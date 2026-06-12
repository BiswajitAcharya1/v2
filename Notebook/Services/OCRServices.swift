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

struct OCREngineReadiness: Hashable {
    var name: String
    var isConfigured: Bool
    var role: String
}

enum OCRPipelineReadiness {
    static var engines: [OCREngineReadiness] {
        [
            OCREngineReadiness(name: "mistral ocr", isConfigured: MistralOCRClient.configuredAPIKey?.isEmpty == false, role: "document understanding"),
            OCREngineReadiness(name: "google vision weekly", isConfigured: GoogleVisionOCRClient.configuredAPIKey?.isEmpty == false, role: "printed and handwriting ocr"),
            OCREngineReadiness(name: "azure document intelligence", isConfigured: AzureDocumentIntelligenceReadOCRClient.configuredAPIKey?.isEmpty == false && AzureDocumentIntelligenceReadOCRClient.configuredEndpoint != nil, role: "handwriting read model"),
            OCREngineReadiness(name: "chandra", isConfigured: ChandraOCRClient.configuredEndpoint != nil, role: "structured handwriting and layout"),
            OCREngineReadiness(name: "surya", isConfigured: SuryaOCRClient.configuredEndpoint != nil, role: "layout and table recovery"),
            OCREngineReadiness(name: "vision language adjudicator", isConfigured: VisionLanguageOCRClient.configuredEndpoint != nil, role: "messy cursive correction"),
            OCREngineReadiness(name: "apple vision", isConfigured: true, role: "offline fallback")
        ]
    }

    static var isDoctorNoteReady: Bool {
        let configured = engines.filter(\.isConfigured).map(\.name)
        let hasPrimaryOCR = configured.contains("mistral ocr")
            || configured.contains("google vision weekly")
            || configured.contains("azure document intelligence")
            || configured.contains("chandra")
        return hasPrimaryOCR && configured.contains("vision language adjudicator")
    }
}

private struct OCRUploadCandidate {
    var name: String
    var data: Data
}

struct HybridSuryaOCRService: OCRServing {
    private let mistral = MistralOCRClient()
    private let googleVision = GoogleVisionOCRClient()
    private let azureVision = AzureVisionReadOCRClient()
    private let azureDocument = AzureDocumentIntelligenceReadOCRClient()
    private let visionLanguage = VisionLanguageOCRClient()
    private let chandra = ChandraOCRClient()
    private let surya = SuryaOCRClient(endpoint: SuryaOCRClient.configuredEndpoint)

    func recognize(in image: UIImage) async -> OCRScanResult {
        async let mistralResult = mistral.recognize(in: image)
        async let googleResult = googleVision.recognize(in: image)
        async let azureResult = azureVision.recognize(in: image)
        async let azureDocumentResult = azureDocument.recognize(in: image)
        async let visionLanguageResult = visionLanguage.recognize(in: image)
        async let chandraResult = chandra.recognize(in: image)
        async let suryaResult = surya.recognize(in: image)

        let remoteResults = await [mistralResult, googleResult, azureResult, azureDocumentResult, visionLanguageResult, chandraResult, suryaResult].compactMap(\.self)
        let visionResult = await VisionOCRTextScanner.recognize(in: image)
        let consensus = OCRConsensusBuilder.make(from: remoteResults + [visionResult])
        if let adjudicated = await visionLanguage.adjudicate(in: image, candidates: remoteResults + [visionResult, consensus]),
           adjudicated.isStrongRemoteResult {
            return adjudicated
        }
        if let elite = remoteResults.first(where: \.isEliteRemoteResult) {
            return elite
        }
        if let bestRemote = OCRResultRanker.bestRemote(remoteResults),
           bestRemote.isStrongRemoteResult {
            return bestRemote
        }

        return OCRReliabilityGate.finalResult(from: remoteResults + [visionResult], consensus: consensus)
    }
}

private extension OCRScanResult {
    var isEliteRemoteResult: Bool {
        (engine.localizedCaseInsensitiveContains("mistral")
            || engine.localizedCaseInsensitiveContains("google")
            || engine.localizedCaseInsensitiveContains("document intelligence")
            || engine.localizedCaseInsensitiveContains("vision language")
            || engine.localizedCaseInsensitiveContains("chandra")
            || engine.localizedCaseInsensitiveContains("azure"))
            && confidence >= 0.9
            && lines.count >= 4
            && rawText.count >= 40
            && rawText.wordLikeRatio >= 0.42
            && rawText.garbageRatio < 0.22
            && !hasSevereOCRArtifacts
    }

    var isStrongRemoteResult: Bool {
        confidence >= 0.84
            && lines.count >= 3
            && rawText.count >= 24
            && rawText.wordLikeRatio >= 0.34
            && rawText.garbageRatio < 0.32
            && !hasSevereOCRArtifacts
    }

    var qualityScore: Double {
        let engineBoost: Double
        if engine.localizedCaseInsensitiveContains("mistral") {
            engineBoost = 0.08
        } else if engine.localizedCaseInsensitiveContains("google") {
            engineBoost = 0.07
        } else if engine.localizedCaseInsensitiveContains("document intelligence") {
            engineBoost = 0.075
        } else if engine.localizedCaseInsensitiveContains("vision language") {
            engineBoost = 0.072
        } else if engine.localizedCaseInsensitiveContains("chandra") {
            engineBoost = 0.078
        } else if engine.localizedCaseInsensitiveContains("azure") {
            engineBoost = 0.065
        } else if engine.localizedCaseInsensitiveContains("surya") {
            engineBoost = 0.045
        } else {
            engineBoost = 0
        }
        let lineScore = min(0.22, Double(lines.count) * 0.018)
        let textScore = min(0.18, Double(rawText.count) / 900)
        let wordScore = min(0.12, rawText.wordLikeRatio * 0.12)
        let tableScore = tables.isEmpty ? 0 : min(0.08, Double(tables.count) * 0.03)
        let garbagePenalty = rawText.garbageRatio * 0.28
        let repetitionPenalty = rawText.repeatedGlyphPenalty * 0.16
        let artifactPenalty = rawText.ocrArtifactPenalty * 0.22
        return confidence * 0.58 + engineBoost + lineScore + textScore + wordScore + tableScore - garbagePenalty - repetitionPenalty
            - artifactPenalty
    }

    var hasSevereOCRArtifacts: Bool {
        rawText.ocrArtifactPenalty > 0.48 || rawText.repeatedGlyphPenalty > 0.22
    }
}

private enum OCRReliabilityGate {
    static func finalResult(from results: [OCRScanResult], consensus: OCRScanResult) -> OCRScanResult {
        let usable = results.filter { !$0.lines.isEmpty }
        let best = OCRResultRanker.best(usable)
        guard !usable.isEmpty else { return consensus }

        if shouldPreferConsensus(best: best, consensus: consensus, competitors: usable) {
            return OCRResultRanker.best(consensus, boostedConsensus(consensus, comparedTo: best))
        }
        return OCRResultRanker.best(consensus, best)
    }

    private static func shouldPreferConsensus(best: OCRScanResult, consensus: OCRScanResult, competitors: [OCRScanResult]) -> Bool {
        guard !consensus.lines.isEmpty else { return false }
        if best.hasSevereOCRArtifacts { return true }
        if best.rawText.wordLikeRatio < 0.42 && consensus.rawText.wordLikeRatio > best.rawText.wordLikeRatio + 0.12 { return true }
        if consensus.lines.count >= best.lines.count + 2 && consensus.rawText.garbageRatio <= best.rawText.garbageRatio + 0.04 { return true }

        let agreement = competitors
            .filter { $0.engine != best.engine && !$0.lines.isEmpty }
            .prefix(4)
            .map { best.lineAgreement(with: $0) }
        let averageAgreement = agreement.isEmpty ? 1 : agreement.reduce(0, +) / Double(agreement.count)
        return averageAgreement < 0.18 && consensus.rawText.count >= best.rawText.count
    }

    private static func boostedConsensus(_ consensus: OCRScanResult, comparedTo best: OCRScanResult) -> OCRScanResult {
        var boosted = consensus
        boosted.confidence = min(0.95, max(consensus.confidence, best.confidence - 0.015))
        boosted.engine = "reliability checked \(consensus.engine)"
        return boosted
    }
}

private enum OCRResultRanker {
    static func best(_ lhs: OCRScanResult, _ rhs: OCRScanResult) -> OCRScanResult {
        if lhs.qualityScore == rhs.qualityScore {
            return lhs.rawText.count >= rhs.rawText.count ? lhs : rhs
        }
        return lhs.qualityScore > rhs.qualityScore ? lhs : rhs
    }

    static func best(_ results: OCRScanResult?...) -> OCRScanResult {
        best(results.compactMap(\.self))
    }

    static func best(_ results: [OCRScanResult]) -> OCRScanResult {
        results.reduce(OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "ocr unavailable"), best)
    }

    static func bestRemote(_ results: OCRScanResult?...) -> OCRScanResult? {
        bestRemote(results.compactMap(\.self))
    }

    static func bestRemote(_ remoteResults: [OCRScanResult]) -> OCRScanResult? {
        guard !remoteResults.isEmpty else { return nil }
        return remoteResults.dropFirst().reduce(remoteResults[0], best)
    }
}

private extension OCRScanResult {
    func lineAgreement(with other: OCRScanResult) -> Double {
        guard !lines.isEmpty, !other.lines.isEmpty else { return 0 }
        let matches = lines.filter { line in
            other.lines.contains { $0.isNearDuplicate(of: line) }
        }
        return Double(matches.count) / Double(max(lines.count, other.lines.count))
    }
}

private enum OCRConsensusBuilder {
    static func make(from results: [OCRScanResult]) -> OCRScanResult {
        let usable = results
            .filter { !$0.lines.isEmpty }
            .sorted { $0.qualityScore > $1.qualityScore }
        guard let best = usable.first else {
            return OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "ocr consensus")
        }

        var lines = best.lines
        for result in usable.dropFirst().prefix(3) {
            for line in result.lines {
                let cleaned = line.normalizedOCRLine
                guard cleaned.count >= 2, cleaned.garbageRatio < 0.38 else { continue }
                if !lines.contains(where: { $0.isNearDuplicate(of: cleaned) }) {
                    lines.append(cleaned)
                }
            }
        }

        let confidence = min(0.97, max(best.confidence, usable.prefix(3).map(\.confidence).reduce(0, +) / Double(min(3, usable.count))) + 0.02)
        let engines = usable.prefix(3).map(\.engine).joined(separator: " + ")
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: usable.flatMap(\.tables),
            confidence: confidence,
            engine: "consensus \(engines)"
        )
    }
}

struct MistralOCRClient {
    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MistralOCRAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["MISTRAL_OCR_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"], !value.isEmpty {
            return value
        }
        return nil
    }

    static var configuredEndpoint: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MistralOCREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["MISTRAL_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return URL(string: "https://api.mistral.ai/v1/ocr")!
    }

    static var configuredModel: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MistralOCRModel") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["MISTRAL_OCR_MODEL"], !value.isEmpty {
            return value
        }
        return "mistral-ocr-latest"
    }

    let apiKey: String?
    let endpoint: URL
    let model: String

    init(apiKey: String? = Self.configuredAPIKey, endpoint: URL = Self.configuredEndpoint, model: String = Self.configuredModel) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        let usesMistralHost = endpoint.host?.localizedCaseInsensitiveContains("mistral.ai") == true
        guard !usesMistralHost || apiKey?.isEmpty == false else { return nil }

        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let document = MistralOCRDocument(
                type: "image_url",
                imageURL: "data:image/jpeg;base64,\(candidate.data.base64EncodedString())"
            )
            let payload = MistralOCRRequest(
                model: model,
                document: document,
                tableFormat: "html",
                confidenceScoresGranularity: "page",
                includeImageBase64: false
            )

            do {
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                      var result = MistralOCRParser.parse(data, fallbackModel: model) else { continue }
                result.engine = "\(result.engine) \(candidate.name)"
                bestResult = OCRResultRanker.best(bestResult, result)
                if result.isEliteRemoteResult { return result }
            } catch {
                continue
            }
        }
        return bestResult
    }
}

private struct MistralOCRRequest: Encodable {
    var model: String
    var document: MistralOCRDocument
    var tableFormat: String
    var confidenceScoresGranularity: String
    var includeImageBase64: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case document
        case tableFormat = "table_format"
        case confidenceScoresGranularity = "confidence_scores_granularity"
        case includeImageBase64 = "include_image_base64"
    }
}

private struct MistralOCRDocument: Encodable {
    var type: String
    var imageURL: String

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
    }
}

private enum MistralOCRParser {
    static func parse(_ data: Data, fallbackModel: String) -> OCRScanResult? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(MistralOCRResponse.self, from: data) else { return nil }

        let pageMarkdown = envelope.pages
            .compactMap(\.markdown)
            .map(\.markdownToPlainText)
            .filter { !$0.isEmpty }
        var lines = pageMarkdown
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }

        var seen = Set<String>()
        lines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }

        let tables = envelope.pages.flatMap { page in
            page.tables?.compactMap { table -> DetectedTable? in
                if let html = table.html, let detected = html.detectedTable(title: table.title ?? "mistral table") {
                    return detected
                }
                if let markdown = table.markdown ?? table.content {
                    return markdown.detectedMarkdownTable(title: table.title ?? "mistral table")
                }
                return nil
            } ?? []
        }

        let confidenceValues = envelope.pages.compactMap { page in
            page.confidenceScores?.averagePageConfidenceScore ?? page.confidenceScores?.minimumPageConfidenceScore
        }
        let confidence = confidenceValues.isEmpty
            ? 0.9
            : min(0.98, max(0.18, confidenceValues.reduce(0, +) / Double(confidenceValues.count)))
        guard !lines.isEmpty || !tables.isEmpty else { return nil }
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: tables,
            confidence: confidence,
            engine: envelope.model ?? fallbackModel
        )
    }
}

private struct MistralOCRResponse: Decodable {
    var pages: [MistralOCRPage]
    var model: String?
}

private struct MistralOCRPage: Decodable {
    var markdown: String?
    var tables: [MistralOCRTable]?
    var confidenceScores: MistralConfidenceScores?

    enum CodingKeys: String, CodingKey {
        case markdown
        case tables
        case confidenceScores = "confidence_scores"
    }
}

private struct MistralOCRTable: Decodable {
    var title: String?
    var html: String?
    var markdown: String?
    var content: String?
}

private struct MistralConfidenceScores: Decodable {
    var averagePageConfidenceScore: Double?
    var minimumPageConfidenceScore: Double?

    enum CodingKeys: String, CodingKey {
        case averagePageConfidenceScore = "average_page_confidence_score"
        case minimumPageConfidenceScore = "minimum_page_confidence_score"
    }
}

struct GoogleVisionOCRClient {
    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GoogleVisionAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GOOGLE_VISION_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_VISION_API_KEY"], !value.isEmpty {
            return value
        }
        return nil
    }

    static var configuredEndpoint: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GoogleVisionOCREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["GOOGLE_VISION_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return URL(string: "https://vision.googleapis.com/v1/images:annotate")!
    }

    static var configuredModel: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GoogleVisionOCRModel") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GOOGLE_VISION_OCR_MODEL"], !value.isEmpty {
            return value
        }
        return "builtin/weekly"
    }

    let apiKey: String?
    let endpoint: URL
    let model: String

    init(apiKey: String? = Self.configuredAPIKey, endpoint: URL = Self.configuredEndpoint, model: String = Self.configuredModel) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        let usesGoogleHost = endpoint.host?.localizedCaseInsensitiveContains("googleapis.com") == true
        guard !usesGoogleHost || apiKey?.isEmpty == false else { return nil }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if usesGoogleHost, let apiKey {
            var queryItems = components?.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "key" }) {
                queryItems.append(URLQueryItem(name: "key", value: apiKey))
            }
            components?.queryItems = queryItems
        }
        let url = components?.url ?? endpoint

        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload = GoogleVisionOCRRequest(
                requests: [
                    GoogleVisionAnnotateRequest(
                        image: GoogleVisionImage(content: candidate.data.base64EncodedString()),
                        features: [GoogleVisionFeature(type: "DOCUMENT_TEXT_DETECTION", maxResults: 1, model: model)],
                        imageContext: GoogleVisionImageContext(languageHints: OCRLanguageHints.vision)
                    )
                ]
            )

            do {
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                      var result = GoogleVisionOCRParser.parse(data) else { continue }
                result.engine = "\(result.engine) \(candidate.name)"
                bestResult = OCRResultRanker.best(bestResult, result)
                if result.isEliteRemoteResult { return result }
            } catch {
                continue
            }
        }
        return bestResult
    }
}

private struct GoogleVisionOCRRequest: Encodable {
    var requests: [GoogleVisionAnnotateRequest]
}

private struct GoogleVisionAnnotateRequest: Encodable {
    var image: GoogleVisionImage
    var features: [GoogleVisionFeature]
    var imageContext: GoogleVisionImageContext
}

private struct GoogleVisionImage: Encodable {
    var content: String
}

private struct GoogleVisionFeature: Encodable {
    var type: String
    var maxResults: Int
    var model: String
}

private struct GoogleVisionImageContext: Encodable {
    var languageHints: [String]
}

private enum GoogleVisionOCRParser {
    static func parse(_ data: Data) -> OCRScanResult? {
        guard let envelope = try? JSONDecoder().decode(GoogleVisionOCRResponse.self, from: data),
              let response = envelope.responses.first,
              response.error == nil else {
            return nil
        }

        let rawText = response.fullTextAnnotation?.text
            ?? response.textAnnotations?.first?.description
            ?? ""
        var lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }

        let structuredLines = response.fullTextAnnotation?.pages?.flatMap { $0.blocks ?? [] }.flatMap { $0.paragraphs ?? [] }.map { paragraph in
            (paragraph.words ?? []).map { word in
                (word.symbols ?? []).map(\.text).joined()
            }
            .joined(separator: " ")
            .normalizedOCRLine
        } ?? []

        for line in structuredLines where !line.isEmpty && line.garbageRatio < 0.44 {
            if !lines.contains(where: { $0.isNearDuplicate(of: line) }) {
                lines.append(line)
            }
        }

        var seen = Set<String>()
        lines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }

        let confidenceValues = response.fullTextAnnotation?.pages?.flatMap { $0.blocks ?? [] }.flatMap { $0.paragraphs ?? [] }.compactMap(\.confidence) ?? []
        let confidence = confidenceValues.isEmpty
            ? 0.88
            : min(0.98, max(0.18, confidenceValues.reduce(0, +) / Double(confidenceValues.count)))
        guard !lines.isEmpty else { return nil }
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: [],
            confidence: confidence,
            engine: "google vision document text"
        )
    }
}

private struct GoogleVisionOCRResponse: Decodable {
    var responses: [GoogleVisionAnnotateResponse]
}

private struct GoogleVisionAnnotateResponse: Decodable {
    var fullTextAnnotation: GoogleVisionFullTextAnnotation?
    var textAnnotations: [GoogleVisionTextAnnotation]?
    var error: GoogleVisionError?
}

private struct GoogleVisionError: Decodable {
    var message: String?
}

private struct GoogleVisionTextAnnotation: Decodable {
    var description: String?
}

private struct GoogleVisionFullTextAnnotation: Decodable {
    var text: String?
    var pages: [GoogleVisionPage]?
}

private struct GoogleVisionPage: Decodable {
    var blocks: [GoogleVisionBlock]?
}

private struct GoogleVisionBlock: Decodable {
    var paragraphs: [GoogleVisionParagraph]?
    var confidence: Double?
}

private struct GoogleVisionParagraph: Decodable {
    var words: [GoogleVisionWord]?
    var confidence: Double?
}

private struct GoogleVisionWord: Decodable {
    var symbols: [GoogleVisionSymbol]?
    var confidence: Double?
}

private struct GoogleVisionSymbol: Decodable {
    var text: String
    var confidence: Double?
}

struct AzureVisionReadOCRClient {
    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AzureVisionAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_VISION_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_COMPUTER_VISION_KEY"], !value.isEmpty {
            return value
        }
        return nil
    }

    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AzureVisionReadEndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_VISION_READ_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_VISION_ENDPOINT"],
           let base = URL(string: value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), !value.isEmpty {
            return base.appendingPathComponent("vision/v3.2/read/analyze")
        }
        return nil
    }

    let apiKey: String?
    let endpoint: URL?

    init(apiKey: String? = Self.configuredAPIKey, endpoint: URL? = Self.configuredEndpoint) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        guard let endpoint, let apiKey, !apiKey.isEmpty else { return nil }
        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            guard let operationURL = await submit(candidate: candidate, endpoint: endpoint, apiKey: apiKey),
                  var result = await poll(operationURL: operationURL, apiKey: apiKey) else {
                continue
            }
            result.engine = "\(result.engine) \(candidate.name)"
            bestResult = OCRResultRanker.best(bestResult, result)
            if result.isEliteRemoteResult { return result }
        }
        return bestResult
    }

    private func submit(candidate: OCRUploadCandidate, endpoint: URL, apiKey: String) async -> URL? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = candidate.data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let location = http.value(forHTTPHeaderField: "Operation-Location"),
                  let url = URL(string: location) else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    private func poll(operationURL: URL, apiKey: String) async -> OCRScanResult? {
        for attempt in 0..<8 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(450 + attempt * 180))
            }
            var request = URLRequest(url: operationURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 45
            request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
                guard let result = AzureVisionReadOCRParser.parse(data) else { continue }
                if result.engine.localizedCaseInsensitiveContains("running") {
                    continue
                }
                return result
            } catch {
                return nil
            }
        }
        return nil
    }
}

private enum AzureVisionReadOCRParser {
    static func parse(_ data: Data) -> OCRScanResult? {
        guard let envelope = try? JSONDecoder().decode(AzureReadResponse.self, from: data) else { return nil }
        let status = envelope.status?.lowercased() ?? ""
        if status == "running" || status == "notstarted" {
            return OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "azure read running")
        }
        guard status == "succeeded" else { return nil }

        let readLines = envelope.analyzeResult?.readResults?.flatMap { $0.lines ?? [] } ?? []
        var lines = readLines
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }

        var seen = Set<String>()
        lines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }

        let confidenceValues = readLines.flatMap { $0.words ?? [] }.compactMap(\.confidence)
        let confidence = confidenceValues.isEmpty
            ? 0.88
            : min(0.98, max(0.18, confidenceValues.reduce(0, +) / Double(confidenceValues.count)))
        guard !lines.isEmpty else { return nil }
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: [],
            confidence: confidence,
            engine: "azure read"
        )
    }
}

private struct AzureReadResponse: Decodable {
    var status: String?
    var analyzeResult: AzureAnalyzeResult?
}

private struct AzureAnalyzeResult: Decodable {
    var readResults: [AzureReadPage]?
}

private struct AzureReadPage: Decodable {
    var lines: [AzureReadLine]?
}

private struct AzureReadLine: Decodable {
    var text: String
    var words: [AzureReadWord]?
}

private struct AzureReadWord: Decodable {
    var text: String
    var confidence: Double?
}

struct AzureDocumentIntelligenceReadOCRClient {
    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AzureDocumentIntelligenceAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_DOCUMENT_INTELLIGENCE_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_FORM_RECOGNIZER_KEY"], !value.isEmpty {
            return value
        }
        return AzureVisionReadOCRClient.configuredAPIKey
    }

    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AzureDocumentIntelligenceEndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return analyzeURL(from: url)
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return analyzeURL(from: url)
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_FORM_RECOGNIZER_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return analyzeURL(from: url)
        }
        if let value = ProcessInfo.processInfo.environment["AZURE_VISION_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return analyzeURL(from: url)
        }
        return nil
    }

    private static func analyzeURL(from endpoint: URL) -> URL {
        let absolute = endpoint.absoluteString
        if absolute.localizedCaseInsensitiveContains("documentModels") {
            return endpoint
        }
        let trimmed = absolute.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let api = "documentintelligence/documentModels/prebuilt-read:analyze?_overload=analyzeDocument&api-version=2024-11-30"
        return URL(string: "\(trimmed)/\(api)") ?? endpoint
    }

    let apiKey: String?
    let endpoint: URL?

    init(apiKey: String? = Self.configuredAPIKey, endpoint: URL? = Self.configuredEndpoint) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        guard let endpoint, let apiKey, !apiKey.isEmpty else { return nil }
        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            guard let operationURL = await submit(candidate: candidate, endpoint: endpoint, apiKey: apiKey),
                  var result = await poll(operationURL: operationURL, apiKey: apiKey) else {
                continue
            }
            result.engine = "\(result.engine) \(candidate.name)"
            bestResult = OCRResultRanker.best(bestResult, result)
            if result.isEliteRemoteResult { return result }
        }
        return bestResult
    }

    private func submit(candidate: OCRUploadCandidate, endpoint: URL, apiKey: String) async -> URL? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = AzureDocumentAnalyzeRequest(base64Source: candidate.data.base64EncodedString())

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let location = http.value(forHTTPHeaderField: "Operation-Location"),
                  let url = URL(string: location) else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    private func poll(operationURL: URL, apiKey: String) async -> OCRScanResult? {
        for attempt in 0..<9 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(520 + attempt * 220))
            }
            var request = URLRequest(url: operationURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 45
            request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
                guard let result = AzureDocumentIntelligenceReadParser.parse(data) else { continue }
                if result.engine.localizedCaseInsensitiveContains("running") {
                    continue
                }
                return result
            } catch {
                return nil
            }
        }
        return nil
    }
}

private struct AzureDocumentAnalyzeRequest: Encodable {
    var base64Source: String
}

private enum AzureDocumentIntelligenceReadParser {
    static func parse(_ data: Data) -> OCRScanResult? {
        guard let envelope = try? JSONDecoder().decode(AzureDocumentReadResponse.self, from: data) else { return nil }
        let status = envelope.status?.lowercased() ?? ""
        if status == "running" || status == "notstarted" {
            return OCRScanResult(rawText: "", lines: [], tables: [], confidence: 0.12, engine: "azure document intelligence running")
        }
        guard status == "succeeded", let analyzeResult = envelope.analyzeResult else { return nil }

        var lines = (analyzeResult.pages ?? []).flatMap { page in
            page.lines ?? []
        }
        .map(\.content)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
        .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }

        if lines.isEmpty, let content = analyzeResult.content {
            lines = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
                .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }
        }

        var seen = Set<String>()
        lines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }

        let confidenceValues = (analyzeResult.pages ?? [])
            .flatMap { $0.words ?? [] }
            .compactMap(\.confidence)
        let confidence = confidenceValues.isEmpty
            ? 0.9
            : min(0.98, max(0.18, confidenceValues.reduce(0, +) / Double(confidenceValues.count)))
        guard !lines.isEmpty else { return nil }
        return OCRScanResult(
            rawText: lines.joined(separator: "\n"),
            lines: lines,
            tables: [],
            confidence: confidence,
            engine: "azure document intelligence read"
        )
    }
}

private struct AzureDocumentReadResponse: Decodable {
    var status: String?
    var analyzeResult: AzureDocumentAnalyzeResult?
}

private struct AzureDocumentAnalyzeResult: Decodable {
    var content: String?
    var pages: [AzureDocumentPage]?
}

private struct AzureDocumentPage: Decodable {
    var lines: [AzureDocumentLine]?
    var words: [AzureDocumentWord]?
}

private struct AzureDocumentLine: Decodable {
    var content: String
}

private struct AzureDocumentWord: Decodable {
    var content: String
    var confidence: Double?
}

struct VisionLanguageOCRClient {
    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VisionLanguageOCRAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["VISION_LANGUAGE_OCR_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GEMMA_VISION_OCR_API_KEY"], !value.isEmpty {
            return value
        }
        return nil
    }

    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VisionLanguageOCREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["VISION_LANGUAGE_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["GEMMA_VISION_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }

    static var configuredModel: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VisionLanguageOCRModel") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["VISION_LANGUAGE_OCR_MODEL"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GEMMA_VISION_OCR_MODEL"], !value.isEmpty {
            return value
        }
        return "gemma-4-12b-it"
    }

    let apiKey: String?
    let endpoint: URL?
    let model: String

    init(apiKey: String? = Self.configuredAPIKey, endpoint: URL? = Self.configuredEndpoint, model: String = Self.configuredModel) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        guard let endpoint else { return nil }
        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let payload = VisionLanguageOCRRequest(
                model: model,
                imageBase64: candidate.data.base64EncodedString(),
                prompt: Self.handwritingPrompt,
                responseFormat: "lines"
            )

            do {
                request.httpBody = try JSONEncoder().encode(payload)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                      var result = VisionLanguageOCRParser.parse(data, fallbackModel: model) else {
                    continue
                }
                result.engine = "\(result.engine) \(candidate.name)"
                bestResult = OCRResultRanker.best(bestResult, result)
                if result.isEliteRemoteResult { return result }
            } catch {
                continue
            }
        }
        return bestResult
    }

    func adjudicate(in image: UIImage, candidates: [OCRScanResult]) async -> OCRScanResult? {
        guard let endpoint else { return nil }
        let usefulCandidates = candidates
            .filter { !$0.lines.isEmpty }
            .sorted { $0.qualityScore > $1.qualityScore }
        guard usefulCandidates.count >= 2 else { return nil }

        guard let candidate = OCRImagePreprocessor.remoteUploadCandidates(from: image).first else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 140
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = VisionLanguageOCRRequest(
            model: model,
            imageBase64: candidate.data.base64EncodedString(),
            prompt: Self.adjudicationPrompt(candidates: usefulCandidates),
            responseFormat: "lines"
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  var result = VisionLanguageOCRParser.parse(data, fallbackModel: model) else {
                return nil
            }
            result.engine = "vision language adjudicated \(model)"
            let bestInput = OCRResultRanker.best(usefulCandidates)
            guard result.rawText.count >= max(12, Int(Double(bestInput.rawText.count) * 0.45)),
                  result.rawText.garbageRatio <= min(0.38, bestInput.rawText.garbageRatio + 0.08) else {
                return nil
            }
            result.confidence = min(0.96, max(result.confidence, bestInput.confidence + 0.025))
            return result
        } catch {
            return nil
        }
    }

    private static let handwritingPrompt = """
    transcribe this student notebook page as faithfully as possible. preserve the author's words, line breaks, math symbols, tables, headings, and crossed-through context when readable. this may contain messy cursive, joined letters, faint pencil, tilted paper, mixed printed and handwritten notes, diagrams, or formulas. do not summarize. do not invent missing words. if a word is uncertain, infer only when the surrounding sentence makes the original handwriting clear.
    """

    private static func adjudicationPrompt(candidates: [OCRScanResult]) -> String {
        let candidateText = candidates.prefix(5).enumerated().map { index, result in
            """
            candidate \(index + 1) from \(result.engine), confidence \(String(format: "%.2f", result.confidence)):
            \(result.rawText)
            """
        }
        .joined(separator: "\n\n")

        return """
        transcribe the student notebook page from the image. use the candidate transcripts below only as evidence, not as final truth. resolve messy cursive, joined letters, faint pencil, formulas, arrows, tables, and abbreviations by comparing the image against the candidates. preserve the student's words and line breaks. do not summarize, paraphrase, add explanations, or invent content that is not supported by the image. if two candidates disagree, choose the reading best supported by the visible handwriting and surrounding context. return only the final transcription as clean lines.

        \(candidateText)
        """
    }
}

private struct VisionLanguageOCRRequest: Encodable {
    var model: String
    var imageBase64: String
    var prompt: String
    var responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model
        case imageBase64 = "image_base64"
        case prompt
        case responseFormat = "response_format"
    }
}

private enum VisionLanguageOCRParser {
    static func parse(_ data: Data, fallbackModel: String) -> OCRScanResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let text = extractText(from: json)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }
        guard !lines.isEmpty else { return nil }
        var seen = Set<String>()
        let uniqueLines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }
        let confidence = min(0.94, max(0.62, uniqueLines.map(\.wordLikeRatio).reduce(0, +) / Double(max(1, uniqueLines.count))))
        return OCRScanResult(
            rawText: uniqueLines.joined(separator: "\n"),
            lines: uniqueLines,
            tables: text.detectedMarkdownTable(title: "vision language table").map { [$0] } ?? [],
            confidence: confidence,
            engine: "vision language \(fallbackModel)"
        )
    }

    private static func extractText(from json: Any) -> String {
        if let string = json as? String { return string }
        if let array = json as? [Any] {
            return array
                .map { extractText(from: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        guard let object = json as? [String: Any] else { return "" }

        if let text = object["text"] as? String { return text }
        if let text = object["output_text"] as? String { return text }
        if let text = object["markdown"] as? String { return text.markdownToPlainText }
        if let lines = object["lines"] as? [String] { return lines.joined(separator: "\n") }
        if let result = object["result"] { return extractText(from: result) }
        if let output = object["output"] { return extractText(from: output) }
        if let message = object["message"] { return extractText(from: message) }

        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first {
            if let text = first["text"] as? String { return text }
            if let text = first["output_text"] as? String { return text }
            if let message = first["message"] as? [String: Any],
               let content = message["content"] {
                return extractText(from: content)
            }
        }

        if let content = object["content"] as? [[String: Any]] {
            return content.compactMap { item in
                item["text"] as? String
                    ?? item["output_text"] as? String
                    ?? item["content"] as? String
                    ?? item["value"] as? String
            }
            .joined(separator: "\n")
        }
        if let content = object["content"] as? String { return content }
        return ""
    }
}

struct ChandraOCRClient {
    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ChandraOCREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["CHANDRA_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["DATALAB_OCR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }

    static var configuredAPIKey: String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ChandraOCRAPIKey") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["CHANDRA_OCR_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["DATALAB_API_KEY"], !value.isEmpty {
            return value
        }
        return nil
    }

    let endpoint: URL?
    let apiKey: String?

    init(endpoint: URL? = Self.configuredEndpoint, apiKey: String? = Self.configuredAPIKey) {
        self.endpoint = endpoint
        self.apiKey = apiKey
    }

    func recognize(in image: UIImage) async -> OCRScanResult? {
        guard let endpoint else { return nil }
        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            do {
                guard var result = try await submit(candidate: candidate, endpoint: endpoint) else { continue }
                result.engine = "\(result.engine) \(candidate.name)"
                bestResult = OCRResultRanker.best(bestResult, result)
                if result.isEliteRemoteResult { return result }
            } catch {
                continue
            }
        }
        return bestResult
    }

    private func submit(candidate: OCRUploadCandidate, endpoint: URL) async throws -> OCRScanResult? {
        if let result = try await submitMultipart(candidate: candidate, endpoint: endpoint) {
            return result
        }
        return try await submitJSON(candidate: candidate, endpoint: endpoint)
    }

    private func submitMultipart(candidate: OCRUploadCandidate, endpoint: URL) async throws -> OCRScanResult? {
        let boundary = "cahier-chandra-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 100
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = multipartBody(imageData: candidate.data, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard 200..<300 ~= http.statusCode else { return nil }
        return ChandraOCRParser.parse(data)
    }

    private func submitJSON(candidate: OCRUploadCandidate, endpoint: URL) async throws -> OCRScanResult? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 100
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        let payload = ChandraOCRRequest(
            imageBase64: candidate.data.base64EncodedString(),
            format: "markdown",
            mode: "accurate",
            task: "ocr"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
        return ChandraOCRParser.parse(data)
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let apiKey, !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    }

    private func multipartBody(imageData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"scan.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"format\"\r\n\r\n")
        body.append("markdown\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n")
        body.append("accurate\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private struct ChandraOCRRequest: Encodable {
    var imageBase64: String
    var format: String
    var mode: String
    var task: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case format
        case mode
        case task
    }
}

private enum ChandraOCRParser {
    static func parse(_ data: Data) -> OCRScanResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return parsePlainText(data)
        }
        let text = extractText(from: json)
        let tables = extractTables(from: json, fallbackText: text)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }
        guard !lines.isEmpty || !tables.isEmpty else { return nil }
        var seen = Set<String>()
        let uniqueLines = lines.filter { seen.insert($0.normalizedForDeduplication).inserted }
        let confidence = extractConfidence(from: json) ?? min(0.94, max(0.7, uniqueLines.map(\.wordLikeRatio).reduce(0, +) / Double(max(1, uniqueLines.count))))
        return OCRScanResult(
            rawText: uniqueLines.joined(separator: "\n"),
            lines: uniqueLines,
            tables: tables,
            confidence: confidence,
            engine: "chandra ocr"
        )
    }

    private static func parsePlainText(_ data: Data) -> OCRScanResult? {
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedOCRLine }
            .filter { !$0.isEmpty && $0.garbageRatio < 0.44 }
        guard !lines.isEmpty else { return nil }
        return OCRScanResult(rawText: lines.joined(separator: "\n"), lines: lines, tables: [], confidence: 0.82, engine: "chandra ocr")
    }

    private static func extractText(from json: Any) -> String {
        if let string = json as? String { return string }
        if let array = json as? [Any] {
            return array.map { extractText(from: $0) }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard let object = json as? [String: Any] else { return "" }
        if let markdown = object["markdown"] as? String { return markdown.markdownToPlainText }
        if let html = object["html"] as? String { return html.htmlToPlainText() }
        if let text = object["text"] as? String { return text }
        if let text = object["content"] as? String { return text }
        if let text = object["output_text"] as? String { return text }
        if let lines = object["lines"] as? [String] { return lines.joined(separator: "\n") }
        if let pages = object["pages"] { return extractText(from: pages) }
        if let results = object["results"] { return extractText(from: results) }
        if let result = object["result"] { return extractText(from: result) }
        if let blocks = object["blocks"] { return extractText(from: blocks) }
        return ""
    }

    private static func extractTables(from json: Any, fallbackText: String) -> [DetectedTable] {
        var tables: [DetectedTable] = []
        if let table = fallbackText.detectedMarkdownTable(title: "chandra table") {
            tables.append(table)
        }
        if let object = json as? [String: Any] {
            if let html = object["html"] as? String, let table = html.detectedTable(title: "chandra table") {
                tables.append(table)
            }
            for value in object.values {
                tables += extractTables(from: value, fallbackText: "")
            }
        } else if let array = json as? [Any] {
            for value in array {
                tables += extractTables(from: value, fallbackText: "")
            }
        }
        var seen = Set<String>()
        return tables.filter { table in
            let signature = ([table.title] + table.headers + table.rows.flatMap { $0 }).joined(separator: "|")
            return seen.insert(signature).inserted
        }
    }

    private static func extractConfidence(from json: Any) -> Double? {
        if let object = json as? [String: Any] {
            for key in ["confidence", "score", "page_confidence", "average_confidence"] {
                if let value = object[key] as? Double { return min(0.98, max(0.18, value)) }
                if let value = object[key] as? Int { return min(0.98, max(0.18, Double(value))) }
            }
            let nested = object.values.compactMap(extractConfidence)
            guard !nested.isEmpty else { return nil }
            return nested.reduce(0, +) / Double(nested.count)
        }
        if let array = json as? [Any] {
            let nested = array.compactMap(extractConfidence)
            guard !nested.isEmpty else { return nil }
            return nested.reduce(0, +) / Double(nested.count)
        }
        return nil
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
        guard let endpoint else { return nil }
        var bestResult: OCRScanResult?
        for candidate in OCRImagePreprocessor.remoteUploadCandidates(from: image) {
            let boundary = "cahier-surya-\(UUID().uuidString)"
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 70
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(imageData: candidate.data, boundary: boundary)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                      var result = SuryaOCRParser.parse(data) else { continue }
                result.engine = "\(result.engine) \(candidate.name)"
                bestResult = OCRResultRanker.best(bestResult, result)
                if result.isStrongRemoteResult { return result }
            } catch {
                continue
            }
        }
        return bestResult
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
                    OCRCandidateRanker.bestCandidate(from: observation.topCandidates(10))
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
            request.recognitionLanguages = OCRLanguageHints.appleVision
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

private enum OCRLanguageHints {
    static let vision = ["en", "fr", "es", "de", "it", "pt", "nl", "pl", "ru", "ar", "hi", "zh", "ja", "ko"]
    static let appleVision = ["en-US", "en-GB", "fr-FR", "es-ES", "de-DE", "it-IT", "pt-BR", "nl-NL", "pl-PL", "ru-RU", "ar-SA", "hi-IN", "zh-Hans", "ja-JP", "ko-KR"]
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
        appendVariant(name: "joined script", image: joinedScriptRecovery(prepared), minimumTextHeight: 0.0035, to: &variants)
        return variants
    }

    static func remoteUploadCandidates(from image: UIImage) -> [OCRUploadCandidate] {
        var candidates: [OCRUploadCandidate] = []
        if let original = image.jpegData(compressionQuality: 0.94) {
            candidates.append(OCRUploadCandidate(name: "original", data: original))
        }
        guard let base = CIImage(image: image)?.oriented(forExifOrientation: image.imageOrientation.exifOrientation) else {
            return candidates
        }
        let prepared = scaledForHandwriting(base)
        let lifted = remoteHandwritingLift(prepared)
        if let liftedData = jpegData(from: lifted, compressionQuality: 0.92),
           liftedData != candidates.first?.data {
            candidates.append(OCRUploadCandidate(name: "handwriting lift", data: liftedData))
        }
        let cursive = remoteCursiveRecovery(prepared)
        if let cursiveData = jpegData(from: cursive, compressionQuality: 0.92),
           !candidates.contains(where: { $0.data == cursiveData }) {
            candidates.append(OCRUploadCandidate(name: "cursive recovery", data: cursiveData))
        }
        return candidates
    }

    private static func appendVariant(name: String, image: CIImage, minimumTextHeight: Float, to variants: inout [Variant]) {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        variants.append(Variant(name: name, image: cgImage, orientation: .up, minimumTextHeight: minimumTextHeight))
    }

    private static func jpegData(from image: CIImage, compressionQuality: CGFloat) -> Data? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality)
    }

    private static func scaledForHandwriting(_ image: CIImage) -> CIImage {
        let longestSide = max(image.extent.width, image.extent.height)
        guard longestSide > 0, longestSide < 2400 else { return image }
        let scale = min(3.0, 2400 / longestSide)
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

    private static func joinedScriptRecovery(_ image: CIImage) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = image
        mono.saturation = 0
        mono.contrast = 2.08
        mono.brightness = 0.035

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mono.outputImage ?? image
        blur.radius = 0.34

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = blur.outputImage?.cropped(to: image.extent) ?? mono.outputImage ?? image
        sharpen.radius = 0.9
        sharpen.intensity = 0.82
        return sharpen.outputImage ?? mono.outputImage ?? image
    }

    private static func remoteHandwritingLift(_ image: CIImage) -> CIImage {
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = image
        shadows.shadowAmount = 0.82
        shadows.highlightAmount = 0.78

        let mono = CIFilter.colorControls()
        mono.inputImage = shadows.outputImage ?? image
        mono.saturation = 0
        mono.contrast = 1.52
        mono.brightness = 0.045

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = mono.outputImage ?? image
        gamma.power = 0.78

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = gamma.outputImage ?? mono.outputImage ?? image
        sharpen.radius = 0.72
        sharpen.intensity = 0.58
        return sharpen.outputImage ?? gamma.outputImage ?? mono.outputImage ?? image
    }

    private static func remoteCursiveRecovery(_ image: CIImage) -> CIImage {
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = image
        shadows.shadowAmount = 0.96
        shadows.highlightAmount = 0.7

        let mono = CIFilter.colorControls()
        mono.inputImage = shadows.outputImage ?? image
        mono.saturation = 0
        mono.contrast = 2.12
        mono.brightness = 0.02

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = mono.outputImage ?? image
        gamma.power = 0.68

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = gamma.outputImage ?? mono.outputImage ?? image
        blur.radius = 0.22

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = blur.outputImage?.cropped(to: image.extent) ?? gamma.outputImage ?? mono.outputImage ?? image
        sharpen.radius = 0.82
        sharpen.intensity = 0.72
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

        for (resultIndex, result) in usable.prefix(4).enumerated() {
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
        let engineNames = usable.prefix(4).map(\.engine).joined(separator: " + ")
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

    var ocrArtifactPenalty: Double {
        let words = split { $0.isWhitespace }.map(String.init)
        guard !words.isEmpty else { return 1 }
        var artifactCount = 0
        var ultraShortCount = 0
        var symbolHeavyCount = 0

        for word in words {
            let useful = word.filter(\.isUsefulOCRCharacter).count
            let letters = word.filter(\.isLetter).count
            let digits = word.filter(\.isNumber).count
            let symbols = max(0, word.count - letters - digits)

            if word.count == 1 { ultraShortCount += 1 }
            if word.count > 0 && useful * 2 < word.count { artifactCount += 1 }
            if word.count >= 3 && symbols > letters + digits { symbolHeavyCount += 1 }
            if word.repeatedGlyphPenalty > 0.25 { artifactCount += 1 }
        }

        let denominator = Double(words.count)
        let artifactRatio = Double(artifactCount) / denominator
        let shortRatio = Double(ultraShortCount) / denominator
        let symbolRatio = Double(symbolHeavyCount) / denominator
        let lineFragmentPenalty = lineFragmentRatio * 0.28
        return min(1, artifactRatio * 0.42 + shortRatio * 0.18 + symbolRatio * 0.26 + lineFragmentPenalty)
    }

    private var lineFragmentRatio: Double {
        let lines = components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return 1 }
        let fragments = lines.filter { line in
            let tokenCount = line.split { !$0.isLetter && !$0.isNumber }.count
            return line.count <= 3 || tokenCount <= 1
        }
        return Double(fragments.count) / Double(lines.count)
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

    var normalizedForDeduplication: String {
        normalizedForOCRComparison
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

    var markdownToPlainText: String {
        self
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[tbl-[^\]]+\]\([^\)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: [.regularExpression, .anchored])
            .replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*\d+[.)]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("| ---") && $0 != "|" }
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

    func detectedMarkdownTable(title: String) -> DetectedTable? {
        let rows = components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("|") }
            .map { row in
                row
                    .trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).markdownToPlainText }
                    .filter { !$0.isEmpty }
            }
            .filter { cells in
                !cells.isEmpty && !cells.allSatisfy { cell in
                    cell.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

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
