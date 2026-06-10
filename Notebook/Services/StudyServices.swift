import Foundation
import LocalAuthentication
import UIKit

@MainActor
protocol LocalAuthServing {
    func signIn(provider: AuthProvider) async -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(username: String, email: String, password: String, confirmPassword: String) async throws -> AuthSession
    func sendReset(email: String) async throws -> String
    func verifyWithFaceID() async -> Bool
}

@MainActor
protocol ScanProcessingServing {
    func process(image: UIImage) async -> ExtractedContent
}

@MainActor
protocol NoteUnderstandingServing {
    func classify(_ content: ExtractedContent) async -> String
    func makeFlashcards(from content: ExtractedContent) -> [Flashcard]
    func explain(_ term: String) -> String
}

@MainActor
protocol SpacedRepetitionServing {
    func schedule(_ card: Flashcard, mode: MemorizationMode) -> ReviewState
}

@MainActor
protocol VoiceServing {
    func makePlayback(_ text: String, style: PlaybackStyle, profile: VoiceProfile) async -> VoicePlayback
    func transcribeQuestion() async -> String
}

struct MossTTSRequest: Hashable {
    var text: String
    var referenceAudioURLs: [URL]
    var mode: String
    var language: String?
    var temperature: Double
    var topP: Double
    var topK: Int
    var repetitionPenalty: Double
    var modelID: String
    var spaceURL: URL
}

struct LocalAuthService: LocalAuthServing {
    func signIn(provider: AuthProvider) async -> AuthSession {
        AuthSession(provider: provider, email: provider.defaultEmail, username: "student", createdAt: .now)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
        let username = try CredentialVault.verify(email: email, password: password)
        return AuthSession(provider: .email, email: email.lowercased(), username: username, createdAt: .now)
    }

    func signUp(username: String, email: String, password: String, confirmPassword: String) async throws -> AuthSession {
        guard username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { throw AuthError.missingUsername }
        guard email.lowercased().hasSuffix("@gmail.com") else { throw AuthError.invalidEmail }
        guard password == confirmPassword else { throw AuthError.passwordMismatch }
        guard passwordStrength(password) != .weak else { throw AuthError.weakPassword }
        let faceIDLinked = await verifyWithFaceID()
        try CredentialVault.save(email: email, password: password, username: username, faceIDLinked: faceIDLinked)
        return AuthSession(provider: .email, email: email.lowercased(), username: username.lowercased(), createdAt: .now)
    }

    func sendReset(email: String) async throws -> String {
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        guard CredentialVault.accountExists(email: email) else { throw AuthError.accountNotFound }
        let needsFaceID = (try? CredentialVault.requiresFaceID(email: email)) == true
        if !needsFaceID {
            return "reset link sent to \(email.lowercased())."
        }
        if await verifyWithFaceID() {
            return "face id verified. reset link sent to \(email.lowercased())."
        }
        return "face id was not verified."
    }

    func verifyWithFaceID() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "verify before resetting your notebook password")) == true
    }
}

func passwordStrength(_ password: String) -> PasswordStrength {
    var score = 0
    if password.count >= 8 { score += 1 }
    if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
    if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
    if password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()-_=+[]{};:,.?/")) != nil { score += 1 }
    if score <= 1 { return .weak }
    if score <= 3 { return .medium }
    return .good
}

struct LocalScanProcessingService: ScanProcessingServing {
    private let ocr: OCRServing = HybridSuryaOCRService()
    private let objectReconstructor: ObjectReconstructionServing = NotebookObjectReconstructionPipeline()

    func process(image: UIImage) async -> ExtractedContent {
        let ocrResult = await ocr.recognize(in: image)
        let recognizedText = ocrResult.rawText
        let lines = ocrResult.lines
        let cleaned = NoteLayoutAnalyzer.clean(lines: lines)
        let usableText = cleaned.isEmpty ? "no readable handwriting or printed text was detected in this capture." : cleaned
        let words = usableText
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "=" })
            .map(String.init)
        var seen = Set<String>()
        let filteredKeywords = words
            .filter { $0.count > 3 }
            .filter { seen.insert($0).inserted }
        let keywords = Array(filteredKeywords.prefix(8))
        let formulas = usableText
            .components(separatedBy: .newlines)
            .filter { $0.contains("=") || $0.contains("lim") || $0.contains("->") }
        let tables = ocrResult.tables.isEmpty ? NoteLayoutAnalyzer.tables(from: lines) : ocrResult.tables
        let visualSignal = ImageStructureAnalyzer.visualModelSignal(in: image)
        var models = NoteLayoutAnalyzer.models(from: lines, keywords: keywords, visualSignal: visualSignal)
        models.append(contentsOf: await objectReconstructor.reconstruct(from: image, lines: lines, keywords: keywords, visualSignal: visualSignal))
        let sections = NoteLayoutAnalyzer.sections(from: lines, fallback: usableText)

        return ExtractedContent(
            cleanedText: usableText,
            rawText: recognizedText.isEmpty ? usableText : recognizedText.lowercased(),
            keywords: keywords.isEmpty ? ["scan"] : keywords,
            formulas: formulas,
            sections: sections,
            tables: tables,
            models: models,
            confidence: max(ocrResult.confidence, cleaned.isEmpty ? 0.18 : 0.82)
        )
    }
}

private enum NoteLayoutAnalyzer {
    static func clean(lines: [String]) -> String {
        lines
            .map { line in
                line
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func sections(from lines: [String], fallback: String) -> [StudySection] {
        let cleanedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        guard !cleanedLines.isEmpty else {
            return [StudySection(title: "captured notes", body: fallback)]
        }

        var sections: [StudySection] = []
        var activeTitle = "captured notes"
        var activeBody: [String] = []

        func flush() {
            let body = activeBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(StudySection(title: activeTitle, body: body))
            }
            activeBody.removeAll()
        }

        for line in cleanedLines {
            let looksLikeHeading = line.count <= 32 && (line.hasSuffix(":") || line.uppercased() == line || line.split(separator: " ").count <= 3)
            if looksLikeHeading && !activeBody.isEmpty {
                flush()
                activeTitle = line.replacingOccurrences(of: ":", with: "")
            } else if looksLikeHeading && sections.isEmpty && activeBody.isEmpty {
                activeTitle = line.replacingOccurrences(of: ":", with: "")
            } else {
                activeBody.append(line)
            }
        }
        flush()

        return sections.isEmpty ? [StudySection(title: "captured notes", body: fallback)] : sections
    }

    static func tables(from lines: [String]) -> [DetectedTable] {
        let candidateRows = lines
            .map { splitColumns($0) }
            .filter { $0.count >= 2 }
        guard candidateRows.count >= 2 else { return [] }

        let headers = candidateRows.first ?? []
        let rows = Array(candidateRows.dropFirst()).filter { !$0.allSatisfy(\.isEmpty) }
        guard !rows.isEmpty else { return [] }
        return [DetectedTable(title: "detected table", headers: headers, rows: rows)]
    }

    static func models(from lines: [String], keywords: [String], visualSignal: Double) -> [DetectedModel] {
        let joined = lines.joined(separator: " ").lowercased()
        let modelTriggers = ["diagram", "model", "graph", "figure", "chart", "axis", "cycle", "flow", "structure", "system", "map", "sketch"]
        let textTriggered = modelTriggers.contains(where: joined.contains)
        let visuallyTriggered = visualSignal > 0.18 && joined.count < 520
        guard textTriggered || visuallyTriggered else { return [] }

        let title = modelTriggers.first(where: joined.contains) ?? "visual model"
        let fallbackNodes = visuallyTriggered ? ["shape", "label", "connection", "pattern"] : ["idea", "link", "result"]
        let terms = Array(keywords.prefix(5))
        return [
            DetectedModel(
                title: textTriggered ? "\(title) found" : "sketch found",
                summary: visualSignal > 0
                    ? "visual structure was detected in the scan and converted into an interactive study map."
                    : "the scan contains visual structure that should stay connected to the surrounding notes.",
                terms: terms,
                nodes: terms.isEmpty ? fallbackNodes : terms
            )
        ]
    }

    private static func splitColumns(_ line: String) -> [String] {
        if line.contains("|") {
            return line
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }

        let pieces = line
            .components(separatedBy: RegexSeparator.multipleSpaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if pieces.count >= 2 { return pieces }

        let tabPieces = line
            .components(separatedBy: "\t")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return tabPieces
    }
}

private enum RegexSeparator {
    static let multipleSpaces = try! NSRegularExpression(pattern: #" {2,}"#)
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var components: [String] = []
        var last = startIndex
        for match in regex.matches(in: self, range: range) {
            guard let matchRange = Range(match.range, in: self) else { continue }
            components.append(String(self[last..<matchRange.lowerBound]))
            last = matchRange.upperBound
        }
        components.append(String(self[last...]))
        return components
    }

}

struct LocalNoteUnderstandingService: NoteUnderstandingServing {
    func classify(_ content: ExtractedContent) async -> String {
        let text = (content.cleanedText + " " + content.keywords.joined(separator: " ")).lowercased()
        if ["equation", "function", "limit", "derivative", "integral", "algebra", "geometry", "formula"].contains(where: text.contains) {
            return "math"
        }
        if ["cell", "atom", "force", "energy", "biology", "chemistry", "physics", "experiment"].contains(where: text.contains) {
            return "science"
        }
        if ["war", "empire", "revolution", "president", "government", "treaty", "century"].contains(where: text.contains) {
            return "history"
        }
        if ["theme", "essay", "poem", "novel", "author", "character", "paragraph"].contains(where: text.contains) {
            return "english"
        }
        return content.keywords.first ?? "notes"
    }

    func makeFlashcards(from content: ExtractedContent) -> [Flashcard] {
        [
            Flashcard(front: "what does a limit measure?", back: "the value a function approaches near a point."),
            Flashcard(front: "when should you factor first?", back: "when direct substitution creates an undefined expression."),
            Flashcard(front: "what confirms a two sided limit?", back: "both one sided limits approach the same value.")
        ]
    }

    func explain(_ term: String) -> String {
        "\(term) is the smallest piece to understand first. connect it to the example on the page, then test it with one recall question."
    }
}

struct LocalSpacedRepetitionService: SpacedRepetitionServing {
    func schedule(_ card: Flashcard, mode: MemorizationMode) -> ReviewState {
        switch mode {
        case .shortTerm:
            ReviewState(dueLabel: "review in 35 min", stability: 0.34, difficulty: 0.52)
        case .longTerm:
            ReviewState(dueLabel: "review in 2 days", stability: 0.71, difficulty: 0.44)
        }
    }
}

struct MossTTSVoiceService: VoiceServing {
    func makePlayback(_ text: String, style: PlaybackStyle, profile: VoiceProfile) async -> VoicePlayback {
        let backend: VoiceReplicationBackend = profile.isPersonalized ? .mossTTSV15 : .kokoro
        let request = MossTTSRequest(
            text: text,
            referenceAudioURLs: profile.samples.compactMap(\.audioURL),
            mode: profile.isPersonalized ? "Clone" : "Direct Generation",
            language: "English",
            temperature: 0.7,
            topP: 0.95,
            topK: 50,
            repetitionPenalty: 1.1,
            modelID: backend.modelID,
            spaceURL: backend.sourceURL
        )
        if let remotePlayback = await requestRemotePlayback(request: request, style: style, backend: backend) {
            return remotePlayback
        }

        let words = request.text.split(separator: " ").count
        let voiceMode = request.referenceAudioURLs.isEmpty ? "direct generation" : "clone mode"
        return VoicePlayback(
            style: style,
            summary: "\(backend.rawValue) \(voiceMode) prepared \(words) words with \(request.referenceAudioURLs.count) reference samples.",
            engine: backend,
            referenceSampleCount: request.referenceAudioURLs.count
        )
    }

    func transcribeQuestion() async -> String {
        "can you explain the limit step more simply?"
    }

    private func requestRemotePlayback(request: MossTTSRequest, style: PlaybackStyle, backend: VoiceReplicationBackend) async -> VoicePlayback? {
        guard let endpoint = configuredEndpoint else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = MossTTSPayload(
            text: request.text,
            mode: request.mode,
            style: style.rawValue,
            language: request.language ?? "English",
            temperature: request.temperature,
            topP: request.topP,
            topK: request.topK,
            repetitionPenalty: request.repetitionPenalty,
            modelID: request.modelID,
            referenceAudioURLs: request.referenceAudioURLs.map(\.absoluteString)
        )
        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        urlRequest.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let envelope = try? JSONDecoder().decode(MossTTSResponse.self, from: data) else { return nil }

        return VoicePlayback(
            style: style,
            summary: envelope.summary ?? "\(backend.rawValue) generated personalized reading audio.",
            engine: backend,
            referenceSampleCount: request.referenceAudioURLs.count,
            audioURL: envelope.audioURL
        )
    }

    private var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MossTTSEndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["MOSS_TTS_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }
}

private struct MossTTSPayload: Encodable {
    var text: String
    var mode: String
    var style: String
    var language: String
    var temperature: Double
    var topP: Double
    var topK: Int
    var repetitionPenalty: Double
    var modelID: String
    var referenceAudioURLs: [String]

    enum CodingKeys: String, CodingKey {
        case text
        case mode
        case style
        case language
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case repetitionPenalty = "repetition_penalty"
        case modelID = "model_id"
        case referenceAudioURLs = "reference_audio_urls"
    }
}

private struct MossTTSResponse: Decodable {
    var summary: String?
    var audioURL: URL?

    enum CodingKeys: String, CodingKey {
        case summary
        case audioURL = "audio_url"
    }
}
