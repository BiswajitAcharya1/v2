import Foundation
import LocalAuthentication

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
    func processDemoCapture() async -> ExtractedContent
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

struct LocalAuthService: LocalAuthServing {
    func signIn(provider: AuthProvider) async -> AuthSession {
        AuthSession(provider: provider, email: provider.defaultEmail, username: "student", createdAt: .now)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
        return AuthSession(provider: .email, email: email.lowercased(), username: email.split(separator: "@").first.map(String.init) ?? "student", createdAt: .now)
    }

    func signUp(username: String, email: String, password: String, confirmPassword: String) async throws -> AuthSession {
        guard username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { throw AuthError.missingUsername }
        guard email.lowercased().hasSuffix("@gmail.com") else { throw AuthError.invalidEmail }
        guard password == confirmPassword else { throw AuthError.passwordMismatch }
        guard passwordStrength(password) != .weak else { throw AuthError.weakPassword }
        return AuthSession(provider: .email, email: email.lowercased(), username: username.lowercased(), createdAt: .now)
    }

    func sendReset(email: String) async throws -> String {
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        if await verifyWithFaceID() {
            return "identity verified. reset link sent to \(email.lowercased())."
        }
        return "reset link sent to \(email.lowercased())."
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
    func processDemoCapture() async -> ExtractedContent {
        ExtractedContent(
            cleanedText: "limits describe what a graph approaches. factor first, cancel matching terms, then substitute. if both sides approach the same value, the limit exists.",
            rawText: "limit notes: graph approaches. factor/cancel/sub. both sides same = exists.",
            keywords: ["limits", "factor", "substitute", "approach"],
            formulas: ["lim x -> a f(x)", "(x^2 - 4) / (x - 2)"],
            sections: [
                StudySection(title: "method", body: "simplify the expression before substituting the target value."),
                StudySection(title: "check", body: "compare the left and right side behavior before trusting an answer.")
            ],
            confidence: 0.96
        )
    }
}

struct LocalNoteUnderstandingService: NoteUnderstandingServing {
    func classify(_ content: ExtractedContent) async -> String {
        content.keywords.contains("limits") ? "math" : "science"
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

struct LocalVoiceService: VoiceServing {
    func makePlayback(_ text: String, style: PlaybackStyle, profile: VoiceProfile) async -> VoicePlayback {
        let engine = profile.isPersonalized ? "personal voice" : "kokoro"
        return VoicePlayback(style: style, summary: "\(engine) prepared \(text.split(separator: " ").count) words")
    }

    func transcribeQuestion() async -> String {
        "can you explain the limit step more simply?"
    }
}
