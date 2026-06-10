import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
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
        let suryaResult = await surya.recognize(in: image)
        if let suryaResult, suryaResult.isStrongRemoteResult {
            return suryaResult
        }

        let visionResult = await VisionOCRTextScanner.recognize(in: image)
        if let suryaResult {
            return OCRResultRanker.best(suryaResult, visionResult)
        }
        return visionResult
    }
}

private extension OCRScanResult {
    var isStrongRemoteResult: Bool {
        confidence >= 0.84 && lines.count >= 3 && rawText.count >= 24
    }

    var qualityScore: Double {
        let lineScore = min(0.22, Double(lines.count) * 0.018)
        let textScore = min(0.18, Double(rawText.count) / 900)
        let tableScore = tables.isEmpty ? 0 : min(0.08, Double(tables.count) * 0.03)
        let garbagePenalty = rawText.garbageRatio * 0.28
        return confidence * 0.62 + lineScore + textScore + tableScore - garbagePenalty
    }
}

private enum OCRResultRanker {
    static func best(_ lhs: OCRScanResult, _ rhs: OCRScanResult) -> OCRScanResult {
        if lhs.qualityScore == rhs.qualityScore {
            return lhs.rawText.count >= rhs.rawText.count ? lhs : rhs
        }
        return lhs.qualityScore > rhs.qualityScore ? lhs : rhs
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
    static func recognize(in image: UIImage) async -> OCRScanResult {
        let variants = OCRImagePreprocessor.variants(from: image)
        var best = OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "apple vision")

        for variant in variants {
            let result = await recognize(cgImage: variant.image, orientation: variant.orientation, name: variant.name)
            best = OCRResultRanker.best(best, result)
        }
        return best
    }

    private static func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation, name: String) async -> OCRScanResult {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sortedForReadingOrder()
                let candidates = observations.compactMap { observation -> VNRecognizedText? in
                    observation.topCandidates(3).first { candidate in
                        candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
                    }
                }
                let lines = candidates
                    .map(\.string)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
                    .filter { !$0.isEmpty }
                let averageConfidence = candidates.isEmpty
                    ? 0.14
                    : Double(candidates.reduce(Float(0)) { $0 + $1.confidence }) / Double(candidates.count)
                let confidence = min(0.94, max(0.14, averageConfidence))
                continuation.resume(returning: OCRScanResult(
                    rawText: lines.joined(separator: "\n"),
                    lines: lines,
                    tables: [],
                    confidence: confidence,
                    engine: "apple vision \(name)"
                ))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.008
            request.customWords = OCRVocabulary.studentNotebookWords

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: OCRScanResult(
                        rawText: "",
                        lines: [],
                        tables: [],
                        confidence: 0.12,
                        engine: "apple vision \(name)"
                    ))
                }
            }
        }
    }
}

private enum OCRVocabulary {
    static let studentNotebookWords = [
        "algebra", "geometry", "calculus", "derivative", "integral", "equation", "function", "limit",
        "biology", "chemistry", "physics", "molecule", "atom", "cell", "mitosis", "photosynthesis",
        "history", "government", "revolution", "treaty", "empire", "english", "literature", "theme",
        "thesis", "evidence", "paragraph", "computer", "algorithm", "variable", "loop", "array",
        "hypothesis", "experiment", "example", "definition", "formula", "notes", "homework"
    ]
}

private enum OCRImagePreprocessor {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false
    ])

    struct Variant {
        var name: String
        var image: CGImage
        var orientation: CGImagePropertyOrientation
    }

    static func variants(from image: UIImage) -> [Variant] {
        guard let base = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.exifOrientation) else {
            return image.cgImage.map { [Variant(name: "original", image: $0, orientation: CGImagePropertyOrientation(image.imageOrientation))] } ?? []
        }

        let filters: [(String, (CIImage) -> CIImage)] = [
            ("original", { $0 }),
            ("ink", highContrastInk),
            ("pencil", faintPencilBoost),
            ("sharp", sharpenedNotebook)
        ]

        return filters.compactMap { name, transform in
            let output = transform(base)
            guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
            return Variant(name: name, image: cgImage, orientation: .up)
        }
    }

    private static func highContrastInk(_ image: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 0
        color.contrast = 1.42
        color.brightness = 0.035

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = color.outputImage ?? image
        sharpen.sharpness = 0.62
        return sharpen.outputImage ?? color.outputImage ?? image
    }

    private static func faintPencilBoost(_ image: CIImage) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = image
        mono.saturation = 0
        mono.contrast = 1.78
        mono.brightness = 0.09

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = mono.outputImage ?? image
        gamma.power = 0.74

        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = gamma.outputImage ?? mono.outputImage ?? image
        unsharp.radius = 1.3
        unsharp.intensity = 0.72
        return unsharp.outputImage ?? gamma.outputImage ?? mono.outputImage ?? image
    }

    private static func sharpenedNotebook(_ image: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 0.08
        color.contrast = 1.22
        color.brightness = 0.015

        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = color.outputImage ?? image
        unsharp.radius = 0.9
        unsharp.intensity = 0.55
        return unsharp.outputImage ?? color.outputImage ?? image
    }
}

private extension String {
    var normalizedOCRLine: String {
        replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: " | ", with: " | ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var garbageRatio: Double {
        guard !isEmpty else { return 1 }
        let useful = filter { $0.isLetter || $0.isNumber || $0.isWhitespace || ".,:;+-=()/%".contains($0) }.count
        return 1 - Double(useful) / Double(count)
    }

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

private extension Array where Element == VNRecognizedTextObservation {
    func sortedForReadingOrder() -> [VNRecognizedTextObservation] {
        sorted { lhs, rhs in
            let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDelta > 0.028 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
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

private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up: 1
        case .down: 3
        case .left: 8
        case .right: 6
        case .upMirrored: 2
        case .downMirrored: 4
        case .leftMirrored: 5
        case .rightMirrored: 7
        @unknown default: 1
        }
    }
}
