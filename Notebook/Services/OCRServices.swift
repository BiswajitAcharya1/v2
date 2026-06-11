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
        let wordScore = min(0.12, rawText.wordLikeRatio * 0.12)
        let tableScore = tables.isEmpty ? 0 : min(0.08, Double(tables.count) * 0.03)
        let garbagePenalty = rawText.garbageRatio * 0.28
        let repetitionPenalty = rawText.repeatedGlyphPenalty * 0.16
        return confidence * 0.58 + lineScore + textScore + wordScore + tableScore - garbagePenalty - repetitionPenalty
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
        let boundary = "vellum-surya-\(UUID().uuidString)"
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
        var results: [OCRScanResult] = []

        for variant in variants {
            let result = await recognize(
                cgImage: variant.image,
                orientation: variant.orientation,
                name: variant.name,
                minimumTextHeight: variant.minimumTextHeight
            )
            results.append(result)
        }
        let best = bestResult(in: results)
        let fused = OCRLineFusion.fuse(results)
        return OCRResultRanker.best(best, fused)
    }

    private static func bestResult(in results: [OCRScanResult]) -> OCRScanResult {
        var best = OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "apple vision")
        for result in results {
            best = OCRResultRanker.best(best, result)
        }
        return best
    }

    private static func recognize(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        name: String,
        minimumTextHeight: Float
    ) async -> OCRScanResult {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sortedForReadingOrder()
                let candidates = observations.compactMap { observation -> VNRecognizedText? in
                    OCRCandidateRanker.bestCandidate(from: observation.topCandidates(6))
                }
                let lines = candidates
                    .map(\.string)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
                    .filter { !$0.isEmpty && $0.garbageRatio < 0.48 }
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
            request.minimumTextHeight = minimumTextHeight
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

private enum OCRCandidateRanker {
    static func bestCandidate(from candidates: [VNRecognizedText]) -> VNRecognizedText? {
        candidates
            .filter { $0.string.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
            .max { score($0) < score($1) }
    }

    private static func score(_ candidate: VNRecognizedText) -> Double {
        let text = candidate.string.normalizedOCRLine
        guard !text.isEmpty else { return -1 }
        let usefulScore = 1 - text.garbageRatio
        let wordScore = text.wordLikeRatio
        let vocabularyScore = text.containsStudentNotebookWord ? 1.0 : 0.0
        let lengthScore = min(0.08, Double(text.count) / 220)
        let repetitionPenalty = text.repeatedGlyphPenalty
        return Double(candidate.confidence) * 0.56
            + usefulScore * 0.18
            + wordScore * 0.14
            + vocabularyScore * 0.08
            + lengthScore
            - repetitionPenalty * 0.22
    }
}

private enum OCRVocabulary {
    static let studentNotebookWords = [
        "algebra", "geometry", "calculus", "derivative", "integral", "equation", "function", "limit",
        "biology", "chemistry", "physics", "molecule", "atom", "cell", "mitosis", "meiosis", "photosynthesis",
        "chlorophyll", "mitochondria", "nucleus", "enzyme", "protein", "ecosystem", "evolution",
        "history", "government", "revolution", "treaty", "empire", "democracy", "constitution", "economy",
        "english", "literature", "theme", "symbolism", "metaphor", "claim", "analysis",
        "thesis", "evidence", "paragraph", "computer", "algorithm", "variable", "loop", "array",
        "hypothesis", "experiment", "example", "definition", "formula", "notes", "homework",
        "quadratic", "polynomial", "matrix", "vector", "slope", "intercept", "velocity", "acceleration",
        "force", "energy", "mass", "gravity", "electron", "proton", "neutron", "acid", "base",
        "literary", "argument", "citation", "source", "primary", "secondary", "outline", "summary"
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
        var minimumTextHeight: Float
    }

    static func variants(from image: UIImage) -> [Variant] {
        guard let base = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.exifOrientation) else {
            return image.cgImage.map {
                [Variant(name: "original", image: $0, orientation: CGImagePropertyOrientation(image.imageOrientation), minimumTextHeight: 0.005)]
            } ?? []
        }

        var variants: [Variant] = []
        let prepared = scaledForHandwriting(base)
        appendVariant(name: "original", image: prepared, minimumTextHeight: 0.0055, to: &variants)
        appendVariant(name: "paper", image: paperNormalized(prepared), minimumTextHeight: 0.005, to: &variants)
        appendVariant(name: "ink", image: highContrastInk(prepared), minimumTextHeight: 0.005, to: &variants)
        appendVariant(name: "pencil", image: faintPencilBoost(prepared), minimumTextHeight: 0.0045, to: &variants)
        appendVariant(name: "shadow", image: shadowLift(prepared), minimumTextHeight: 0.0045, to: &variants)
        appendVariant(name: "cursive", image: cursiveInkLift(prepared), minimumTextHeight: 0.004, to: &variants)
        appendVariant(name: "thin strokes", image: thinStrokeRecovery(prepared), minimumTextHeight: 0.004, to: &variants)
        return variants
    }

    private static func appendVariant(name: String, image: CIImage, minimumTextHeight: Float, to variants: inout [Variant]) {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        variants.append(Variant(name: name, image: cgImage, orientation: .up, minimumTextHeight: minimumTextHeight))
    }

    private static func scaledForHandwriting(_ image: CIImage) -> CIImage {
        let longestSide = max(image.extent.width, image.extent.height)
        guard longestSide > 0, longestSide < 1900 else { return image }
        let scale = min(2.7, 1900 / longestSide)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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

    private static func paperNormalized(_ image: CIImage) -> CIImage {
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = 0.28

        let controls = CIFilter.colorControls()
        controls.inputImage = exposure.outputImage ?? image
        controls.saturation = 0
        controls.contrast = 1.24
        controls.brightness = 0.025

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = controls.outputImage ?? image
        sharpen.radius = 0.82
        sharpen.intensity = 0.46
        return sharpen.outputImage ?? controls.outputImage ?? image
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

    private static func shadowLift(_ image: CIImage) -> CIImage {
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = image
        shadows.shadowAmount = 0.72
        shadows.highlightAmount = 0.84

        let color = CIFilter.colorControls()
        color.inputImage = shadows.outputImage ?? image
        color.saturation = 0
        color.contrast = 1.58
        color.brightness = 0.045
        return color.outputImage ?? shadows.outputImage ?? image
    }

    private static func cursiveInkLift(_ image: CIImage) -> CIImage {
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = image
        shadows.shadowAmount = 0.92
        shadows.highlightAmount = 0.72

        let color = CIFilter.colorControls()
        color.inputImage = shadows.outputImage ?? image
        color.saturation = 0
        color.contrast = 1.92
        color.brightness = 0.02

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = color.outputImage ?? image
        sharpen.radius = 0.55
        sharpen.intensity = 0.92
        return sharpen.outputImage ?? color.outputImage ?? image
    }

    private static func thinStrokeRecovery(_ image: CIImage) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = image
        mono.saturation = 0
        mono.contrast = 1.36
        mono.brightness = 0.12

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = mono.outputImage ?? image
        gamma.power = 0.62

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = gamma.outputImage ?? mono.outputImage ?? image
        sharpen.sharpness = 0.88
        return sharpen.outputImage ?? gamma.outputImage ?? mono.outputImage ?? image
    }

}

private enum OCRLineFusion {
    static func fuse(_ results: [OCRScanResult]) -> OCRScanResult {
        var usable = results.filter { !$0.lines.isEmpty }
        usable.sort { $0.qualityScore > $1.qualityScore }
        guard !usable.isEmpty else {
            return OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "apple vision fused")
        }

        var lines: [String] = []
        var confidenceTotal = 0.0
        var confidenceWeight = 0.0

        for (resultIndex, result) in usable.prefix(3).enumerated() {
            let weight = max(0.18, result.confidence - Double(resultIndex) * 0.07)
            confidenceTotal += result.confidence * weight
            confidenceWeight += weight
            for line in result.lines {
                let cleaned = line.normalizedOCRLine
                guard cleaned.count >= 2, cleaned.garbageRatio < 0.38 else { continue }
                if !lines.contains(where: { existing in existing.isNearDuplicate(of: cleaned) }) {
                    lines.append(cleaned)
                }
            }
        }

        let confidence = min(0.94, max(0.14, confidenceWeight == 0 ? usable[0].confidence : confidenceTotal / confidenceWeight))
        let engineNames = usable.prefix(3).map(\.engine).joined(separator: " + ")
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: usable.flatMap(\.tables),
            confidence: confidence,
            engine: "apple vision fused \(engineNames)"
        )
    }
}

private extension String {
    var normalizedOCRLine: String {
        var text = replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
        text = text.replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " | ", with: " | ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.lowercased()
    }

    var wordLikeRatio: Double {
        let words = split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return 0 }
        let plausible = words.filter { word in
            let letters = word.filter(\.isLetter).count
            let numbers = word.filter(\.isNumber).count
            return word.count >= 2 && (letters >= 2 || numbers >= 1)
        }
        return Double(plausible.count) / Double(words.count)
    }

    var repeatedGlyphPenalty: Double {
        let characters = Array(filter { !$0.isWhitespace })
        guard characters.count >= 5 else { return 0 }
        var repeatedRuns = 0
        var runLength = 1
        for index in 1..<characters.count {
            if characters[index] == characters[index - 1] {
                runLength += 1
                if runLength >= 4 { repeatedRuns += 1 }
            } else {
                runLength = 1
            }
        }
        return min(1, Double(repeatedRuns) / Double(characters.count))
    }

    var containsStudentNotebookWord: Bool {
        let lowercasedText = lowercased()
        return OCRVocabulary.studentNotebookWords.contains { lowercasedText.contains($0) }
    }

    var garbageRatio: Double {
        guard !isEmpty else { return 1 }
        var useful = 0
        for character in self where character.isUsefulOCRCharacter {
            useful += 1
        }
        return 1 - Double(useful) / Double(count)
    }

    func isNearDuplicate(of other: String) -> Bool {
        let lhs = normalizedForOCRComparison
        let rhs = other.normalizedForOCRComparison
        guard !lhs.isEmpty, !rhs.isEmpty else { return true }
        if lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) { return true }
        let shared = Set(lhs.split(separator: " ")).intersection(Set(rhs.split(separator: " "))).count
        let denominator = max(1, min(lhs.split(separator: " ").count, rhs.split(separator: " ").count))
        if Double(shared) / Double(denominator) > 0.72 { return true }
        guard abs(lhs.count - rhs.count) <= 5, max(lhs.count, rhs.count) <= 44 else { return false }
        return lhs.ocrEditDistance(to: rhs) <= max(2, min(lhs.count, rhs.count) / 8)
    }

    private var normalizedForOCRComparison: String {
        var text = lowercased()
        text = text.replacingOccurrences(of: #"[^a-z0-9=+\-/% ]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ocrEditDistance(to other: String) -> Int {
        let a = Array(self)
        let b = Array(other)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
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

private extension Character {
    var isUsefulOCRCharacter: Bool {
        if isLetter || isNumber || isWhitespace { return true }
        return OCRAllowedMarks.characters.contains(self)
    }
}

private enum OCRAllowedMarks {
    static let characters = Set(".,:;+-=()/%'[]{}<>")
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
