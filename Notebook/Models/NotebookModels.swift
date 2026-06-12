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

struct ComfortSettings: Hashable, Codable {
    var enabledFeatures: Set<ComfortFeature>

    static let `default` = ComfortSettings(enabledFeatures: [
        .einkPaper,
        .warmPaper,
        .softerInk,
        .mutedAccents,
        .lessGlow,
        .calmerMotion,
        .staticPaper,
        .largeReadingText,
        .roomyLines,
        .scannerLowGlare,
        .scannerSteadyFrame,
        .pageTexture,
        .softRules,
        .tapTargets
    ])

    func isEnabled(_ feature: ComfortFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    mutating func set(_ feature: ComfortFeature, enabled: Bool) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }

    var warmth: Double {
        var value = 0.08
        if isEnabled(.warmPaper) { value += 0.12 }
        if isEnabled(.reducedBlue) { value += 0.08 }
        if isEnabled(.eveningShade) { value += 0.14 }
        return min(value, 0.38)
    }

    var paperWash: Double {
        var value = isEnabled(.einkPaper) ? 0.16 : 0.06
        if isEnabled(.matteGlass) { value += 0.05 }
        if isEnabled(.focusVignette) { value += 0.04 }
        return min(value, 0.32)
    }

    var saturation: Double {
        var value = 1.0
        if isEnabled(.mutedAccents) { value -= 0.18 }
        if isEnabled(.graphiteOnly) { value -= 0.42 }
        if isEnabled(.scannerLowGlare) { value -= 0.06 }
        return max(value, 0.42)
    }

    var contrast: Double {
        var value = 1.0
        if isEnabled(.softerInk) { value -= 0.08 }
        if isEnabled(.einkPaper) { value -= 0.04 }
        if isEnabled(.ocrSharpness) { value += 0.04 }
        return min(max(value, 0.82), 1.08)
    }

    var brightness: Double {
        var value = 0.0
        if isEnabled(.eveningShade) { value -= 0.035 }
        if isEnabled(.batterySaver) { value -= 0.012 }
        return value
    }

    var textureDensity: Int {
        var density = 80
        if isEnabled(.paperGrain) { density += 110 }
        if isEnabled(.pageTexture) { density += 70 }
        if isEnabled(.batterySaver) { density = max(30, density / 2) }
        return density
    }

    var reducesMotion: Bool {
        isEnabled(.calmerMotion) || isEnabled(.noPulse) || isEnabled(.lowRefresh) || isEnabled(.batterySaver)
    }

    var scannerIsQuiet: Bool {
        isEnabled(.scannerLowGlare) || isEnabled(.scannerSteadyFrame) || isEnabled(.scannerQuietProcessing)
    }

    var comfortScore: Int {
        min(100, Int((Double(enabledFeatures.count) / Double(ComfortFeature.allCases.count) * 100).rounded()))
    }
}

enum ComfortFeature: String, CaseIterable, Identifiable, Hashable, Codable {
    case einkPaper
    case warmPaper
    case matteGlass
    case softerInk
    case reducedBlue
    case mutedAccents
    case graphiteOnly
    case lessGlow
    case calmerMotion
    case staticPaper
    case noPulse
    case largeReadingText
    case roomyLines
    case widerMargins
    case focusVignette
    case readingRuler
    case tapTargets
    case scannerLowGlare
    case scannerSteadyFrame
    case scannerQuietProcessing
    case ocrSharpness
    case pageTexture
    case paperGrain
    case softRules
    case marginGuide
    case hiddenProgressNoise
    case compactToolbars
    case batterySaver
    case lowRefresh
    case eveningShade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .einkPaper: "e ink paper"
        case .warmPaper: "warm paper"
        case .matteGlass: "matte glass"
        case .softerInk: "softer ink"
        case .reducedBlue: "reduced blue"
        case .mutedAccents: "muted accents"
        case .graphiteOnly: "graphite only"
        case .lessGlow: "less glow"
        case .calmerMotion: "calmer motion"
        case .staticPaper: "static paper"
        case .noPulse: "no pulse"
        case .largeReadingText: "larger reading"
        case .roomyLines: "roomy lines"
        case .widerMargins: "wide margins"
        case .focusVignette: "focus vignette"
        case .readingRuler: "reading ruler"
        case .tapTargets: "larger taps"
        case .scannerLowGlare: "low glare scan"
        case .scannerSteadyFrame: "steady frame"
        case .scannerQuietProcessing: "quiet processing"
        case .ocrSharpness: "ocr sharpness"
        case .pageTexture: "page texture"
        case .paperGrain: "paper grain"
        case .softRules: "soft rules"
        case .marginGuide: "margin guide"
        case .hiddenProgressNoise: "quiet progress"
        case .compactToolbars: "compact tools"
        case .batterySaver: "battery saver"
        case .lowRefresh: "low refresh"
        case .eveningShade: "evening shade"
        }
    }

    var detail: String {
        switch self {
        case .einkPaper: "low glare off white paper wash"
        case .warmPaper: "warmer surface for long sessions"
        case .matteGlass: "flattens shiny glass panels"
        case .softerInk: "reduces harsh black contrast"
        case .reducedBlue: "cuts cool light from the ui"
        case .mutedAccents: "quieter colors across notebooks"
        case .graphiteOnly: "near monochrome study mode"
        case .lessGlow: "reduces luminous effects"
        case .calmerMotion: "shortens animated movement"
        case .staticPaper: "keeps paper backgrounds still"
        case .noPulse: "removes pulsing decorations"
        case .largeReadingText: "prefers easier reading sizes"
        case .roomyLines: "adds breathing room to text"
        case .widerMargins: "keeps text away from edges"
        case .focusVignette: "soft edge shade while reading"
        case .readingRuler: "adds a subtle line guide"
        case .tapTargets: "keeps controls finger friendly"
        case .scannerLowGlare: "dims the scanner surface"
        case .scannerSteadyFrame: "simplifies scan frame motion"
        case .scannerQuietProcessing: "calmer scan processing"
        case .ocrSharpness: "adds slight text clarity contrast"
        case .pageTexture: "adds tactile paper depth"
        case .paperGrain: "adds fine paper grain"
        case .softRules: "softens ruled paper lines"
        case .marginGuide: "keeps the red margin subtle"
        case .hiddenProgressNoise: "hides extra status noise"
        case .compactToolbars: "reduces toolbar weight"
        case .batterySaver: "cuts animation and texture work"
        case .lowRefresh: "slows decorative refresh"
        case .eveningShade: "warmer dimmer night reading"
        }
    }

    var symbol: String {
        switch self {
        case .einkPaper: "text.page"
        case .warmPaper: "sun.haze.fill"
        case .matteGlass: "circle.lefthalf.filled"
        case .softerInk: "drop.fill"
        case .reducedBlue: "moon.fill"
        case .mutedAccents: "paintpalette.fill"
        case .graphiteOnly: "circle.grid.cross"
        case .lessGlow: "lightbulb.min"
        case .calmerMotion: "slowmo"
        case .staticPaper: "pause.fill"
        case .noPulse: "waveform.path"
        case .largeReadingText: "textformat.size"
        case .roomyLines: "line.3.horizontal"
        case .widerMargins: "increase.indent"
        case .focusVignette: "viewfinder"
        case .readingRuler: "ruler.fill"
        case .tapTargets: "target"
        case .scannerLowGlare: "camera.filters"
        case .scannerSteadyFrame: "viewfinder.rectangular"
        case .scannerQuietProcessing: "wand.and.rays.inverse"
        case .ocrSharpness: "text.viewfinder"
        case .pageTexture: "doc.richtext"
        case .paperGrain: "circle.hexagongrid.fill"
        case .softRules: "list.bullet"
        case .marginGuide: "sidebar.left"
        case .hiddenProgressNoise: "eye.slash.fill"
        case .compactToolbars: "rectangle.compress.vertical"
        case .batterySaver: "battery.75percent"
        case .lowRefresh: "tortoise.fill"
        case .eveningShade: "moon.zzz.fill"
        }
    }

    var group: ComfortFeatureGroup {
        switch self {
        case .einkPaper, .warmPaper, .matteGlass, .softerInk, .reducedBlue, .mutedAccents, .graphiteOnly, .lessGlow, .eveningShade:
            .surface
        case .calmerMotion, .staticPaper, .noPulse, .batterySaver, .lowRefresh:
            .motion
        case .largeReadingText, .roomyLines, .widerMargins, .focusVignette, .readingRuler, .tapTargets:
            .reading
        case .scannerLowGlare, .scannerSteadyFrame, .scannerQuietProcessing, .ocrSharpness:
            .scanner
        case .pageTexture, .paperGrain, .softRules, .marginGuide, .hiddenProgressNoise, .compactToolbars:
            .notebook
        }
    }
}

enum ComfortFeatureGroup: String, CaseIterable, Identifiable {
    case surface
    case motion
    case reading
    case scanner
    case notebook

    var id: String { rawValue }
}

enum ComfortPreset: String, CaseIterable, Identifiable {
    case paper
    case focus
    case evening
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "paper"
        case .focus: "focus"
        case .evening: "evening"
        case .performance: "fast"
        }
    }

    var symbol: String {
        switch self {
        case .paper: "text.page"
        case .focus: "viewfinder"
        case .evening: "moon.zzz.fill"
        case .performance: "bolt.fill"
        }
    }

    var features: Set<ComfortFeature> {
        switch self {
        case .paper:
            [
                .einkPaper, .warmPaper, .matteGlass, .softerInk, .mutedAccents,
                .lessGlow, .staticPaper, .largeReadingText, .roomyLines, .widerMargins,
                .pageTexture, .paperGrain, .softRules, .marginGuide, .tapTargets
            ]
        case .focus:
            [
                .einkPaper, .softerInk, .reducedBlue, .mutedAccents, .graphiteOnly,
                .lessGlow, .calmerMotion, .staticPaper, .noPulse, .largeReadingText,
                .roomyLines, .widerMargins, .focusVignette, .readingRuler, .hiddenProgressNoise,
                .compactToolbars, .scannerLowGlare, .scannerSteadyFrame
            ]
        case .evening:
            [
                .einkPaper, .warmPaper, .matteGlass, .softerInk, .reducedBlue,
                .mutedAccents, .lessGlow, .calmerMotion, .staticPaper, .noPulse,
                .largeReadingText, .roomyLines, .focusVignette, .readingRuler, .scannerLowGlare,
                .scannerQuietProcessing, .pageTexture, .softRules, .eveningShade
            ]
        case .performance:
            [
                .einkPaper, .matteGlass, .softerInk, .mutedAccents, .lessGlow,
                .calmerMotion, .staticPaper, .noPulse, .scannerSteadyFrame, .scannerQuietProcessing,
                .hiddenProgressNoise, .compactToolbars, .batterySaver, .lowRefresh
            ]
        }
    }
}

enum AvatarDetail: String, CaseIterable, Identifiable, Hashable, Codable {
    case spark
    case orbit
    case notes
    case prism
    case wave
    case grid
    case constellation
    case bloom
    case contour

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
    var coverStyle: NotebookCoverStyle
    var coverColor: ColorToken
    var coverLabelStyle: NotebookLabelStyle
    var coverFontStyle: NotebookCoverFontStyle
    var customCoverData: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case pages
        case progress
        case lastActivity
        case isPinned
        case accent
        case coverStyle
        case coverColor
        case coverLabelStyle
        case coverFontStyle
        case customCoverData
    }

    init(
        id: UUID = UUID(),
        subject: String,
        pages: [NotebookPage],
        progress: Double,
        lastActivity: String,
        isPinned: Bool,
        accent: ColorToken,
        coverStyle: NotebookCoverStyle = .marbled,
        coverColor: ColorToken = .graphite,
        coverLabelStyle: NotebookLabelStyle = .classic,
        coverFontStyle: NotebookCoverFontStyle = .serif,
        customCoverData: Data? = nil
    ) {
        self.id = id
        self.subject = subject
        self.pages = pages
        self.progress = progress
        self.lastActivity = lastActivity
        self.isPinned = isPinned
        self.accent = accent
        self.coverStyle = coverStyle
        self.coverColor = coverColor
        self.coverLabelStyle = coverLabelStyle
        self.coverFontStyle = coverFontStyle
        self.customCoverData = customCoverData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subject = try container.decode(String.self, forKey: .subject)
        pages = try container.decode([NotebookPage].self, forKey: .pages)
        progress = try container.decode(Double.self, forKey: .progress)
        lastActivity = try container.decode(String.self, forKey: .lastActivity)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        accent = try container.decode(ColorToken.self, forKey: .accent)
        coverStyle = try container.decodeIfPresent(NotebookCoverStyle.self, forKey: .coverStyle) ?? .marbled
        coverColor = try container.decodeIfPresent(ColorToken.self, forKey: .coverColor) ?? .graphite
        coverLabelStyle = try container.decodeIfPresent(NotebookLabelStyle.self, forKey: .coverLabelStyle) ?? .classic
        coverFontStyle = try container.decodeIfPresent(NotebookCoverFontStyle.self, forKey: .coverFontStyle) ?? .serif
        customCoverData = try container.decodeIfPresent(Data.self, forKey: .customCoverData)
    }
}

enum NotebookCoverStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    case marbled
    case solid
    case linen
    case paper

    var id: String { rawValue }

    var title: String { rawValue }

    var symbol: String {
        switch self {
        case .marbled: "scribble"
        case .solid: "rectangle.fill"
        case .linen: "square.grid.3x3.fill"
        case .paper: "doc.richtext"
        }
    }
}

enum NotebookLabelStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    case classic
    case minimal
    case lab
    case ruled
    case graffiti

    var id: String { rawValue }
    var title: String { rawValue }
}

enum NotebookCoverFontStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    case serif
    case rounded
    case mono
    case handwritten

    var id: String { rawValue }
    var title: String { rawValue }
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

struct ScanRouteNotice: Identifiable, Hashable {
    var id = UUID()
    var fromSubject: String
    var toSubject: String
    var pageCount: Int

    var moved: Bool {
        fromSubject != toSubject
    }
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
    var sourceEngine: String

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
        case sourceEngine
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
        confidence: Double,
        sourceEngine: String = "local"
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
        self.sourceEngine = sourceEngine.lowercased()
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
        sourceEngine = try container.decodeIfPresent(String.self, forKey: .sourceEngine) ?? "local"
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
    var signature: HandwritingSignature? = nil

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

struct HandwritingSignature: Hashable, Codable {
    var rhythm: Double
    var consistency: Double
    var correctionNeed: Double
    var studyReadiness: Double
    var identity: String
    var nextStroke: String
    var predictedIssue: String
    var strengths: [String]

    static let empty = HandwritingSignature(
        rhythm: 0,
        consistency: 0,
        correctionNeed: 0,
        studyReadiness: 0,
        identity: "steady",
        nextStroke: "",
        predictedIssue: "",
        strengths: []
    )
}

struct InkReplayPlan: Hashable {
    var score: Double
    var title: String
    var detail: String
    var tint: ColorToken
    var strokes: [InkReplayStroke]
}

struct InkReplayStroke: Identifiable, Hashable {
    var id: String
    var start: CGPointUnit
    var control: CGPointUnit
    var end: CGPointUnit
    var weight: Double
    var delay: Double
}

struct CGPointUnit: Hashable {
    var x: Double
    var y: Double
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

struct ModelReadiness: Hashable {
    var score: Double
    var reason: String
    var action: String
    var symbol: String
    var tint: ColorToken

    static let empty = ModelReadiness(
        score: 0,
        reason: "scan first",
        action: "scan",
        symbol: "viewfinder",
        tint: .graphite
    )
}

struct StudyAutopilotPlan: Hashable {
    var kind: StudyAutopilotKind
    var pageID: NotebookPage.ID?
    var notebookID: SubjectNotebook.ID?
    var title: String
    var detail: String
    var symbol: String
    var tint: ColorToken
    var score: Double
    var steps: [StudyAutopilotStep]

    static let empty = StudyAutopilotPlan(
        kind: .scan,
        pageID: nil,
        notebookID: nil,
        title: "scan",
        detail: "add notes",
        symbol: "viewfinder",
        tint: .graphite,
        score: 0.16,
        steps: []
    )
}

enum StudyAutopilotKind: String, Hashable {
    case scan
    case clean
    case model
    case review
    case study
    case add
}

struct StudyAutopilotStep: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var done: Bool
}

struct StudyDailyBrief: Hashable {
    var score: Double
    var title: String
    var items: [StudyBriefItem]

    static let empty = StudyDailyBrief(score: 0, title: "ready", items: [])
}

struct StudyBriefItem: Identifiable, Hashable {
    var id = UUID()
    var kind: StudyBriefKind
    var pageID: NotebookPage.ID?
    var notebookID: SubjectNotebook.ID?
    var title: String
    var value: String
    var symbol: String
    var tint: ColorToken
    var score: Double
}

enum StudyBriefKind: String, Hashable {
    case scan
    case clean
    case model
    case review
    case search
}

struct StudyMemoryMap: Hashable {
    var score: Double
    var nodes: [StudyMemoryNode]

    static let empty = StudyMemoryMap(score: 0, nodes: [])
}

struct PresentationRunway: Hashable {
    var score: Double
    var title: String
    var detail: String
    var steps: [PresentationRunwayStep]

    static let empty = PresentationRunway(score: 0, title: "ready", detail: "add a course", steps: [])
}

struct PresentationRunwayStep: Identifiable, Hashable {
    var id: String
    var kind: PresentationRunwayKind
    var title: String
    var detail: String
    var symbol: String
    var tint: ColorToken
    var weight: Double
    var isReady: Bool
}

enum PresentationRunwayKind: String, Hashable {
    case scan
    case sort
    case model
    case review
    case search
    case avatar
}

struct StudyMemoryNode: Identifiable, Hashable {
    var id: String
    var kind: StudyMemoryNodeKind
    var pageID: NotebookPage.ID?
    var notebookID: SubjectNotebook.ID?
    var title: String
    var detail: String
    var symbol: String
    var tint: ColorToken
    var weight: Double
}

enum StudyMemoryNodeKind: String, Hashable {
    case keyword
    case model
    case review
    case notebook
    case formula
    case table
}

struct ModelForgePlan: Hashable {
    var score: Double
    var title: String
    var detail: String
    var symbol: String
    var tint: ColorToken
    var isReady: Bool
    var steps: [ModelForgeStep]
}

struct ModelForgeStep: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var tint: ColorToken
    var progress: Double
    var isComplete: Bool
}

struct ExamPulse: Hashable {
    var score: Double
    var title: String
    var prompt: String
    var symbol: String
    var tint: ColorToken
    var actions: [ExamPulseAction]
}

struct ExamPulseAction: Identifiable, Hashable {
    var id: String
    var kind: ExamPulseKind
    var title: String
    var detail: String
    var prompt: String
    var symbol: String
    var tint: ColorToken
    var weight: Double
}

enum ExamPulseKind: String, Hashable {
    case recall
    case model
    case formula
    case table
    case ask
    case drill
}

struct ForgettingForecast: Hashable {
    var score: Double
    var title: String
    var points: [ForgettingForecastPoint]
}

struct ForgettingForecastPoint: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var prompt: String
    var symbol: String
    var tint: ColorToken
    var weight: Double
    var action: ExamPulseKind
}

struct ConceptBridgeMap: Hashable {
    var score: Double
    var title: String
    var nodes: [ConceptBridgeNode]
}

struct ConceptBridgeNode: Identifiable, Hashable {
    var id: String
    var pageID: NotebookPage.ID
    var notebookID: SubjectNotebook.ID?
    var relation: ConceptBridgeRelation
    var title: String
    var detail: String
    var symbol: String
    var tint: ColorToken
    var weight: Double
}

enum ConceptBridgeRelation: String, Hashable {
    case keyword
    case formula
    case model
    case table
    case review
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

    var credentialSetupMessage: String {
        switch self {
        case .apple:
            "apple sign in needs your app services key."
        case .google:
            "google sign in needs your client id."
        case .email:
            "email sign in is ready."
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
    case avatar
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
