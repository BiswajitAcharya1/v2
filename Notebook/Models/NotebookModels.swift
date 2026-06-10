import Foundation
import SwiftUI

struct NotebookUser: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var gradeLevel: String
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
    var confidence: Double
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
