import Foundation
import SwiftUI

struct NotebookUser: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var gradeLevel: String
    var avatar: AvatarProfile = .default

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gradeLevel
        case avatar
    }

    init(id: UUID = UUID(), name: String, gradeLevel: String, avatar: AvatarProfile = .default) {
        self.id = id
        self.name = name
        self.gradeLevel = gradeLevel
        self.avatar = avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        gradeLevel = try container.decode(String.self, forKey: .gradeLevel)
        avatar = try container.decodeIfPresent(AvatarProfile.self, forKey: .avatar) ?? .default
    }
}

struct AvatarProfile: Hashable, Codable {
    var base: ColorToken
    var accent: ColorToken
    var symbol: String
    var detail: AvatarDetail

    static let `default` = AvatarProfile(base: .blue, accent: .green, symbol: "book.closed.fill", detail: .spark)
}

enum AvatarDetail: String, CaseIterable, Identifiable, Hashable, Codable {
    case spark
    case orbit
    case notes
    case prism
    case wave
    case grid

    var id: String { rawValue }
}

struct SubjectNotebook: Identifiable, Hashable, Codable {
    var id = UUID()
    var subject: String
    var pages: [NotebookPage]
    var progress: Double
    var lastActivity: String
    var isPinned: Bool
    var accent: ColorToken
}

struct NotebookPage: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var createdAt: Date
    var rawScanLabel: String
    var content: ExtractedContent
    var studyState: ReviewState
}

struct ScanJob: Identifiable, Hashable, Codable {
    var id = UUID()
    var targetSubject: String?
    var phase: ScanPhase
}

struct ExtractedContent: Identifiable, Hashable, Codable {
    var id = UUID()
    var cleanedText: String
    var rawText: String
    var keywords: [String]
    var formulas: [String]
    var sections: [StudySection]
    var tables: [DetectedTable] = []
    var models: [DetectedModel] = []
    var insight: SmartPageInsight = .empty
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case cleanedText
        case rawText
        case keywords
        case formulas
        case sections
        case tables
        case models
        case insight
        case confidence
    }

    init(
        id: UUID = UUID(),
        cleanedText: String,
        rawText: String,
        keywords: [String],
        formulas: [String],
        sections: [StudySection],
        tables: [DetectedTable] = [],
        models: [DetectedModel] = [],
        insight: SmartPageInsight = .empty,
        confidence: Double
    ) {
        self.id = id
        self.cleanedText = cleanedText
        self.rawText = rawText
        self.keywords = keywords
        self.formulas = formulas
        self.sections = sections
        self.tables = tables
        self.models = models
        self.insight = insight
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cleanedText = try container.decode(String.self, forKey: .cleanedText)
        rawText = try container.decode(String.self, forKey: .rawText)
        keywords = try container.decode([String].self, forKey: .keywords)
        formulas = try container.decode([String].self, forKey: .formulas)
        sections = try container.decode([StudySection].self, forKey: .sections)
        tables = try container.decodeIfPresent([DetectedTable].self, forKey: .tables) ?? []
        models = try container.decodeIfPresent([DetectedModel].self, forKey: .models) ?? []
        insight = try container.decodeIfPresent(SmartPageInsight.self, forKey: .insight) ?? .empty
        confidence = try container.decode(Double.self, forKey: .confidence)
    }
}

struct SmartPageInsight: Identifiable, Hashable, Codable {
    var id = UUID()
    var onlyWhatMatters: String
    var nextBestStep: String
    var clarityScore: Double
    var retentionRisk: Double
    var estimatedReadMinutes: Int
    var handwriting: HandwritingAnalysis
    var studyLanes: [StudyLane]
    var recallPrompts: [String]
    var quickQuestions: [String]
    var memoryHooks: [String]
    var examAngles: [String]
    var confusionAlerts: [String]
    var cleanupSuggestions: [String]
    var detectedFeatures: [String]

    static let empty = SmartPageInsight(
        onlyWhatMatters: "",
        nextBestStep: "",
        clarityScore: 0,
        retentionRisk: 0,
        estimatedReadMinutes: 1,
        handwriting: .empty,
        studyLanes: [],
        recallPrompts: [],
        quickQuestions: [],
        memoryHooks: [],
        examAngles: [],
        confusionAlerts: [],
        cleanupSuggestions: [],
        detectedFeatures: []
    )

    enum CodingKeys: String, CodingKey {
        case id
        case onlyWhatMatters
        case nextBestStep
        case clarityScore
        case retentionRisk
        case estimatedReadMinutes
        case handwriting
        case studyLanes
        case recallPrompts
        case quickQuestions
        case memoryHooks
        case examAngles
        case confusionAlerts
        case cleanupSuggestions
        case detectedFeatures
    }

    init(
        id: UUID = UUID(),
        onlyWhatMatters: String,
        nextBestStep: String,
        clarityScore: Double,
        retentionRisk: Double,
        estimatedReadMinutes: Int,
        handwriting: HandwritingAnalysis,
        studyLanes: [StudyLane],
        recallPrompts: [String],
        quickQuestions: [String],
        memoryHooks: [String],
        examAngles: [String],
        confusionAlerts: [String],
        cleanupSuggestions: [String],
        detectedFeatures: [String]
    ) {
        self.id = id
        self.onlyWhatMatters = onlyWhatMatters
        self.nextBestStep = nextBestStep
        self.clarityScore = clarityScore
        self.retentionRisk = retentionRisk
        self.estimatedReadMinutes = estimatedReadMinutes
        self.handwriting = handwriting
        self.studyLanes = studyLanes
        self.recallPrompts = recallPrompts
        self.quickQuestions = quickQuestions
        self.memoryHooks = memoryHooks
        self.examAngles = examAngles
        self.confusionAlerts = confusionAlerts
        self.cleanupSuggestions = cleanupSuggestions
        self.detectedFeatures = detectedFeatures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        onlyWhatMatters = try container.decodeIfPresent(String.self, forKey: .onlyWhatMatters) ?? ""
        nextBestStep = try container.decodeIfPresent(String.self, forKey: .nextBestStep) ?? ""
        clarityScore = try container.decodeIfPresent(Double.self, forKey: .clarityScore) ?? 0
        retentionRisk = try container.decodeIfPresent(Double.self, forKey: .retentionRisk) ?? 0
        estimatedReadMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedReadMinutes) ?? 1
        handwriting = try container.decodeIfPresent(HandwritingAnalysis.self, forKey: .handwriting) ?? .empty
        studyLanes = try container.decodeIfPresent([StudyLane].self, forKey: .studyLanes) ?? []
        recallPrompts = try container.decodeIfPresent([String].self, forKey: .recallPrompts) ?? []
        quickQuestions = try container.decodeIfPresent([String].self, forKey: .quickQuestions) ?? []
        memoryHooks = try container.decodeIfPresent([String].self, forKey: .memoryHooks) ?? []
        examAngles = try container.decodeIfPresent([String].self, forKey: .examAngles) ?? []
        confusionAlerts = try container.decodeIfPresent([String].self, forKey: .confusionAlerts) ?? []
        cleanupSuggestions = try container.decodeIfPresent([String].self, forKey: .cleanupSuggestions) ?? []
        detectedFeatures = try container.decodeIfPresent([String].self, forKey: .detectedFeatures) ?? []
    }
}

struct HandwritingAnalysis: Hashable, Codable {
    var legibility: Double
    var inkDensity: Double
    var spacing: Double
    var structure: Double
    var pace: WritingPace
    var pressure: WritingPressure
    var noteStyle: NoteStyle
    var coaching: String

    static let empty = HandwritingAnalysis(
        legibility: 0,
        inkDensity: 0,
        spacing: 0,
        structure: 0,
        pace: .steady,
        pressure: .balanced,
        noteStyle: .linear,
        coaching: ""
    )
}

struct StudyLane: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var systemName: String
    var value: String
}

enum WritingPace: String, Hashable, Codable {
    case rushed
    case steady
    case deliberate
}

enum WritingPressure: String, Hashable, Codable {
    case light
    case balanced
    case heavy
}

enum NoteStyle: String, Hashable, Codable {
    case linear
    case diagram
    case table
    case formula
    case mixed
}

struct StudySection: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var body: String
}

struct DetectedTable: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var headers: [String]
    var rows: [[String]]
}

struct DetectedModel: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var summary: String
    var terms: [String]
    var nodes: [String]? = nil
    var reconstruction: ModelReconstruction? = nil
}

struct ModelReconstruction: Hashable, Codable {
    var source: String
    var confidence: Double
    var shape: ModelShape
    var anchors: [ModelAnchor]
    var interactionHint: String
}

struct ModelAnchor: Identifiable, Hashable, Codable {
    var id = UUID()
    var label: String
    var x: Double
    var y: Double
    var z: Double
}

enum ModelShape: String, CaseIterable, Identifiable, Hashable, Codable {
    case orbit
    case mesh
    case table
    case cycle
    case stack

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .orbit: "circle.dotted.circle"
        case .mesh: "point.3.connected.trianglepath.dotted"
        case .table: "tablecells"
        case .cycle: "arrow.trianglehead.2.clockwise.rotate.90"
        case .stack: "square.stack.3d.up.fill"
        }
    }
}

struct Flashcard: Identifiable, Hashable, Codable {
    var id = UUID()
    var front: String
    var back: String
}

struct ReviewState: Hashable, Codable {
    var dueLabel: String
    var stability: Double
    var difficulty: Double
    var lastReviewedAt: Date? = nil
    var reviewCount: Int = 0
    var lapses: Int = 0

    enum CodingKeys: String, CodingKey {
        case dueLabel
        case stability
        case difficulty
        case lastReviewedAt
        case reviewCount
        case lapses
    }

    init(dueLabel: String, stability: Double, difficulty: Double, lastReviewedAt: Date? = nil, reviewCount: Int = 0, lapses: Int = 0) {
        self.dueLabel = dueLabel
        self.stability = stability
        self.difficulty = difficulty
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
        self.lapses = lapses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dueLabel = try container.decode(String.self, forKey: .dueLabel)
        stability = try container.decode(Double.self, forKey: .stability)
        difficulty = try container.decode(Double.self, forKey: .difficulty)
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
    }
}

enum ReviewGrade: String, CaseIterable, Identifiable, Hashable, Codable {
    case forgot
    case hard
    case good
    case easy

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .forgot: "arrow.counterclockwise"
        case .hard: "flame.fill"
        case .good: "checkmark"
        case .easy: "sparkles"
        }
    }
}

struct AIAction: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var systemName: String
    var result: String
}

struct VoiceProfile: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String = "my voice"
    var samples: [VoiceSample] = []
    var isPersonalized = false
    var wantsPersonalVoice = false
    var replicationBackend: VoiceReplicationBackend = .mossTTSV15
}

struct VoiceSample: Identifiable, Hashable, Codable {
    var id = UUID()
    var prompt: String
    var isRecorded: Bool
    var audioURL: URL?
    var duration: TimeInterval = 0
    var transcript: String? = nil
}

struct VoicePlayback: Hashable, Codable {
    var style: PlaybackStyle
    var summary: String
    var engine: VoiceReplicationBackend
    var referenceSampleCount: Int
    var audioURL: URL? = nil
}

enum VoiceReplicationBackend: String, Hashable, Codable {
    case mossTTSV15 = "moss-tts"
    case kokoro = "kokoro"

    var modelID: String {
        switch self {
        case .mossTTSV15: "OpenMOSS-Team/MOSS-TTS-v1.5"
        case .kokoro: "hexgrad/kokoro"
        }
    }

    var sourceURL: URL {
        switch self {
        case .mossTTSV15:
            URL(string: "https://huggingface.co/spaces/OpenMOSS-Team/MOSS-TTS-v1.5/tree/main")!
        case .kokoro:
            URL(string: "https://github.com/hexgrad/kokoro")!
        }
    }

    var displayName: String {
        switch self {
        case .mossTTSV15: "moss-tts v1.5"
        case .kokoro: "kokoro"
        }
    }
}

enum PageDisplayMode: String, CaseIterable, Identifiable, Codable {
    case cleaned = "cleaned"
    case raw = "raw"

    var id: String { rawValue }
}

enum MemorizationMode: String, CaseIterable, Identifiable, Codable {
    case shortTerm = "short term"
    case longTerm = "long term"

    var id: String { rawValue }
}

enum PlaybackStyle: String, CaseIterable, Identifiable, Codable {
    case calmTutor = "calm tutor"
    case focusedReview = "focused review"
    case examPrep = "exam prep"

    var id: String { rawValue }
}

struct AuthSession: Hashable, Codable {
    var provider: AuthProvider
    var email: String
    var username: String
    var createdAt: Date
}

enum AuthProvider: String, CaseIterable, Identifiable, Codable {
    case apple
    case google
    case email

    var id: String { rawValue }

    var defaultEmail: String {
        switch self {
        case .apple: "student@icloud.com"
        case .google: "student@gmail.com"
        case .email: "student@email.com"
        }
    }

    var title: String {
        switch self {
        case .apple: "sign up with apple"
        case .google: "sign up with google"
        case .email: "sign up with email"
        }
    }

    var signInTitle: String {
        switch self {
        case .apple: "sign in with apple"
        case .google: "sign in with google"
        case .email: "sign in with email"
        }
    }

    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .email: "envelope.fill"
        }
    }
}

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case passwordMismatch
    case missingUsername
    case accountNotFound
    case invalidPassword
    case secureStorageFailed

    var errorDescription: String? {
        switch self {
        case .invalidEmail: "enter a valid email."
        case .weakPassword: "use at least six characters."
        case .passwordMismatch: "passwords must match."
        case .missingUsername: "choose a username."
        case .accountNotFound: "no saved account found for that email."
        case .invalidPassword: "that password does not match this account."
        case .secureStorageFailed: "secure account storage failed."
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case light
    case dark
    case device

    var id: String { rawValue }
}

enum SetupStep: Hashable, Codable {
    case voiceRecording
    case theme
    case subjects
}

enum PasswordStrength: String {
    case weak
    case medium
    case good

    var color: Color {
        switch self {
        case .weak: .red
        case .medium: .yellow
        case .good: .green
        }
    }
}

enum ScanPhase: String, CaseIterable, Identifiable, Codable {
    case framing = "framing"
    case capturing = "capturing"
    case processing = "processing"
    case organizing = "organizing"
    case sorted = "sorted"

    var id: String { rawValue }

    var caption: String {
        switch self {
        case .framing: "align page"
        case .capturing: "capturing knowledge"
        case .processing: "cleaning ink"
        case .organizing: "finding subject"
        case .sorted: "organized"
        }
    }
}

enum ColorToken: String, CaseIterable, Hashable, Codable {
    case graphite
    case blue
    case green
    case plum
    case amber
}
