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
    func answer(_ question: String, from content: ExtractedContent) -> String
    func answerWithLocalModel(_ question: String, from content: ExtractedContent) async -> String?
}

@MainActor
protocol SpacedRepetitionServing {
    func schedule(_ card: Flashcard, mode: MemorizationMode) -> ReviewState
}

@MainActor
protocol VoiceServing {
    func makePlayback(_ text: String, style: PlaybackStyle, profile: VoiceProfile) async -> VoicePlayback
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
        let profile = ImageStructureAnalyzer.profile(in: image)
        let insight = NoteIntelligenceAnalyzer.insight(
            text: usableText,
            lines: lines,
            keywords: keywords,
            formulas: formulas,
            tables: tables,
            models: models,
            confidence: ocrResult.confidence,
            profile: profile
        )

        return ExtractedContent(
            cleanedText: usableText,
            rawText: recognizedText.isEmpty ? usableText : recognizedText.lowercased(),
            keywords: keywords.isEmpty ? ["scan"] : keywords,
            formulas: formulas,
            sections: sections,
            tables: tables,
            models: models,
            insight: insight,
            confidence: cleaned.isEmpty ? min(ocrResult.confidence, 0.18) : ocrResult.confidence,
            sourceEngine: ocrResult.engine
        )
    }
}

private enum NoteIntelligenceAnalyzer {
    static func insight(
        text: String,
        lines: [String],
        keywords: [String],
        formulas: [String],
        tables: [DetectedTable],
        models: [DetectedModel],
        confidence: Double,
        profile: ImageStructureAnalyzer.Profile
    ) -> SmartPageInsight {
        let cleanedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        let wordCount = max(1, text.split(whereSeparator: \.isWhitespace).count)
        let averageLineLength = cleanedLines.isEmpty ? 0 : Double(cleanedLines.map(\.count).reduce(0, +)) / Double(cleanedLines.count)
        let shortLineRatio = cleanedLines.isEmpty ? 0 : Double(cleanedLines.filter { $0.count < 24 }.count) / Double(cleanedLines.count)
        let structureScore = min(1, Double(keywords.count + formulas.count + tables.count * 2 + models.count * 2) / 14.0)
        let spacing = max(0, min(1, 1 - abs(averageLineLength - 44) / 64))
        let legibility = max(0.05, min(1, confidence * 0.58 + spacing * 0.18 + (1 - profile.inkDensity) * 0.14 + structureScore * 0.1))
        let clarity = max(0.05, min(1, legibility * 0.52 + structureScore * 0.24 + min(1, Double(cleanedLines.count) / 18) * 0.14 + (models.isEmpty ? 0 : 0.1)))
        let risk = max(0.04, min(0.96, 1 - clarity + (formulas.count > 2 ? 0.08 : 0) + (wordCount > 280 ? 0.08 : 0)))
        let pace: WritingPace = averageLineLength > 70 || confidence < 0.46 ? .rushed : averageLineLength < 28 && profile.inkDensity < 0.11 ? .deliberate : .steady
        let pressure: WritingPressure = profile.inkDensity > 0.32 ? .heavy : profile.inkDensity < 0.11 ? .light : .balanced
        let style: NoteStyle
        if !models.isEmpty && (!tables.isEmpty || !formulas.isEmpty) {
            style = .mixed
        } else if !models.isEmpty {
            style = .diagram
        } else if !tables.isEmpty {
            style = .table
        } else if formulas.count >= 2 {
            style = .formula
        } else {
            style = .linear
        }
        let topIdea = keywords.first ?? cleanedLines.first ?? "this page"
        let onlyWhatMatters = onlyWhatMatters(from: cleanedLines, keywords: keywords, formulas: formulas, models: models)
        let nextBestStep = nextStep(style: style, risk: risk, keywords: keywords, formulas: formulas, models: models)
        let coaching = handwritingCoach(legibility: legibility, spacing: spacing, pace: pace, pressure: pressure)
        let lanes = [
            StudyLane(title: "read", systemName: "book.pages.fill", value: "\(max(1, Int(ceil(Double(wordCount) / 180.0)))) min"),
            StudyLane(title: "risk", systemName: "exclamationmark.triangle.fill", value: percent(risk)),
            StudyLane(title: "clarity", systemName: "checkmark.seal.fill", value: percent(clarity)),
            StudyLane(title: "style", systemName: style.symbol, value: style.rawValue)
        ]
        let prompts = Array([
            "explain \(topIdea) without looking.",
            "name the detail most likely to be tested.",
            formulas.first.map { "solve a new example using \($0)." },
            models.first.map { "redraw the \( $0.title ) from memory." },
            tables.first.map { "cover the \($0.title) and recreate the columns." }
        ].compactMap(\.self).prefix(5))
        let questions = Array([
            "what is the main claim of this page?",
            "which keyword connects two sections?",
            formulas.first.map { "what does \($0) prove or compute?" },
            models.first.map { "what changes if one part of \($0.title) is removed?" },
            risk > 0.5 ? "which line should be rewritten first?" : nil
        ].compactMap(\.self).prefix(5))
        let hooks = memoryHooks(keywords: keywords, style: style, models: models)
        let angles = examAngles(keywords: keywords, formulas: formulas, tables: tables, models: models)
        let alerts = confusionAlerts(confidence: confidence, risk: risk, legibility: legibility, formulas: formulas, models: models)
        let cleanup = cleanupSuggestions(spacing: spacing, structure: structureScore, pace: pace, pressure: pressure, tables: tables, models: models)
        let signature = handwritingSignature(
            legibility: legibility,
            spacing: spacing,
            structure: structureScore,
            confidence: confidence,
            profile: profile,
            averageLineLength: averageLineLength,
            shortLineRatio: shortLineRatio,
            style: style
        )
        let features = detectedFeatures(
            keywords: keywords,
            formulas: formulas,
            tables: tables,
            models: models,
            shortLineRatio: shortLineRatio,
            profile: profile
        )
        return SmartPageInsight(
            onlyWhatMatters: onlyWhatMatters,
            nextBestStep: nextBestStep,
            clarityScore: clarity,
            retentionRisk: risk,
            estimatedReadMinutes: max(1, Int(ceil(Double(wordCount) / 180.0))),
            handwriting: HandwritingAnalysis(
                legibility: legibility,
                inkDensity: profile.inkDensity,
                spacing: spacing,
                structure: structureScore,
                pace: pace,
                pressure: pressure,
                noteStyle: style,
                coaching: coaching,
                signature: signature
            ),
            studyLanes: lanes,
            recallPrompts: prompts,
            quickQuestions: questions,
            memoryHooks: hooks,
            examAngles: angles,
            confusionAlerts: alerts,
            cleanupSuggestions: cleanup,
            detectedFeatures: features
        )
    }

    private static func handwritingSignature(
        legibility: Double,
        spacing: Double,
        structure: Double,
        confidence: Double,
        profile: ImageStructureAnalyzer.Profile,
        averageLineLength: Double,
        shortLineRatio: Double,
        style: NoteStyle
    ) -> HandwritingSignature {
        let rhythm = max(0.04, min(1, 1 - abs(averageLineLength - 46) / 72))
        let consistency = max(0.04, min(1, spacing * 0.34 + legibility * 0.34 + profile.balance * 0.18 + (1 - shortLineRatio) * 0.14))
        let correctionNeed = max(0.03, min(0.97, (1 - legibility) * 0.46 + (1 - spacing) * 0.22 + profile.edgeDensity * 0.18 + (confidence < 0.52 ? 0.14 : 0)))
        let studyReadiness = max(0.04, min(1, legibility * 0.38 + consistency * 0.28 + structure * 0.22 + (1 - correctionNeed) * 0.12))
        let identity: String
        if style == .diagram || style == .mixed {
            identity = "visual mapper"
        } else if rhythm > 0.76 && consistency > 0.66 {
            identity = "clean rhythm"
        } else if profile.inkDensity > 0.3 {
            identity = "heavy ink"
        } else if shortLineRatio > 0.58 {
            identity = "quick fragments"
        } else {
            identity = "steady notes"
        }
        let nextStroke: String
        if legibility < 0.48 {
            nextStroke = "rewrite keywords wider"
        } else if spacing < 0.45 {
            nextStroke = "add space between ideas"
        } else if structure < 0.38 {
            nextStroke = "box headings before review"
        } else if correctionNeed > 0.48 {
            nextStroke = "clean one weak line"
        } else {
            nextStroke = "study without rewriting"
        }
        let predictedIssue: String
        if confidence < 0.44 {
            predictedIssue = "ocr may miss names or formulas"
        } else if profile.edgeDensity > 0.34 {
            predictedIssue = "dense sketch may hide labels"
        } else if spacing < 0.42 {
            predictedIssue = "ideas may blend during review"
        } else if style == .formula {
            predictedIssue = "symbols need a worked example"
        } else {
            predictedIssue = "low risk"
        }
        var strengths: [String] = []
        if legibility > 0.68 { strengths.append("readable") }
        if spacing > 0.62 { strengths.append("spaced") }
        if structure > 0.5 { strengths.append("structured") }
        if profile.balance > 0.58 { strengths.append("balanced") }
        if style == .diagram || style == .mixed { strengths.append("visual") }
        if strengths.isEmpty { strengths = ["captured", "recoverable"] }
        return HandwritingSignature(
            rhythm: rhythm,
            consistency: consistency,
            correctionNeed: correctionNeed,
            studyReadiness: studyReadiness,
            identity: identity,
            nextStroke: nextStroke,
            predictedIssue: predictedIssue,
            strengths: Array(strengths.prefix(4))
        )
    }

    private static func onlyWhatMatters(from lines: [String], keywords: [String], formulas: [String], models: [DetectedModel]) -> String {
        let strongestLine = lines.first { line in
            keywords.contains { line.contains($0) }
        } ?? lines.first ?? "review the core idea on this page."
        var parts = [strongestLine]
        if let formula = formulas.first {
            parts.append("use \(formula)")
        }
        if let model = models.first {
            parts.append("connect it to \(model.title)")
        }
        return parts.joined(separator: "\n")
    }

    private static func nextStep(style: NoteStyle, risk: Double, keywords: [String], formulas: [String], models: [DetectedModel]) -> String {
        if risk > 0.62 {
            return "rewrite the messiest line, then test \(keywords.first ?? "one idea")."
        }
        switch style {
        case .diagram:
            return "tap the model and explain each node."
        case .table:
            return "hide one column and recall it."
        case .formula:
            return "make one fresh problem from \(formulas.first ?? "the formula")."
        case .mixed:
            return "study text first, then rebuild the diagram."
        case .linear:
            return "turn the first section into two recall prompts."
        }
    }

    private static func handwritingCoach(legibility: Double, spacing: Double, pace: WritingPace, pressure: WritingPressure) -> String {
        if legibility < 0.42 {
            return "slow down and leave more air between lines before the next scan."
        }
        if spacing < 0.46 {
            return "spacing is tight. add short gaps around headings and formulas."
        }
        if pace == .rushed {
            return "the writing looks fast. rewrite key terms before reviewing."
        }
        if pressure == .heavy {
            return "ink pressure is strong. lighten strokes so ocr keeps letters cleaner."
        }
        return "handwriting is study ready. keep the same rhythm for future pages."
    }

    private static func detectedFeatures(
        keywords: [String],
        formulas: [String],
        tables: [DetectedTable],
        models: [DetectedModel],
        shortLineRatio: Double,
        profile: ImageStructureAnalyzer.Profile
    ) -> [String] {
        var features: [String] = []
        if !keywords.isEmpty { features.append("keywords") }
        if !formulas.isEmpty { features.append("formulas") }
        if !tables.isEmpty { features.append("tables") }
        if !models.isEmpty { features.append("models") }
        if shortLineRatio > 0.34 { features.append("outline") }
        if profile.edgeDensity > 0.22 { features.append("sketch") }
        if profile.balance > 0.72 { features.append("balanced page") }
        return features.isEmpty ? ["notes"] : features
    }

    private static func memoryHooks(keywords: [String], style: NoteStyle, models: [DetectedModel]) -> [String] {
        var hooks = keywords.prefix(4).map { "link \($0) to one image or example." }
        if let model = models.first {
            hooks.append("picture \(model.title) rotating once.")
        }
        hooks.append("say the \(style.rawValue) pattern out loud.")
        return Array(hooks.prefix(5))
    }

    private static func examAngles(keywords: [String], formulas: [String], tables: [DetectedTable], models: [DetectedModel]) -> [String] {
        var angles: [String] = []
        if let keyword = keywords.first {
            angles.append("define \(keyword) in one sentence.")
        }
        if let formula = formulas.first {
            angles.append("use \(formula) with new numbers.")
        }
        if let table = tables.first {
            angles.append("compare two columns in \(table.title).")
        }
        if let model = models.first {
            angles.append("label each node in \(model.title).")
        }
        angles.append("explain the page from memory in 30 seconds.")
        return Array(angles.prefix(5))
    }

    private static func confusionAlerts(confidence: Double, risk: Double, legibility: Double, formulas: [String], models: [DetectedModel]) -> [String] {
        var alerts: [String] = []
        if confidence < 0.48 { alerts.append("ocr confidence is low. verify the text before studying.") }
        if risk > 0.58 { alerts.append("retention risk is high. do recall before rereading.") }
        if legibility < 0.45 { alerts.append("handwriting may hide key terms.") }
        if formulas.count > 3 { alerts.append("formula-heavy page. practice, do not just read.") }
        if models.count > 1 { alerts.append("multiple diagrams. study one model at a time.") }
        return alerts
    }

    private static func cleanupSuggestions(spacing: Double, structure: Double, pace: WritingPace, pressure: WritingPressure, tables: [DetectedTable], models: [DetectedModel]) -> [String] {
        var suggestions: [String] = []
        if spacing < 0.5 { suggestions.append("add space around headings.") }
        if structure < 0.35 { suggestions.append("mark key ideas with bullets.") }
        if pace == .rushed { suggestions.append("rewrite the first messy line.") }
        if pressure == .heavy { suggestions.append("use lighter strokes next scan.") }
        if !tables.isEmpty { suggestions.append("check table headers.") }
        if !models.isEmpty { suggestions.append("tap the model before flashcards.") }
        return suggestions
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private extension NoteStyle {
    var symbol: String {
        switch self {
        case .linear: "text.alignleft"
        case .diagram: "cube.transparent"
        case .table: "tablecells"
        case .formula: "function"
        case .mixed: "sparkles.rectangle.stack"
        }
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
        if candidateRows.count < 2 {
            return keyValueTable(from: lines).map { [$0] } ?? []
        }

        let headers = candidateRows.first ?? []
        let rows = Array(candidateRows.dropFirst()).filter { !$0.allSatisfy(\.isEmpty) }
        guard !rows.isEmpty else { return [] }
        return [DetectedTable(title: "detected table", headers: headers, rows: rows)]
    }

    static func models(from lines: [String], keywords: [String], visualSignal: Double) -> [DetectedModel] {
        let joined = lines.joined(separator: " ").lowercased()
        let modelTriggers = [
            "diagram", "model", "graph", "figure", "chart", "axis", "cycle", "flow", "structure", "system", "map", "sketch",
            "arrow", "pathway", "network", "circuit", "cell", "molecule", "atom", "timeline", "shape", "label"
        ]
        let textTriggered = modelTriggers.contains(where: joined.contains)
        let visuallyTriggered = visualSignal > 0.13 && joined.count < 640
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
                nodes: terms.isEmpty ? fallbackNodes : terms,
                reconstruction: ModelReconstructionFactory.make(
                    source: "surya layout plus local depth",
                    confidence: max(0.46, min(0.91, visualSignal + (textTriggered ? 0.34 : 0.22))),
                    shape: shape(from: joined, visualSignal: visualSignal),
                    nodes: terms.isEmpty ? fallbackNodes : terms,
                    hint: "tap anchors to rebuild the scan as a memory object."
                )
            )
        ]
    }

    private static func shape(from text: String, visualSignal: Double) -> ModelShape {
        if text.contains("cycle") || text.contains("flow") || text.contains("loop") || text.contains("pathway") { return .cycle }
        if text.contains("table") || text.contains("chart") { return .table }
        if text.contains("layer") || text.contains("stack") || text.contains("timeline") { return .stack }
        return visualSignal > 0.22 ? .mesh : .orbit
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

    private static func keyValueTable(from lines: [String]) -> DetectedTable? {
        let pairs = lines.compactMap { line -> [String]? in
            let separators = [":", " - ", " -> ", " = "]
            guard let separator = separators.first(where: { line.contains($0) }) else { return nil }
            let pieces = line
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard pieces.count >= 2, pieces[0].count <= 32 else { return nil }
            return [pieces[0], pieces.dropFirst().joined(separator: " ")]
        }
        guard pairs.count >= 3 else { return nil }
        return DetectedTable(
            title: "structured notes",
            headers: ["term", "detail"],
            rows: Array(pairs.prefix(8))
        )
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
    private let localLLM = GemmaStudyLLMService()

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
        var cards: [Flashcard] = []
        for section in content.sections.prefix(4) {
            let answer = section.body
                .split(separator: "\n")
                .prefix(2)
                .joined(separator: " ")
            cards.append(Flashcard(front: "what matters in \(section.title)?", back: answer.isEmpty ? section.body : answer))
        }
        for keyword in content.keywords.prefix(4) {
            cards.append(Flashcard(front: "explain \(keyword)", back: explain(keyword)))
        }
        for formula in content.formulas.prefix(3) {
            cards.append(Flashcard(front: "when do you use \(formula)?", back: "use it when the page asks you to connect the quantities around \(formula)."))
        }
        for table in content.tables.prefix(2) {
            cards.append(Flashcard(front: "what does \(table.title) compare?", back: table.headers.joined(separator: ", ")))
        }
        for model in content.models.prefix(2) {
            let nodes = (model.nodes ?? model.terms).joined(separator: ", ")
            cards.append(Flashcard(front: "rebuild \(model.title)", back: nodes.isEmpty ? model.summary : nodes))
        }
        for prompt in content.insight.recallPrompts.prefix(3) {
            cards.append(Flashcard(front: prompt, back: content.insight.onlyWhatMatters.isEmpty ? content.cleanedText : content.insight.onlyWhatMatters))
        }

        var seen = Set<String>()
        let unique = cards.filter { seen.insert($0.front).inserted }
        if unique.isEmpty {
            return [Flashcard(front: "what is this page about?", back: content.cleanedText)]
        }
        return Array(unique.prefix(12))
    }

    func explain(_ term: String) -> String {
        "\(term) is the smallest piece to understand first. connect it to the example on the page, then test it with one recall question."
    }

    func answer(_ question: String, from content: ExtractedContent) -> String {
        let cleanedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedQuestion.isEmpty else {
            return content.insight.nextBestStep.isEmpty ? "ask about a term, formula, table, or model from this page." : content.insight.nextBestStep
        }

        let questionWords = Set(cleanedQuestion
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 })
        let section = bestSection(in: content, matching: questionWords)
        var answerParts: [String] = []

        if let section {
            answerParts.append(section.body)
        } else if !content.insight.onlyWhatMatters.isEmpty {
            answerParts.append(content.insight.onlyWhatMatters)
        } else {
            answerParts.append(content.cleanedText.components(separatedBy: .newlines).prefix(3).joined(separator: "\n"))
        }

        if cleanedQuestion.contains("formula"), let formula = content.formulas.first {
            answerParts.append("use \(formula) and make one fresh example.")
        }
        if cleanedQuestion.contains("table"), let table = content.tables.first {
            answerParts.append("the table compares \(table.headers.prefix(4).joined(separator: ", ")).")
        }
        if cleanedQuestion.contains("model") || cleanedQuestion.contains("diagram"),
           let model = content.models.first {
            let nodes = (model.nodes ?? model.terms).prefix(5).joined(separator: ", ")
            answerParts.append(nodes.isEmpty ? model.summary : "rebuild \(model.title) through \(nodes).")
        }
        if let keyword = content.keywords.first(where: { cleanedQuestion.contains($0) }) {
            answerParts.append("test yourself by explaining \(keyword) without looking.")
        }

        let unique = answerParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, part in
                if !result.contains(part) {
                    result.append(part)
                }
            }
        return unique.prefix(4).joined(separator: "\n\n")
    }

    func answerWithLocalModel(_ question: String, from content: ExtractedContent) async -> String? {
        await localLLM.answer(question: question, content: content)
    }

    private func bestSection(in content: ExtractedContent, matching words: Set<String>) -> StudySection? {
        guard !words.isEmpty else { return content.sections.first }
        return content.sections.max { first, second in
            score(first, words: words, keywords: content.keywords) < score(second, words: words, keywords: content.keywords)
        }
    }

    private func score(_ section: StudySection, words: Set<String>, keywords: [String]) -> Int {
        let haystack = "\(section.title) \(section.body)".lowercased()
        let wordScore = words.reduce(0) { total, word in total + (haystack.contains(word) ? 2 : 0) }
        let keywordScore = keywords.reduce(0) { total, keyword in total + (haystack.contains(keyword) ? 1 : 0) }
        return wordScore + keywordScore
    }
}

struct GemmaStudyLLMService {
    static var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GemmaStudyEndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["GEMMA_STUDY_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["LOCAL_GEMMA_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return URL(string: "http://127.0.0.1:8765/gemma/generate")
    }

    static var configuredModel: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GemmaStudyModel") as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["GEMMA_STUDY_MODEL"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["LOCAL_GEMMA_MODEL"], !value.isEmpty {
            return value
        }
        return "gemma-4-e4b-it"
    }

    let endpoint: URL?
    let model: String

    init(endpoint: URL? = Self.configuredEndpoint, model: String = Self.configuredModel) {
        self.endpoint = endpoint
        self.model = model
    }

    func answer(question: String, content: ExtractedContent) async -> String? {
        guard let endpoint else { return nil }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 28
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = GemmaStudyLLMRequest(
            model: model,
            prompt: prompt(question: trimmed, content: content),
            maxTokens: 420,
            temperature: 0.2
        )
        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            return GemmaStudyLLMParser.parse(data)
        } catch {
            return nil
        }
    }

    private func prompt(question: String, content: ExtractedContent) -> String {
        """
        you are marginalia's local gemma study tutor. answer only from the student's notes. keep it short, clear, and useful. if the answer is not in the notes, say what part of the notes is closest.

        question:
        \(question)

        notes:
        \(content.cleanedText.prefix(3500))
        """
    }
}

private struct GemmaStudyLLMRequest: Encodable {
    var model: String
    var prompt: String
    var maxTokens: Int
    var temperature: Double
}

private enum GemmaStudyLLMParser {
    static func parse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let answer = json["answer"] as? String { return answer.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let response = json["response"] as? String { return response.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let text = json["text"] as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let output = json["output"] as? String { return output.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first {
            if let text = first["text"] as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
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
        let styleName = style.rawValue.replacingOccurrences(of: "-", with: " ")
        let summary: String
        if request.referenceAudioURLs.isEmpty {
            summary = "on device \(styleName) reader is speaking \(words) words."
        } else {
            summary = "on device \(styleName) reader is using \(request.referenceAudioURLs.count) saved voice samples for timing."
        }
        return VoicePlayback(
            style: style,
            summary: summary,
            engine: backend,
            referenceSampleCount: request.referenceAudioURLs.count
        )
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
