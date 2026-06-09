import Foundation

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
}

struct MockScanProcessingService: ScanProcessingServing {
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

struct MockNoteUnderstandingService: NoteUnderstandingServing {
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

struct MockSpacedRepetitionService: SpacedRepetitionServing {
    func schedule(_ card: Flashcard, mode: MemorizationMode) -> ReviewState {
        switch mode {
        case .shortTerm:
            ReviewState(dueLabel: "review in 35 min", stability: 0.34, difficulty: 0.52)
        case .longTerm:
            ReviewState(dueLabel: "review in 2 days", stability: 0.71, difficulty: 0.44)
        }
    }
}

struct MockVoiceService: VoiceServing {
    func makePlayback(_ text: String, style: PlaybackStyle, profile: VoiceProfile) async -> VoicePlayback {
        VoicePlayback(style: style, summary: "\(style.rawValue) prepared \(text.split(separator: " ").count) words")
    }
}
