import Foundation
import LocalAuthentication
import UIKit
@preconcurrency import Vision

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
    func process(image: UIImage) async -> ExtractedContent {
        let recognizedText = await OCRTextScanner.recognizeText(in: image)
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        let tables = NoteLayoutAnalyzer.tables(from: lines)
        let visualSignal = ImageStructureAnalyzer.visualModelSignal(in: image)
        let models = NoteLayoutAnalyzer.models(from: lines, keywords: keywords, visualSignal: visualSignal)
        let sections = NoteLayoutAnalyzer.sections(from: lines, fallback: usableText)

        return ExtractedContent(
            cleanedText: usableText,
            rawText: recognizedText.isEmpty ? usableText : recognizedText.lowercased(),
            keywords: keywords.isEmpty ? ["scan"] : keywords,
            formulas: formulas,
            sections: sections,
            tables: tables,
            models: models,
            confidence: cleaned.isEmpty ? 0.18 : 0.82
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

private enum ImageStructureAnalyzer {
    static func visualModelSignal(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 56
        let height = 72
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkCount = 0
        var edgeCount = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let value = Int(pixels[index])
                if value < 154 { darkCount += 1 }
                let right = Int(pixels[index + 1])
                let down = Int(pixels[index + width])
                if abs(value - right) > 44 || abs(value - down) > 44 {
                    edgeCount += 1
                }
            }
        }

        let sampleCount = Double((width - 2) * (height - 2))
        let inkDensity = Double(darkCount) / sampleCount
        let edgeDensity = Double(edgeCount) / sampleCount
        return min(1, inkDensity * 0.55 + edgeDensity * 0.75)
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

private enum OCRTextScanner {
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
            Flashcard(front: "what confirms a two-sided limit?", back: "both one-sided limits approach the same value.")
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
}
