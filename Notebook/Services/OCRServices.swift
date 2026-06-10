import Foundation
import UIKit
@preconcurrency import Vision

@MainActor
protocol OCRServing {
    func recognize(in image: UIImage) async -> OCRScanResult
}

struct OCRScanResult: Hashable {
    var rawText: String
    var lines: [String]
    var tables: [DetectedTable]
    var confidence: Double
    var engine: String
}

struct HybridSuryaOCRService: OCRServing {
    private let surya = SuryaOCRClient(endpoint: SuryaOCRClient.configuredEndpoint)

    func recognize(in image: UIImage) async -> OCRScanResult {
        if let result = await surya.recognize(in: image), !result.lines.isEmpty {
            return result
        }

        let recognizedText = await VisionOCRTextScanner.recognizeText(in: image)
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return OCRScanResult(
            rawText: recognizedText,
            lines: lines,
            tables: [],
            confidence: lines.isEmpty ? 0.18 : 0.74,
            engine: "apple vision"
        )
    }
}

struct SuryaOCRClient {
    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SuryaOCREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["SURYA_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }

    let endpoint: URL?

    func recognize(in image: UIImage) async -> OCRScanResult? {
        guard let endpoint, let imageData = image.jpegData(compressionQuality: 0.88) else { return nil }
        let boundary = "margins-surya-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(imageData: imageData, boundary: boundary)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            return SuryaOCRParser.parse(data)
        } catch {
            return nil
        }
    }

    private func multipartBody(imageData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"scan.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        body.append("ocr\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private enum SuryaOCRParser {
    static func parse(_ data: Data) -> OCRScanResult? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(SuryaOCRResponse.self, from: data) else { return nil }
        let blocks = envelope.resolvedPages
            .flatMap(\.resolvedBlocks)
            .sorted { ($0.readingOrder ?? 0) < ($1.readingOrder ?? 0) }
        guard !blocks.isEmpty else { return nil }

        var lines: [String] = []
        var tables: [DetectedTable] = []
        var confidenceValues: [Double] = []

        for block in blocks {
            if let confidence = block.confidence {
                confidenceValues.append(confidence)
            }
            let html = block.html ?? block.text ?? ""
            let text = html.htmlToPlainText()
            if !text.isEmpty {
                lines += text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            let label = (block.label ?? block.rawLabel ?? "").lowercased()
            if label.contains("table") || html.localizedCaseInsensitiveContains("<table"),
               let table = html.detectedTable(title: "surya table") {
                tables.append(table)
            }
        }

        let confidence = confidenceValues.isEmpty ? 0.86 : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        return OCRScanResult(rawText: lines.joined(separator: "\n"), lines: lines, tables: tables, confidence: confidence, engine: "surya")
    }
}

private struct SuryaOCRResponse: Decodable {
    var pages: [SuryaPage]?
    var blocks: [SuryaBlock]?
    var results: [String: [SuryaPage]]?

    var resolvedPages: [SuryaPage] {
        if let pages { return pages }
        if let results { return results.values.flatMap { $0 } }
        if let blocks { return [SuryaPage(blocks: blocks)] }
        return []
    }
}

private struct SuryaPage: Decodable {
    var blocks: [SuryaBlock]?
    var resolvedBlocks: [SuryaBlock] { blocks ?? [] }
}

private struct SuryaBlock: Decodable {
    var label: String?
    var rawLabel: String?
    var readingOrder: Int?
    var html: String?
    var text: String?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case label
        case rawLabel = "raw_label"
        case readingOrder = "reading_order"
        case html
        case text
        case confidence
    }
}

private enum VisionOCRTextScanner {
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

private extension String {
    func htmlToPlainText() -> String {
        self
            .replacingOccurrences(of: "</tr>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</t[dh]>", with: " | ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
    }

    func detectedTable(title: String) -> DetectedTable? {
        let rows = regexCaptures(pattern: #"<tr[^>]*>(.*?)</tr>"#)
            .map { fragment in
                fragment
                    .regexCaptures(pattern: #"<t[dh][^>]*>(.*?)</t[dh]>"#)
                    .map { $0.htmlToPlainText().replacingOccurrences(of: "\n", with: " ") }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }

        guard rows.count >= 2 else { return nil }
        return DetectedTable(title: title, headers: rows[0], rows: Array(rows.dropFirst()))
    }

    private func regexCaptures(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: self) else { return nil }
            return String(self[range])
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
