import Foundation
import Observation
import SwiftUI
import AVFoundation
import UIKit
import Speech

@MainActor
@Observable
final class NotebookStore {
    var user = NotebookUser(name: "maya", gradeLevel: "11")
    var notebooks: [SubjectNotebook] = []
    var isAuthenticated = false
    var authSession: AuthSession?
    var authMessage: String?
    var hasCompletedOnboarding = false
    var setupStep: SetupStep = .voiceRecording
    var appTheme: AppTheme = .device
    var activeScanJob: ScanJob?
    var scanRouteNotice: ScanRouteNotice?
    var selectedStudyMode: MemorizationMode = .longTerm
    var voiceProfile = VoiceProfile()
    var scanPhase: ScanPhase = .framing
    var onboardingSubjects: [String] = ["math", "science", "history", "english"]
    var isRecordingVoice = false
    var isVoicePaused = false
    var voiceRecordingElapsed: TimeInterval = 0
    var voiceRecordingLevel: Double = 0
    var voiceSignalActive = false
    var voiceRecognitionAvailable = false
    var voicePromptWordProgress = 0
    var latestVoiceTranscript: String?

    private let authService: LocalAuthServing = LocalAuthService()
    private let scanProcessor: ScanProcessingServing = LocalScanProcessingService()
    private let aiService: NoteUnderstandingServing = LocalNoteUnderstandingService()
    private let reviewService: SpacedRepetitionServing = LocalSpacedRepetitionService()
    private let voiceService: VoiceServing = MossTTSVoiceService()
    @ObservationIgnored private let persistence = AppPersistence()
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var voiceTapInstalled = false
    @ObservationIgnored private var voiceAudioFile: AVAudioFile?
    @ObservationIgnored private var liveRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var liveRecognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var pendingVoiceFinishTask: Task<Void, Never>?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var recordingPrompt: String?
    @ObservationIgnored private var voiceRecordingStartedAt: Date?
    @ObservationIgnored private var lastVoiceHeardAt: Date?
    @ObservationIgnored private var voiceNoiseFloor: Double = 0.025
    @ObservationIgnored private var voiceSignalStartedAt: Date?
    @ObservationIgnored private var voiceActiveSpeechDuration: TimeInterval = 0
    @ObservationIgnored private var lastVoiceActivityTick: Date?
    @ObservationIgnored private var lastVoiceMeterUIUpdateAt: Date?

    var pinnedNotebooks: [SubjectNotebook] {
        notebooks.filter(\.isPinned)
    }

    var preferredColorScheme: ColorScheme? {
        .light
    }

    init() {
        if let saved = persistence.load() {
            user = saved.user
            notebooks = saved.notebooks
            authSession = saved.authSession
            isAuthenticated = saved.authSession != nil
            hasCompletedOnboarding = saved.hasCompletedOnboarding
            setupStep = saved.setupStep
            appTheme = saved.appTheme
            selectedStudyMode = saved.selectedStudyMode
            voiceProfile = saved.voiceProfile
            onboardingSubjects = saved.onboardingSubjects
        }
    }

    func signIn(provider: AuthProvider) async {
        if provider == .apple || provider == .google {
            let message = "\(provider.rawValue) secrets are not added yet."
            authMessage = message
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.4))
                if authMessage == message {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        authMessage = nil
                    }
                }
            }
            return
        }
        let session = await authService.signIn(provider: provider)
        completeAuth(session)
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await authService.signIn(email: email, password: password)
            completeAuth(session)
        } catch {
            authMessage = error.localizedDescription.lowercased()
        }
    }

    func signUp(username: String, email: String, password: String, confirmPassword: String) async {
        do {
            let session = try await authService.signUp(username: username, email: email, password: password, confirmPassword: confirmPassword)
            completeAuth(session)
        } catch {
            authMessage = error.localizedDescription.lowercased()
        }
    }

    func resetPassword(email: String) async {
        do {
            authMessage = try await authService.sendReset(email: email)
        } catch {
            authMessage = error.localizedDescription.lowercased()
        }
    }

    func signOut() {
        withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) {
            authSession = nil
            isAuthenticated = false
            hasCompletedOnboarding = false
            setupStep = .voiceRecording
            authMessage = nil
        }
        persist()
    }

    func finishOnboarding() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            hasCompletedOnboarding = true
            setupStep = .voiceRecording
        }
        persist()
    }

    func choosePersonalVoice(_ wantsPersonalVoice: Bool) {
        voiceProfile.wantsPersonalVoice = wantsPersonalVoice
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            setupStep = wantsPersonalVoice ? .voiceRecording : .subjects
        }
        persist()
    }

    func recordVoicePrompt(_ prompt: String) async {
        guard voiceProfile.samples.count < 3 else { return }
        if isRecordingVoice {
            finishVoicePrompt()
        } else {
            await startVoicePrompt(prompt)
        }
    }

    func pauseVoiceRecording() {
        guard isRecordingVoice, !isVoicePaused else { return }
        audioEngine?.pause()
        isVoicePaused = true
    }

    func resumeVoiceRecording() {
        guard isRecordingVoice, isVoicePaused else { return }
        try? audioEngine?.start()
        isVoicePaused = false
    }

    func skipVoiceSetup() {
        voiceProfile.wantsPersonalVoice = false
        voiceProfile.isPersonalized = false
        voiceProfile.samples.removeAll()
        isRecordingVoice = false
        isVoicePaused = false
        voiceRecordingElapsed = 0
        voiceRecordingLevel = 0
        voiceSignalActive = false
        voiceRecognitionAvailable = false
        voicePromptWordProgress = 0
        latestVoiceTranscript = nil
        stopLiveVoiceCapture(cancelRecognition: true)
        recordingURL = nil
        recordingPrompt = nil
        voiceRecordingStartedAt = nil
        lastVoiceHeardAt = nil
        voiceNoiseFloor = 0.025
        voiceSignalStartedAt = nil
        voiceActiveSpeechDuration = 0
        lastVoiceActivityTick = nil
        lastVoiceMeterUIUpdateAt = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            setupStep = .subjects
        }
        persist()
    }

    func retakeVoicePrompt() {
        guard !voiceProfile.samples.isEmpty else { return }
        voiceProfile.samples.removeLast()
        voiceProfile.isPersonalized = false
        persist()
    }

    func chooseTheme(_ theme: AppTheme) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            appTheme = theme
        }
        persist()
    }

    func continueToSubjects() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            setupStep = .subjects
        }
        persist()
    }

    func setSubjects(_ subjects: [String]) {
        let cleaned = subjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        onboardingSubjects = cleaned
        notebooks = cleaned.enumerated().map { index, subject in
            SubjectNotebook(
                subject: subject,
                pages: [],
                progress: 0,
                lastActivity: "ready to scan",
                isPinned: index == 0,
                accent: ColorToken.allCases[index % ColorToken.allCases.count]
            )
        }
        finishOnboarding()
    }

    func addCourse(_ subject: String) {
        let cleaned = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, !notebooks.contains(where: { $0.subject == cleaned }) else { return }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
            notebooks.append(
                SubjectNotebook(
                    subject: cleaned,
                    pages: [],
                    progress: 0,
                    lastActivity: "ready to scan",
                    isPinned: notebooks.isEmpty,
                    accent: ColorToken.allCases[notebooks.count % ColorToken.allCases.count]
                )
            )
            onboardingSubjects.append(cleaned)
        }
        persist()
    }

    private func completeAuth(_ session: AuthSession) {
        authSession = session
        authMessage = "\(session.provider.rawValue) ready"
        user.name = session.username.lowercased()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            isAuthenticated = true
            hasCompletedOnboarding = false
            setupStep = .voiceRecording
        }
        persist()
    }

    private func startVoicePrompt(_ prompt: String) async {
        stopLiveVoiceCapture(cancelRecognition: true)
        guard await requestMicrophonePermission() else {
            authMessage = "microphone access is needed to record voice."
            return
        }
        let speechAllowed = await requestSpeechPermission()
        let recognizer = speechAllowed ? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) : nil
        let session = AVAudioSession.sharedInstance()
        let fileName = "vellum-voice-\(UUID().uuidString).caf"
        let url = voiceSamplesDirectory().appendingPathComponent(fileName)

        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try? session.setPreferredSampleRate(44_100)
            try? session.setPreferredIOBufferDuration(0.025)
            try session.setActive(true)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceRecordingError.failedToStart
            }
            audioEngine = engine
            let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
            var recognitionTask: SFSpeechRecognitionTask?
            if let recognizer, recognizer.isAvailable {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.addsPunctuation = false
                request.taskHint = .dictation
                request.contextualStrings = prompt.normalizedSpeechWords + ["vellum", "study", "tutor", "remember"]
                recognitionRequest = request
                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString.lowercased()
                        Task { @MainActor in
                            self.applyLiveVoiceTranscript(transcript, prompt: prompt)
                        }
                    } else if error != nil {
                        Task { @MainActor in
                            self.liveRecognitionTask = nil
                            self.liveRecognitionRequest = nil
                            self.voiceRecognitionAvailable = false
                        }
                    }
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    return
                }
                recognitionRequest?.append(buffer)
                let level = Self.normalizedVoiceLevel(buffer)
                Task { @MainActor in
                    guard let self, self.isRecordingVoice else { return }
                    let activeLevel = self.isVoicePaused ? 0 : level
                    let now = Date()
                    if let lastUpdate = self.lastVoiceMeterUIUpdateAt, now.timeIntervalSince(lastUpdate) < 1.0 / 18.0 {
                        return
                    }
                    self.lastVoiceMeterUIUpdateAt = now
                    let elapsed = self.voiceRecordingStartedAt.map { now.timeIntervalSince($0) } ?? 0
                    if elapsed < 0.55 {
                        self.voiceNoiseFloor = min(0.08, max(0.012, self.voiceNoiseFloor * 0.84 + activeLevel * 0.16))
                    }
                    let speechThreshold = max(0.045, min(0.18, self.voiceNoiseFloor + 0.045))
                    if activeLevel > speechThreshold {
                        if self.voiceSignalStartedAt == nil {
                            self.voiceSignalStartedAt = now
                        }
                        let sustainedSpeech = self.voiceSignalStartedAt.map { now.timeIntervalSince($0) > 0.08 } ?? false
                        if sustainedSpeech {
                            self.lastVoiceHeardAt = now
                            self.trackVoiceActivity(now: now)
                        }
                    } else if activeLevel < speechThreshold * 0.72 {
                        self.voiceSignalStartedAt = nil
                        self.lastVoiceActivityTick = nil
                    }
                    self.voiceSignalActive = self.lastVoiceHeardAt.map { now.timeIntervalSince($0) < 0.42 } ?? false
                    if !self.voiceSignalActive {
                        self.latestVoiceTranscript = nil
                    }
                    self.voiceRecordingLevel = activeLevel
                    if let startedAt = self.voiceRecordingStartedAt {
                        self.voiceRecordingElapsed = now.timeIntervalSince(startedAt)
                    }
                }
            }
            voiceTapInstalled = true

            liveRecognitionRequest = recognitionRequest
            liveRecognitionTask = recognitionTask
            voiceAudioFile = audioFile
            engine.prepare()
            try engine.start()
            recordingURL = url
            recordingPrompt = prompt
            voiceRecordingStartedAt = Date()
            voiceProfile.wantsPersonalVoice = true
            isRecordingVoice = true
            isVoicePaused = false
            voiceRecordingElapsed = 0
            voiceRecordingLevel = 0
            voiceSignalActive = false
            voiceRecognitionAvailable = recognitionRequest != nil
            voicePromptWordProgress = 0
            latestVoiceTranscript = nil
            lastVoiceHeardAt = nil
            voiceNoiseFloor = 0.025
            voiceSignalStartedAt = nil
            voiceActiveSpeechDuration = 0
            lastVoiceActivityTick = nil
            lastVoiceMeterUIUpdateAt = nil
        } catch {
            stopLiveVoiceCapture(cancelRecognition: true)
            recordingURL = nil
            recordingPrompt = nil
            isVoicePaused = false
            voiceRecordingElapsed = 0
            voiceRecordingLevel = 0
            voiceSignalActive = false
            voiceRecognitionAvailable = false
            voicePromptWordProgress = 0
            voiceRecordingStartedAt = nil
            lastVoiceHeardAt = nil
            voiceNoiseFloor = 0.025
            voiceSignalStartedAt = nil
            voiceActiveSpeechDuration = 0
            lastVoiceActivityTick = nil
            lastVoiceMeterUIUpdateAt = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            authMessage = "voice recording could not start."
        }
    }

    private func finishVoicePrompt() {
        guard let url = recordingURL else { return }
        stopLiveVoiceCapture(cancelRecognition: false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecordingVoice = false
        isVoicePaused = false

        let prompt = recordingPrompt ?? ""
        let duration = voiceRecordingElapsed
        let completedProgress = voicePromptWordProgress
        let hadWordRecognition = voiceRecognitionAvailable
        let capturedSpeechDuration = voiceActiveSpeechDuration
        voiceRecordingElapsed = 0
        voiceRecordingLevel = 0
        voiceSignalActive = false
        voiceRecognitionAvailable = false
        voicePromptWordProgress = 0
        voiceRecordingStartedAt = nil
        lastVoiceHeardAt = nil
        voiceNoiseFloor = 0.025
        voiceSignalStartedAt = nil
        voiceActiveSpeechDuration = 0
        lastVoiceActivityTick = nil
        lastVoiceMeterUIUpdateAt = nil
        recordingURL = nil
        recordingPrompt = nil
        guard duration >= 0.5 else {
            authMessage = "record a little longer so voice can be saved."
            try? FileManager.default.removeItem(at: url)
            return
        }
        if hadWordRecognition {
            guard completedProgress >= max(1, prompt.normalizedSpeechWords.count - 1) else {
                authMessage = "read the sentence once so the voice sample can match it."
                try? FileManager.default.removeItem(at: url)
                return
            }
        } else {
            let targetSpeechDuration = max(0.9, min(2.4, Double(prompt.normalizedSpeechWords.count) * 0.24))
            guard capturedSpeechDuration >= targetSpeechDuration else {
                authMessage = "keep reading until the voice meter stays active."
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
        let sampleID = UUID()
        voiceProfile.samples.append(VoiceSample(id: sampleID, prompt: prompt, isRecorded: true, audioURL: url, duration: duration))
        voiceProfile.isPersonalized = voiceProfile.samples.count == 3
        if voiceProfile.isPersonalized {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                setupStep = .subjects
            }
        }
        persist()

        Task { @MainActor in
            let transcript = await transcribeVoiceSample(at: url)
            guard let sampleIndex = voiceProfile.samples.firstIndex(where: { $0.id == sampleID }) else { return }
            voiceProfile.samples[sampleIndex].transcript = transcript.isEmpty ? nil : transcript
            latestVoiceTranscript = transcript.isEmpty ? nil : transcript
            persist()
        }
    }

    private func trackVoiceActivity(now: Date) {
        if let lastVoiceActivityTick {
            voiceActiveSpeechDuration += min(0.18, max(0, now.timeIntervalSince(lastVoiceActivityTick)))
        }
        lastVoiceActivityTick = now
    }

    private func applyLiveVoiceTranscript(_ transcript: String, prompt: String) {
        guard isRecordingVoice else { return }
        let heardRecently = lastVoiceHeardAt.map { Date().timeIntervalSince($0) < 0.58 } ?? false
        guard heardRecently else {
            latestVoiceTranscript = nil
            return
        }
        latestVoiceTranscript = transcript.isEmpty ? nil : transcript
        let matchedWords = matchedPromptWordCount(prompt: prompt, transcript: transcript)
        if matchedWords > voicePromptWordProgress {
            Haptics.selection()
        }
        voicePromptWordProgress = max(voicePromptWordProgress, matchedWords)
        let targetCount = prompt.normalizedSpeechWords.count
        if targetCount > 0, voicePromptWordProgress >= targetCount, voiceRecordingElapsed > 0.9 {
            scheduleVoicePromptFinish(expectedProgress: targetCount)
        }
    }

    private func matchedPromptWordCount(prompt: String, transcript: String) -> Int {
        let promptWords = prompt.normalizedSpeechWords
        let transcriptWords = transcript.normalizedSpeechWords
        guard !promptWords.isEmpty, !transcriptWords.isEmpty else { return 0 }

        var matched = 0
        for spoken in transcriptWords {
            guard matched < promptWords.count else { break }
            let expected = promptWords[matched]
            if speechWord(spoken, matches: expected) {
                matched += 1
            } else if matched + 1 < promptWords.count, speechWord(spoken, matches: promptWords[matched + 1]) {
                matched += 2
            }
        }
        return min(matched, promptWords.count)
    }

    private func speechWord(_ spoken: String, matches expected: String) -> Bool {
        let spoken = spoken.speechAlias
        let expected = expected.speechAlias
        guard !spoken.isEmpty, !expected.isEmpty else { return false }
        if spoken == expected || spoken.hasPrefix(expected) || expected.hasPrefix(spoken) {
            return true
        }
        guard min(spoken.count, expected.count) >= 5 else { return false }
        return spoken.levenshteinDistance(to: expected) <= 1
    }

    private func scheduleVoicePromptFinish(expectedProgress: Int) {
        guard pendingVoiceFinishTask == nil else { return }
        pendingVoiceFinishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard isRecordingVoice, voicePromptWordProgress >= expectedProgress else {
                pendingVoiceFinishTask = nil
                return
            }
            pendingVoiceFinishTask = nil
            finishVoicePrompt()
        }
    }

    private func stopLiveVoiceCapture(cancelRecognition: Bool) {
        pendingVoiceFinishTask?.cancel()
        pendingVoiceFinishTask = nil
        if voiceTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            voiceTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        voiceAudioFile = nil
        voiceSignalActive = false
        voiceRecognitionAvailable = false
        voiceSignalStartedAt = nil
        voiceNoiseFloor = 0.025
        voiceActiveSpeechDuration = 0
        lastVoiceActivityTick = nil
        lastVoiceMeterUIUpdateAt = nil
        liveRecognitionRequest?.endAudio()
        liveRecognitionRequest = nil
        if cancelRecognition {
            liveRecognitionTask?.cancel()
        }
        liveRecognitionTask = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private enum VoiceRecordingError: Error {
        case failedToStart
    }

    func notebook(with id: SubjectNotebook.ID) -> SubjectNotebook? {
        notebooks.first { $0.id == id }
    }

    func page(with id: NotebookPage.ID) -> NotebookPage? {
        notebooks
            .lazy
            .flatMap(\.pages)
            .first { $0.id == id }
    }

    func notebookContaining(pageID: NotebookPage.ID) -> SubjectNotebook? {
        notebooks.first { notebook in
            notebook.pages.contains { $0.id == pageID }
        }
    }

    func pin(_ notebook: SubjectNotebook) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isPinned.toggle()
        persist()
    }

    func rename(_ notebook: SubjectNotebook, to name: String) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].subject = name.lowercased()
        persist()
    }

    func updateAvatar(_ avatar: AvatarProfile) {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            user.avatar = avatar
        }
        persist()
    }

    func randomizeAvatar() {
        let bases = ColorToken.allCases
        let symbols = [
            "book.closed.fill", "pencil.and.scribble", "sparkles", "brain.head.profile", "cube.transparent", "graduationcap.fill",
            "atom", "function", "paintpalette.fill", "lightbulb.fill", "waveform.path.ecg", "scope", "scribble.variable"
        ]
        let details = AvatarDetail.allCases
        updateAvatar(
            AvatarProfile(
                base: bases.randomElement() ?? .blue,
                accent: bases.randomElement() ?? .green,
                symbol: symbols.randomElement() ?? "book.closed.fill",
                detail: details.randomElement() ?? .spark
            )
        )
    }

    func move(_ notebook: SubjectNotebook, direction: MoveDirection) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        let target = direction == .earlier ? max(index - 1, 0) : min(index + 1, notebooks.count - 1)
        guard target != index else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            notebooks.swapAt(index, target)
        }
        persist()
    }

    func updatePageText(pageID: NotebookPage.ID, text: String) {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            notebooks[notebookIndex].pages[pageIndex].content.cleanedText = text.lowercased()
            notebooks[notebookIndex].lastActivity = "edited notes"
            persist()
            return
        }
    }

    func polishPageForStudy(pageID: NotebookPage.ID) {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            var content = notebooks[notebookIndex].pages[pageIndex].content
            let rebuilt = rebuiltStudySections(from: content)
            content.sections = rebuilt.sections
            content.cleanedText = rebuilt.text
            content.insight.onlyWhatMatters = rebuilt.focus
            content.insight.nextBestStep = "answer the first recall prompt, then grade it."
            content.insight.clarityScore = min(1, max(content.insight.clarityScore, content.insight.clarityScore + 0.12))
            content.insight.retentionRisk = max(0.04, content.insight.retentionRisk - 0.08)
            content.insight.handwriting = polishedHandwriting(content.insight.handwriting)
            content.insight.cleanupSuggestions = Array(Set(content.insight.cleanupSuggestions + ["page cleaned for study."]))
            if !content.insight.detectedFeatures.contains("cleaned") {
                content.insight.detectedFeatures.append("cleaned")
            }
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                notebooks[notebookIndex].pages[pageIndex].content = content
                notebooks[notebookIndex].lastActivity = "page cleaned"
                notebooks[notebookIndex].progress = min(1, notebooks[notebookIndex].progress + 0.04)
            }
            persist()
            return
        }
    }

    private func rebuiltStudySections(from content: ExtractedContent) -> (sections: [StudySection], text: String, focus: String) {
        let lines = content.cleanedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let focusLines = content.insight.onlyWhatMatters
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let focus = (focusLines.first ?? lines.first ?? "review the core idea on this page.").lowercased()
        var sections: [StudySection] = [
            StudySection(title: "only what matters", body: focus)
        ]

        let keyTerms = Array(content.keywords.prefix(8))
        if !keyTerms.isEmpty {
            sections.append(StudySection(title: "key terms", body: keyTerms.joined(separator: "\n")))
        }
        if !content.formulas.isEmpty {
            sections.append(StudySection(title: "formulas", body: content.formulas.prefix(6).joined(separator: "\n").lowercased()))
        }
        if let table = content.tables.first {
            let tableText = ([table.headers.joined(separator: "  ")] + table.rows.map { $0.joined(separator: "  ") })
                .joined(separator: "\n")
                .lowercased()
            sections.append(StudySection(title: table.title.lowercased(), body: tableText))
        }
        if let model = content.models.first {
            let nodes = (model.nodes ?? model.terms).prefix(8).joined(separator: "\n").lowercased()
            sections.append(StudySection(title: model.title.lowercased(), body: nodes.isEmpty ? model.summary.lowercased() : nodes))
        }

        let remaining = lines
            .filter { line in
                !sections.contains { section in
                    section.body.localizedCaseInsensitiveContains(line) || section.title.localizedCaseInsensitiveContains(line)
                }
            }
            .prefix(12)
            .joined(separator: "\n")
        if !remaining.isEmpty {
            sections.append(StudySection(title: "clean notes", body: remaining))
        }

        let text = sections.map { "\($0.title)\n\($0.body)" }.joined(separator: "\n\n")
        return (sections, text, focus)
    }

    private func polishedHandwriting(_ handwriting: HandwritingAnalysis) -> HandwritingAnalysis {
        var polished = handwriting
        polished.legibility = min(1, max(polished.legibility, polished.legibility + 0.1))
        polished.spacing = min(1, max(polished.spacing, polished.spacing + 0.08))
        polished.structure = min(1, max(polished.structure, polished.structure + 0.12))
        polished.coaching = "cleaned into a study-ready page. review the highlighted ideas before rewriting anything."
        if var signature = polished.signature {
            signature.correctionNeed = max(0.04, signature.correctionNeed - 0.24)
            signature.studyReadiness = min(1, signature.studyReadiness + 0.18)
            signature.nextStroke = "start recall"
            signature.predictedIssue = signature.studyReadiness > 0.72 ? "low risk" : signature.predictedIssue
            if !signature.strengths.contains("cleaned") {
                signature.strengths = Array((["cleaned"] + signature.strengths).prefix(4))
            }
            polished.signature = signature
        }
        return polished
    }

    @discardableResult
    func generateStudyModel(for pageID: NotebookPage.ID) -> DetectedModel? {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            let content = notebooks[notebookIndex].pages[pageIndex].content
            let generatedTitle = "\(notebooks[notebookIndex].pages[pageIndex].title) model"
            let model = pageStudyModel(content: content, pageTitle: notebooks[notebookIndex].pages[pageIndex].title)
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                if let existingIndex = notebooks[notebookIndex].pages[pageIndex].content.models.firstIndex(where: { existing in
                    existing.title == generatedTitle || existing.reconstruction?.source == "local page reconstruction"
                }) {
                    notebooks[notebookIndex].pages[pageIndex].content.models[existingIndex] = model
                } else {
                    notebooks[notebookIndex].pages[pageIndex].content.models.insert(model, at: 0)
                }
                notebooks[notebookIndex].pages[pageIndex].content.insight.detectedFeatures = Array(Set(notebooks[notebookIndex].pages[pageIndex].content.insight.detectedFeatures + ["models"]))
                notebooks[notebookIndex].pages[pageIndex].content.insight.nextBestStep = "study the generated model, then grade one flashcard."
                notebooks[notebookIndex].lastActivity = "model generated"
            }
            persist()
            return model
        }
        return nil
    }

    @discardableResult
    func preparePageForStudy(pageID: NotebookPage.ID) -> Bool {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            var page = notebooks[notebookIndex].pages[pageIndex]
            var content = page.content
            let rebuilt = rebuiltStudySections(from: content)
            content.sections = rebuilt.sections
            content.cleanedText = rebuilt.text
            content.insight.onlyWhatMatters = rebuilt.focus
            content.insight.nextBestStep = content.models.isEmpty
                ? "study the model, then answer one prompt."
                : "answer one prompt, then grade it."
            content.insight.clarityScore = min(1, max(content.insight.clarityScore, 0.74))
            content.insight.retentionRisk = max(0.05, content.insight.retentionRisk - 0.14)
            content.insight.cleanupSuggestions = Array(Set(content.insight.cleanupSuggestions + ["page prepared for review."]))
            for feature in ["prepared", "cleaned"] where !content.insight.detectedFeatures.contains(feature) {
                content.insight.detectedFeatures.append(feature)
            }
            if content.models.isEmpty || shouldAutoGenerateStudyModel(from: content) {
                let model = pageStudyModel(content: content, pageTitle: page.title)
                if let existingIndex = content.models.firstIndex(where: { $0.title == model.title || $0.reconstruction?.source == model.reconstruction?.source }) {
                    content.models[existingIndex] = model
                } else {
                    content.models.insert(model, at: 0)
                }
                if !content.insight.detectedFeatures.contains("models") {
                    content.insight.detectedFeatures.append("models")
                }
            }
            page.content = content
            page.studyState.lastReviewedAt = .now
            page.studyState.reviewCount += 1
            page.studyState.stability = min(1, page.studyState.stability + 0.12)
            page.studyState.difficulty = max(0.08, page.studyState.difficulty - 0.07)
            page.studyState.dueLabel = selectedStudyMode == .shortTerm ? "review tomorrow" : "review in 3 days"
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                notebooks[notebookIndex].pages[pageIndex] = page
                notebooks[notebookIndex].progress = min(1, notebooks[notebookIndex].progress + 0.06)
                notebooks[notebookIndex].lastActivity = "page prepared"
            }
            persist()
            return true
        }
        return false
    }

    private func pageStudyModel(content: ExtractedContent, pageTitle: String) -> DetectedModel {
        let tableNodes = content.tables.flatMap { table in
            [table.title] + table.headers + table.rows.flatMap { Array($0.prefix(2)) }
        }
        let relationshipNodes = relationshipAnchors(from: content.cleanedText)
        let terms = Array((relationshipNodes + content.keywords + content.formulas + tableNodes).filter { !$0.isEmpty }.prefix(8))
        let sectionTerms = content.sections.flatMap { section in
            [section.title] + section.body
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 4 }
        }
        let nodes = terms.isEmpty ? Array(sectionTerms.prefix(6)) : terms
        let finalNodes = nodes.isEmpty ? ["idea", "evidence", "example", "test", "memory"] : nodes
        let shape = content.tables.isEmpty ? inferredModelShape(from: content, nodeCount: finalNodes.count) : ModelShape.table
        let modelTitle = modelTitle(for: content, pageTitle: pageTitle)
        return DetectedModel(
            title: modelTitle,
            summary: content.tables.isEmpty
                ? "vellum rebuilt the page into a rotatable study object with labeled anchors, relationships, and depth."
                : "vellum rebuilt the table into a structured study object with row and column anchors.",
            terms: finalNodes,
            nodes: finalNodes,
            reconstruction: ModelReconstructionFactory.make(
                source: content.models.first?.reconstruction?.source ?? "local page reconstruction",
                confidence: max(0.58, min(0.96, content.insight.clarityScore + 0.22)),
                shape: shape,
                nodes: finalNodes,
                hint: shape == .table ? "tap each cell anchor to rebuild the table." : "rotate the object and explain each anchor aloud."
            )
        )
    }

    private func relationshipAnchors(from text: String) -> [String] {
        let structuralLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { line in
                line.contains("->")
                    || line.contains("→")
                    || line.contains(":")
                    || line.contains("=")
                    || line.contains("causes")
                    || line.contains("leads to")
                    || line.contains("becomes")
            }
        var anchors: [String] = []
        for line in structuralLines {
            let parts = line
                .replacingOccurrences(of: "leads to", with: " ")
                .replacingOccurrences(of: "causes", with: " ")
                .replacingOccurrences(of: "becomes", with: " ")
                .components(separatedBy: CharacterSet(charactersIn: "→->:=|,;()[]{}"))
                .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }
                .filter { $0.count > 2 && !["the", "and", "for", "with", "from", "this", "that"].contains($0) }
            anchors.append(contentsOf: parts)
        }
        var seen = Set<String>()
        return anchors.filter { seen.insert($0).inserted }.prefix(8).map(\.self)
    }

    private func modelTitle(for content: ExtractedContent, pageTitle: String) -> String {
        if let model = content.models.first, !model.title.isEmpty { return model.title.lowercased() }
        if let table = content.tables.first { return "\(table.title) model".lowercased() }
        if let section = content.sections.first, section.title != "notes" { return "\(section.title) model".lowercased() }
        return "\(pageTitle) model".lowercased()
    }

    private func shouldAutoGenerateStudyModel(from content: ExtractedContent) -> Bool {
        if !content.tables.isEmpty || !content.formulas.isEmpty { return true }
        if content.insight.handwriting.noteStyle == .diagram || content.insight.handwriting.noteStyle == .mixed { return true }
        let features = Set(content.insight.detectedFeatures)
        if !features.isDisjoint(with: ["sketch", "models", "tables", "formulas"]) { return true }
        let text = (content.cleanedText + " " + content.keywords.joined(separator: " ")).lowercased()
        return ["diagram", "model", "graph", "shape", "cycle", "structure", "system", "map"].contains(where: text.contains)
    }

    private func modelFeatureBoost(for content: ExtractedContent) -> Double {
        var score = 0.12
        if !content.models.isEmpty { score += 0.46 }
        if !content.tables.isEmpty { score += 0.28 }
        if !content.formulas.isEmpty { score += 0.2 }
        if content.insight.handwriting.noteStyle == .diagram { score += 0.26 }
        if content.insight.handwriting.noteStyle == .mixed { score += 0.32 }
        let features = Set(content.insight.detectedFeatures)
        if !features.isDisjoint(with: ["models", "sketch", "tables", "formulas"]) { score += 0.18 }
        if relationshipAnchors(from: content.cleanedText).count >= 3 { score += 0.18 }
        return min(1, score)
    }

    private func scannedContentWithAutomaticModel(_ content: ExtractedContent, title: String) -> ExtractedContent {
        guard content.models.isEmpty, shouldAutoGenerateStudyModel(from: content) else { return content }
        var enhanced = content
        let model = pageStudyModel(content: enhanced, pageTitle: title)
        enhanced.models.insert(model, at: 0)
        if !enhanced.insight.detectedFeatures.contains("models") {
            enhanced.insight.detectedFeatures.append("models")
        }
        enhanced.insight.nextBestStep = "rotate the generated model, then answer one prompt."
        return enhanced
    }

    private func inferredModelShape(from content: ExtractedContent, nodeCount: Int) -> ModelShape {
        let text = (content.cleanedText + " " + content.keywords.joined(separator: " ")).lowercased()
        if text.contains("cycle") || text.contains("loop") || text.contains("flow") { return .cycle }
        if text.contains("layer") || text.contains("stack") { return .stack }
        if nodeCount >= 5 || content.insight.handwriting.noteStyle == .diagram { return .mesh }
        return .orbit
    }

    func addTypedPage(to notebookID: SubjectNotebook.ID, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }

        let words = cleaned
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var seenWords = Set<String>()
        var keywords: [String] = []
        for word in words where word.count > 3 && keywords.count < 5 {
            if seenWords.insert(word).inserted {
                keywords.append(word)
            }
        }
        let content = ExtractedContent(
            cleanedText: cleaned,
            rawText: cleaned,
            keywords: keywords.isEmpty ? [notebooks[notebookIndex].subject] : keywords,
            formulas: words.filter { $0.contains("=") },
            sections: [StudySection(title: "notes", body: cleaned)],
            confidence: 1
        )
        let page = NotebookPage(
            title: "\(notebooks[notebookIndex].subject) notes",
            createdAt: .now,
            rawScanLabel: "typed page",
            content: content,
            studyState: ReviewState(dueLabel: "ready", stability: 0.46, difficulty: 0.4)
        )
        withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
            notebooks[notebookIndex].pages.insert(page, at: 0)
            notebooks[notebookIndex].lastActivity = "typed page added"
        }
        persist()
    }

    @MainActor
    func scanCapturedImage(_ image: UIImage, into notebookID: SubjectNotebook.ID) async {
        await scanCapturedImages([image], into: notebookID)
    }

    @MainActor
    func scanCapturedImages(_ images: [UIImage], into notebookID: SubjectNotebook.ID) async {
        guard let notebook = notebooks.first(where: { $0.id == notebookID }) else { return }
        guard !images.isEmpty else { return }
        scanPhase = .capturing
        activeScanJob = ScanJob(targetSubject: notebook.subject, phase: .capturing)
        await ScanLiveActivityCenter.shared.start(notebookID: notebook.id, subject: notebook.subject, pageCount: images.count)
        try? await Task.sleep(for: .milliseconds(180))

        scanPhase = .processing
        activeScanJob?.phase = .processing
        await ScanLiveActivityCenter.shared.update(phase: .processing, subject: notebook.subject, pageCount: images.count)
        var processedPages: [(ExtractedContent, String)] = []
        for image in images {
            let extracted = await scanProcessor.process(image: image)
            let classifiedSubject = await aiService.classify(extracted)
            processedPages.append((extracted, classifiedSubject))
        }

        scanPhase = .organizing
        activeScanJob?.phase = .organizing
        activeScanJob?.targetSubject = processedPages.last?.1 ?? notebook.subject
        await ScanLiveActivityCenter.shared.update(phase: .organizing, subject: activeScanJob?.targetSubject ?? notebook.subject, pageCount: images.count)
        try? await Task.sleep(for: .milliseconds(220))

        scanPhase = .sorted
        activeScanJob?.phase = .sorted
        await ScanLiveActivityCenter.shared.update(phase: .sorted, subject: activeScanJob?.targetSubject ?? notebook.subject, pageCount: images.count)
        var routeCounts: [String: Int] = [:]
        for (offset, page) in processedPages.enumerated().reversed() {
            let routedSubject = insertScannedPage(page.0, intoNotebookID: notebookID, classifiedSubject: page.1, pageNumber: offset + 1)
            routeCounts[routedSubject, default: 0] += 1
        }
        let routedSubject = routeCounts.max { $0.value < $1.value }?.key ?? activeScanJob?.targetSubject ?? notebook.subject
        activeScanJob?.targetSubject = routedSubject
        scanRouteNotice = ScanRouteNotice(fromSubject: notebook.subject, toSubject: routedSubject, pageCount: images.count)
        await ScanLiveActivityCenter.shared.end(subject: activeScanJob?.targetSubject ?? notebook.subject, pageCount: images.count)
        try? await Task.sleep(for: .milliseconds(760))
    }

    func resetScan() {
        let subject = activeScanJob?.targetSubject ?? "notes"
        Task { await ScanLiveActivityCenter.shared.end(phase: .framing, subject: subject, pageCount: 0) }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            scanPhase = .framing
            activeScanJob = nil
            scanRouteNotice = nil
        }
    }

    func flashcards(for page: NotebookPage) -> [Flashcard] {
        aiService.makeFlashcards(from: page.content)
    }

    func explain(_ term: String) -> String {
        aiService.explain(term)
    }

    func answer(_ question: String, for page: NotebookPage) -> String {
        aiService.answer(question, from: page.content)
    }

    func schedule(for card: Flashcard, mode: MemorizationMode) -> ReviewState {
        reviewService.schedule(card, mode: mode)
    }

    func reviewQueue(limit: Int = 5) -> [NotebookPage] {
        notebooks
            .flatMap(\.pages)
            .sorted { first, second in
                let firstScore = first.content.insight.retentionRisk + first.studyState.difficulty - first.studyState.stability * 0.35
                let secondScore = second.content.insight.retentionRisk + second.studyState.difficulty - second.studyState.stability * 0.35
                if firstScore == secondScore {
                    return first.createdAt > second.createdAt
                }
                return firstScore > secondScore
            }
            .prefix(limit)
            .map(\.self)
    }

    func modelReadiness(for page: NotebookPage) -> ModelReadiness {
        let content = page.content
        let hasModel = !content.models.isEmpty
        let signature = content.insight.handwriting.signature
        let featureBoost = modelFeatureBoost(for: content)
        let structure = content.insight.handwriting.structure
        let handwritingReady = signature?.studyReadiness ?? content.insight.clarityScore
        let score = max(
            hasModel ? 0.72 : 0,
            min(1, featureBoost + structure * 0.24 + handwritingReady * 0.18 + content.insight.clarityScore * 0.12)
        )
        let shape = content.models.first?.reconstruction?.shape ?? inferredModelShape(from: content, nodeCount: content.keywords.count + content.formulas.count)
        if hasModel {
            return ModelReadiness(
                score: max(score, content.models.first?.reconstruction?.confidence ?? 0.72),
                reason: shape.rawValue,
                action: "open model",
                symbol: shape.symbol,
                tint: .blue
            )
        }
        if !content.tables.isEmpty {
            return ModelReadiness(score: max(score, 0.78), reason: "table found", action: "build table", symbol: "tablecells", tint: .green)
        }
        if !content.formulas.isEmpty {
            return ModelReadiness(score: max(score, 0.7), reason: "formula found", action: "build formula", symbol: "function", tint: .amber)
        }
        if content.insight.handwriting.noteStyle == .diagram || content.insight.handwriting.noteStyle == .mixed {
            return ModelReadiness(score: max(score, 0.74), reason: "diagram found", action: "rebuild", symbol: "cube.transparent", tint: .blue)
        }
        if score > 0.5 {
            return ModelReadiness(score: score, reason: signature?.identity ?? "structure found", action: "make model", symbol: shape.symbol, tint: .plum)
        }
        return ModelReadiness(score: score, reason: "text page", action: "study text", symbol: "doc.text.magnifyingglass", tint: .graphite)
    }

    func modelForgePlan(for page: NotebookPage) -> ModelForgePlan {
        let content = page.content
        let readiness = modelReadiness(for: page)
        let handwriting = content.insight.handwriting
        let hasModel = !content.models.isEmpty
        let structureScore = max(handwriting.structure, content.insight.clarityScore)
        let visualScore = modelFeatureBoost(for: content)
        let objectScore = max(content.models.first?.reconstruction?.confidence ?? 0, readiness.score)
        let evidenceCount = content.tables.count + content.formulas.count + content.models.count + content.insight.detectedFeatures.count

        let steps = [
            ModelForgeStep(
                id: "ink",
                title: "ink",
                symbol: "text.viewfinder",
                tint: .blue,
                progress: max(content.confidence, handwriting.legibility),
                isComplete: content.confidence > 0.58 || handwriting.legibility > 0.58
            ),
            ModelForgeStep(
                id: "shape",
                title: "shape",
                symbol: readiness.symbol,
                tint: readiness.tint,
                progress: visualScore,
                isComplete: visualScore > 0.48 || !content.tables.isEmpty || !content.formulas.isEmpty
            ),
            ModelForgeStep(
                id: "links",
                title: "links",
                symbol: "point.3.connected.trianglepath.dotted",
                tint: .green,
                progress: min(1, structureScore + Double(relationshipAnchors(from: content.cleanedText).count) * 0.06),
                isComplete: structureScore > 0.52 || relationshipAnchors(from: content.cleanedText).count >= 3
            ),
            ModelForgeStep(
                id: "object",
                title: "object",
                symbol: hasModel ? "arkit" : "cube.transparent",
                tint: .plum,
                progress: objectScore,
                isComplete: hasModel
            )
        ]

        let stepScore = steps.reduce(0) { $0 + $1.progress } / Double(max(steps.count, 1))
        let score = min(1, max(readiness.score, stepScore + Double(min(evidenceCount, 6)) * 0.035))
        let title = hasModel ? "object ready" : (score > 0.52 ? "build object" : "map page")
        let detail: String
        if let model = content.models.first {
            detail = model.reconstruction?.shape.rawValue ?? model.title.lowercased()
        } else if !content.tables.isEmpty {
            detail = "table"
        } else if !content.formulas.isEmpty {
            detail = "formula"
        } else {
            detail = readiness.reason
        }

        return ModelForgePlan(
            score: score,
            title: title,
            detail: detail,
            symbol: hasModel ? "arkit" : readiness.symbol,
            tint: hasModel ? .plum : readiness.tint,
            isReady: hasModel,
            steps: steps
        )
    }

    func examPulse(for page: NotebookPage) -> ExamPulse {
        let content = page.content
        let modelPlan = modelForgePlan(for: page)
        let handwriting = content.insight.handwriting
        let weakInk = handwriting.signature?.correctionNeed ?? max(0, 1 - handwriting.legibility)
        let risk = min(1, content.insight.retentionRisk * 0.5 + page.studyState.difficulty * 0.24 + weakInk * 0.16 + (1 - content.insight.clarityScore) * 0.1)
        let firstRecall = content.insight.recallPrompts.first ?? content.insight.quickQuestions.first ?? "say the page from memory."
        var actions: [ExamPulseAction] = [
            ExamPulseAction(
                id: "recall",
                kind: .recall,
                title: "recall",
                detail: page.studyState.dueLabel,
                prompt: firstRecall,
                symbol: "brain.head.profile",
                tint: .plum,
                weight: max(0.42, risk)
            )
        ]

        if modelPlan.score > 0.38 {
            actions.append(ExamPulseAction(
                id: "model",
                kind: .model,
                title: modelPlan.isReady ? "object" : "build",
                detail: modelPlan.detail,
                prompt: content.models.first?.title ?? modelPlan.detail,
                symbol: modelPlan.symbol,
                tint: modelPlan.tint,
                weight: modelPlan.score
            ))
        }

        if let formula = content.formulas.first {
            actions.append(ExamPulseAction(
                id: "formula",
                kind: .formula,
                title: "formula",
                detail: formula,
                prompt: "make a new example using \(formula).",
                symbol: "function",
                tint: .amber,
                weight: min(1, 0.48 + Double(content.formulas.count) * 0.11)
            ))
        }

        if let table = content.tables.first {
            actions.append(ExamPulseAction(
                id: "table",
                kind: .table,
                title: "table",
                detail: table.title.lowercased(),
                prompt: "recreate \(table.title) without looking.",
                symbol: "tablecells",
                tint: .green,
                weight: min(1, 0.5 + Double(table.rows.count) * 0.05)
            ))
        }

        if let question = content.insight.quickQuestions.first {
            actions.append(ExamPulseAction(
                id: "ask",
                kind: .ask,
                title: "ask",
                detail: "explain",
                prompt: question,
                symbol: "text.bubble.fill",
                tint: .blue,
                weight: 0.5
            ))
        }

        actions.append(ExamPulseAction(
            id: "drill",
            kind: .drill,
            title: "drill",
            detail: "\(max(3, min(6, content.keywords.count + content.formulas.count + content.models.count)))",
            prompt: "start practice.",
            symbol: "target",
            tint: .green,
            weight: min(1, 0.42 + risk * 0.42)
        ))

        let ranked = actions
            .sorted { $0.weight > $1.weight }
            .prefix(5)
            .map(\.self)
        let leading = ranked.first
        let title: String
        if risk > 0.62 {
            title = "high yield"
        } else if modelPlan.isReady {
            title = "object first"
        } else if !content.formulas.isEmpty {
            title = "formula first"
        } else {
            title = "test ready"
        }

        return ExamPulse(
            score: max(risk, leading?.weight ?? 0.4),
            title: title,
            prompt: leading?.prompt ?? firstRecall,
            symbol: leading?.symbol ?? "target",
            tint: leading?.tint ?? .plum,
            actions: ranked
        )
    }

    func forgettingForecast(for page: NotebookPage) -> ForgettingForecast {
        let content = page.content
        let modelPlan = modelForgePlan(for: page)
        let signature = content.insight.handwriting.signature
        let inkRisk = signature?.correctionNeed ?? max(0, 1 - content.insight.handwriting.legibility)
        let baseRisk = min(1, content.insight.retentionRisk * 0.46 + page.studyState.difficulty * 0.28 + inkRisk * 0.16 + max(0, 1 - page.studyState.stability) * 0.1)
        let recallPrompt = content.insight.recallPrompts.first ?? content.insight.quickQuestions.first ?? content.insight.onlyWhatMatters
        var points: [ForgettingForecastPoint] = [
            ForgettingForecastPoint(
                id: "now",
                title: "now",
                detail: page.studyState.dueLabel,
                prompt: recallPrompt.isEmpty ? "say the page from memory." : recallPrompt,
                symbol: "brain.head.profile",
                tint: .plum,
                weight: max(0.36, baseRisk),
                action: .recall
            )
        ]

        if modelPlan.score > 0.4 {
            points.append(ForgettingForecastPoint(
                id: "object",
                title: "object",
                detail: modelPlan.detail,
                prompt: content.models.first?.title ?? modelPlan.detail,
                symbol: modelPlan.symbol,
                tint: modelPlan.tint,
                weight: modelPlan.isReady ? max(0.62, modelPlan.score) : modelPlan.score,
                action: .model
            ))
        }

        if let formula = content.formulas.first {
            points.append(ForgettingForecastPoint(
                id: "formula",
                title: "formula",
                detail: formula,
                prompt: "make a new example using \(formula).",
                symbol: "function",
                tint: .amber,
                weight: min(1, 0.48 + Double(content.formulas.count) * 0.12 + baseRisk * 0.18),
                action: .formula
            ))
        }

        if let table = content.tables.first {
            points.append(ForgettingForecastPoint(
                id: "table",
                title: "table",
                detail: table.title.lowercased(),
                prompt: "recreate \(table.title) without looking.",
                symbol: "tablecells",
                tint: .green,
                weight: min(1, 0.46 + Double(table.headers.count + table.rows.count) * 0.04),
                action: .table
            ))
        }

        if let alert = content.insight.confusionAlerts.first ?? content.insight.cleanupSuggestions.first {
            points.append(ForgettingForecastPoint(
                id: "weak",
                title: "weak",
                detail: signature?.predictedIssue ?? "check",
                prompt: alert,
                symbol: "exclamationmark.triangle.fill",
                tint: .amber,
                weight: min(1, 0.44 + inkRisk * 0.36 + content.insight.retentionRisk * 0.2),
                action: .ask
            ))
        }

        points.append(ForgettingForecastPoint(
            id: "drill",
            title: "drill",
            detail: "\(max(3, min(6, content.keywords.count + content.formulas.count + content.models.count)))",
            prompt: "start practice.",
            symbol: "target",
            tint: .green,
            weight: min(1, 0.36 + baseRisk * 0.5),
            action: .drill
        ))

        var seen = Set<String>()
        let ranked = points
            .sorted { $0.weight > $1.weight }
            .filter { seen.insert($0.id).inserted }
            .prefix(5)
            .map(\.self)
        let score = ranked.isEmpty ? baseRisk : ranked.reduce(0) { $0 + $1.weight } / Double(ranked.count)
        let title: String
        if score > 0.68 {
            title = "fragile"
        } else if score > 0.44 {
            title = "steady"
        } else {
            title = "sharp"
        }
        return ForgettingForecast(score: min(1, max(baseRisk, score)), title: title, points: ranked)
    }

    func bestModelPage(in notebookID: SubjectNotebook.ID? = nil) -> NotebookPage? {
        let pages = notebooks
            .filter { notebookID == nil || $0.id == notebookID }
            .flatMap(\.pages)
        return pages.max { first, second in
            modelReadiness(for: first).score < modelReadiness(for: second).score
        }
    }

    func studyAutopilot(in notebookID: SubjectNotebook.ID? = nil) -> StudyAutopilotPlan {
        let scopedNotebooks = notebooks.filter { notebookID == nil || $0.id == notebookID }
        guard !scopedNotebooks.isEmpty else {
            return StudyAutopilotPlan(
                kind: .add,
                pageID: nil,
                notebookID: nil,
                title: "add",
                detail: "course",
                symbol: "plus",
                tint: .amber,
                score: 0.12,
                steps: [
                    StudyAutopilotStep(title: "course", symbol: "book.closed.fill", done: false),
                    StudyAutopilotStep(title: "scan", symbol: "viewfinder", done: false)
                ]
            )
        }
        if let emptyNotebook = scopedNotebooks.first(where: { $0.pages.isEmpty }) {
            return StudyAutopilotPlan(
                kind: .scan,
                pageID: nil,
                notebookID: emptyNotebook.id,
                title: "scan",
                detail: emptyNotebook.subject,
                symbol: "viewfinder",
                tint: emptyNotebook.accent,
                score: 0.22,
                steps: [
                    StudyAutopilotStep(title: "capture", symbol: "viewfinder", done: false),
                    StudyAutopilotStep(title: "sort", symbol: "sparkle.magnifyingglass", done: false),
                    StudyAutopilotStep(title: "study", symbol: "brain.head.profile", done: false)
                ]
            )
        }

        let pages = scopedNotebooks.flatMap(\.pages)
        if let correctionPage = pages.max(by: { first, second in
            (first.content.insight.handwriting.signature?.correctionNeed ?? 0) < (second.content.insight.handwriting.signature?.correctionNeed ?? 0)
        }),
           let signature = correctionPage.content.insight.handwriting.signature,
           signature.correctionNeed > 0.42 {
            return StudyAutopilotPlan(
                kind: .clean,
                pageID: correctionPage.id,
                notebookID: notebookContaining(pageID: correctionPage.id)?.id,
                title: "clean",
                detail: signature.nextStroke,
                symbol: "wand.and.rays",
                tint: .amber,
                score: signature.correctionNeed,
                steps: [
                    StudyAutopilotStep(title: "ink", symbol: "pencil.and.scribble", done: true),
                    StudyAutopilotStep(title: "clean", symbol: "wand.and.rays", done: false),
                    StudyAutopilotStep(title: "recall", symbol: "brain.head.profile", done: false)
                ]
            )
        }

        if let page = bestModelPage(in: notebookID) {
            let readiness = modelReadiness(for: page)
            if readiness.score > 0.54, readiness.action != "study text" {
                return StudyAutopilotPlan(
                    kind: .model,
                    pageID: page.id,
                    notebookID: notebookContaining(pageID: page.id)?.id,
                    title: readiness.action,
                    detail: readiness.reason,
                    symbol: readiness.symbol,
                    tint: readiness.tint,
                    score: readiness.score,
                    steps: [
                        StudyAutopilotStep(title: "scan", symbol: "doc.text.magnifyingglass", done: true),
                        StudyAutopilotStep(title: "model", symbol: readiness.symbol, done: !page.content.models.isEmpty),
                        StudyAutopilotStep(title: "drill", symbol: "scope", done: false)
                    ]
                )
            }
        }

        if let page = reviewQueue(limit: 1).first {
            return StudyAutopilotPlan(
                kind: .review,
                pageID: page.id,
                notebookID: notebookContaining(pageID: page.id)?.id,
                title: "review",
                detail: page.studyState.dueLabel,
                symbol: "brain.head.profile",
                tint: .plum,
                score: min(1, page.content.insight.retentionRisk + page.studyState.difficulty * 0.4),
                steps: [
                    StudyAutopilotStep(title: "recall", symbol: "brain.head.profile", done: false),
                    StudyAutopilotStep(title: "grade", symbol: "checkmark", done: false),
                    StudyAutopilotStep(title: "schedule", symbol: "calendar", done: false)
                ]
            )
        }

        let fallbackNotebook = scopedNotebooks.first
        return StudyAutopilotPlan(
            kind: .study,
            pageID: pages.first?.id,
            notebookID: fallbackNotebook?.id,
            title: "study",
            detail: fallbackNotebook?.subject ?? "notes",
            symbol: "book.pages.fill",
            tint: fallbackNotebook?.accent ?? .graphite,
            score: 0.34,
            steps: [
                StudyAutopilotStep(title: "open", symbol: "book.pages.fill", done: false),
                StudyAutopilotStep(title: "ask", symbol: "text.bubble.fill", done: false)
            ]
        )
    }

    func dailyBrief(in notebookID: SubjectNotebook.ID? = nil) -> StudyDailyBrief {
        let scopedNotebooks = notebooks.filter { notebookID == nil || $0.id == notebookID }
        let pages = scopedNotebooks.flatMap(\.pages)
        var items: [StudyBriefItem] = []

        if let emptyNotebook = scopedNotebooks.first(where: { $0.pages.isEmpty }) {
            items.append(StudyBriefItem(
                kind: .scan,
                pageID: nil,
                notebookID: emptyNotebook.id,
                title: "scan",
                value: emptyNotebook.subject,
                symbol: "viewfinder",
                tint: emptyNotebook.accent,
                score: 0.22
            ))
        }

        if let review = reviewQueue(limit: 1).first {
            items.append(StudyBriefItem(
                kind: .review,
                pageID: review.id,
                notebookID: notebookContaining(pageID: review.id)?.id,
                title: "review",
                value: review.studyState.dueLabel,
                symbol: "brain.head.profile",
                tint: .plum,
                score: min(1, review.content.insight.retentionRisk + review.studyState.difficulty * 0.36)
            ))
        }

        if let weakInk = pages.max(by: { first, second in
            (first.content.insight.handwriting.signature?.correctionNeed ?? 0) < (second.content.insight.handwriting.signature?.correctionNeed ?? 0)
        }),
           let signature = weakInk.content.insight.handwriting.signature,
           signature.correctionNeed > 0.34 {
            items.append(StudyBriefItem(
                kind: .clean,
                pageID: weakInk.id,
                notebookID: notebookContaining(pageID: weakInk.id)?.id,
                title: "ink",
                value: signature.identity,
                symbol: "pencil.and.scribble",
                tint: .amber,
                score: signature.correctionNeed
            ))
        }

        if let page = bestModelPage(in: notebookID) {
            let readiness = modelReadiness(for: page)
            if readiness.score > 0.42 {
                items.append(StudyBriefItem(
                    kind: .model,
                    pageID: page.id,
                    notebookID: notebookContaining(pageID: page.id)?.id,
                    title: "model",
                    value: readiness.reason,
                    symbol: readiness.symbol,
                    tint: readiness.tint,
                    score: readiness.score
                ))
            }
        }

        let keywordCount = Set(pages.flatMap(\.content.keywords)).count
        if keywordCount > 0 {
            items.append(StudyBriefItem(
                kind: .search,
                pageID: pages.first?.id,
                notebookID: notebookID,
                title: "terms",
                value: "\(keywordCount)",
                symbol: "magnifyingglass",
                tint: .green,
                score: min(1, Double(keywordCount) / 28.0)
            ))
        }

        var seen = Set<StudyBriefKind>()
        let filtered = items
            .sorted { $0.score > $1.score }
            .filter { seen.insert($0.kind).inserted }
            .prefix(4)
            .map(\.self)
        let average = filtered.isEmpty ? 0 : filtered.reduce(0) { $0 + $1.score } / Double(filtered.count)
        let title: String
        if filtered.contains(where: { $0.kind == .scan }) {
            title = "capture"
        } else if filtered.contains(where: { $0.kind == .clean }) {
            title = "clean"
        } else if filtered.contains(where: { $0.kind == .model }) {
            title = "rebuild"
        } else if filtered.contains(where: { $0.kind == .review }) {
            title = "review"
        } else {
            title = "steady"
        }
        return StudyDailyBrief(score: average, title: title, items: filtered)
    }

    func memoryMap(in notebookID: SubjectNotebook.ID? = nil) -> StudyMemoryMap {
        let scopedNotebooks = notebooks.filter { notebookID == nil || $0.id == notebookID }
        let pages = scopedNotebooks.flatMap(\.pages)
        guard !scopedNotebooks.isEmpty else { return .empty }

        var nodes: [StudyMemoryNode] = scopedNotebooks.prefix(2).map { notebook in
            StudyMemoryNode(
                id: "notebook-\(notebook.id.uuidString)",
                kind: .notebook,
                pageID: notebook.pages.first?.id,
                notebookID: notebook.id,
                title: notebook.subject.lowercased(),
                detail: notebook.pages.isEmpty ? "scan" : "\(notebook.pages.count) pages",
                symbol: "book.closed.fill",
                tint: notebook.accent,
                weight: max(0.24, min(1, notebook.progress + Double(notebook.pages.count) * 0.08))
            )
        }

        if let review = reviewQueue(limit: 1).first,
           notebookID == nil || notebookContaining(pageID: review.id)?.id == notebookID {
            nodes.append(StudyMemoryNode(
                id: "review-\(review.id.uuidString)",
                kind: .review,
                pageID: review.id,
                notebookID: notebookContaining(pageID: review.id)?.id,
                title: "review",
                detail: review.studyState.dueLabel,
                symbol: "brain.head.profile",
                tint: .plum,
                weight: min(1, 0.28 + review.content.insight.retentionRisk + review.studyState.difficulty * 0.28)
            ))
        }

        if let page = bestModelPage(in: notebookID) {
            let readiness = modelReadiness(for: page)
            if readiness.score > 0.35 {
                nodes.append(StudyMemoryNode(
                    id: "model-\(page.id.uuidString)",
                    kind: .model,
                    pageID: page.id,
                    notebookID: notebookContaining(pageID: page.id)?.id,
                    title: readiness.action,
                    detail: readiness.reason,
                    symbol: readiness.symbol,
                    tint: readiness.tint,
                    weight: readiness.score
                ))
            }
        }

        if let formulaPage = pages.first(where: { !$0.content.formulas.isEmpty }),
           let formula = formulaPage.content.formulas.first {
            nodes.append(StudyMemoryNode(
                id: "formula-\(formulaPage.id.uuidString)",
                kind: .formula,
                pageID: formulaPage.id,
                notebookID: notebookContaining(pageID: formulaPage.id)?.id,
                title: "formula",
                detail: formula.lowercased(),
                symbol: "function",
                tint: .amber,
                weight: min(1, 0.48 + Double(formulaPage.content.formulas.count) * 0.12)
            ))
        }

        if let tablePage = pages.first(where: { !$0.content.tables.isEmpty }),
           let table = tablePage.content.tables.first {
            nodes.append(StudyMemoryNode(
                id: "table-\(tablePage.id.uuidString)",
                kind: .table,
                pageID: tablePage.id,
                notebookID: notebookContaining(pageID: tablePage.id)?.id,
                title: "table",
                detail: table.title.lowercased(),
                symbol: "tablecells",
                tint: .green,
                weight: min(1, 0.46 + Double(table.rows.count) * 0.05)
            ))
        }

        let keywordNodes = strongestKeywords(from: pages).prefix(max(0, 6 - nodes.count)).map { entry in
            StudyMemoryNode(
                id: "keyword-\(entry.word)",
                kind: .keyword,
                pageID: entry.pageID,
                notebookID: entry.notebookID,
                title: entry.word,
                detail: "\(entry.count)",
                symbol: "sparkle.magnifyingglass",
                tint: entry.tint,
                weight: min(1, 0.28 + Double(entry.count) * 0.12)
            )
        }
        nodes.append(contentsOf: keywordNodes)

        let ranked = nodes
            .sorted { $0.weight > $1.weight }
            .prefix(6)
            .map(\.self)
        let score = ranked.isEmpty ? 0 : ranked.reduce(0) { $0 + $1.weight } / Double(ranked.count)
        return StudyMemoryMap(score: min(1, score), nodes: ranked)
    }

    private func strongestKeywords(from pages: [NotebookPage]) -> [(word: String, count: Int, pageID: NotebookPage.ID?, notebookID: SubjectNotebook.ID?, tint: ColorToken)] {
        var counts: [String: (count: Int, pageID: NotebookPage.ID?, notebookID: SubjectNotebook.ID?, tint: ColorToken)] = [:]
        let blocked: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "notes", "page", "study"]

        for page in pages {
            let notebook = notebookContaining(pageID: page.id)
            let words = page.content.keywords + page.content.sections.flatMap { section in
                (section.title + " " + section.body)
                    .lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
            }
            for rawWord in words {
                let word = rawWord
                    .lowercased()
                    .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                guard word.count > 3, !blocked.contains(word), word.rangeOfCharacter(from: .letters) != nil else { continue }
                let current = counts[word] ?? (0, page.id, notebook?.id, notebook?.accent ?? .graphite)
                counts[word] = (current.count + 1, current.pageID, current.notebookID, current.tint)
            }
        }

        return counts
            .map { key, value in
                (word: key, count: value.count, pageID: value.pageID, notebookID: value.notebookID, tint: value.tint)
            }
            .sorted {
                if $0.count == $1.count { return $0.word < $1.word }
                return $0.count > $1.count
            }
    }

    func recordReview(pageID: NotebookPage.ID, grade: ReviewGrade) {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            var state = notebooks[notebookIndex].pages[pageIndex].studyState
            state.reviewCount += 1
            state.lastReviewedAt = .now
            switch grade {
            case .forgot:
                state.lapses += 1
                state.stability = max(0.12, state.stability * 0.62)
                state.difficulty = min(1, state.difficulty + 0.18)
                state.dueLabel = "review in 10 min"
            case .hard:
                state.stability = max(0.18, state.stability * 0.88)
                state.difficulty = min(1, state.difficulty + 0.08)
                state.dueLabel = "review tonight"
            case .good:
                state.stability = min(1, state.stability + 0.16)
                state.difficulty = max(0.12, state.difficulty - 0.08)
                state.dueLabel = selectedStudyMode == .shortTerm ? "review tomorrow" : "review in 3 days"
            case .easy:
                state.stability = min(1, state.stability + 0.26)
                state.difficulty = max(0.08, state.difficulty - 0.14)
                state.dueLabel = selectedStudyMode == .shortTerm ? "review in 2 days" : "review next week"
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                notebooks[notebookIndex].pages[pageIndex].studyState = state
                notebooks[notebookIndex].progress = min(1, max(0, notebooks[notebookIndex].progress + (grade == .forgot ? -0.02 : 0.04)))
                notebooks[notebookIndex].lastActivity = "reviewed \(grade.rawValue)"
            }
            persist()
            return
        }
    }

    func readAloud(_ page: NotebookPage, style: PlaybackStyle) async -> VoicePlayback {
        await voiceService.makePlayback(page.content.cleanedText, style: style, profile: voiceProfile)
    }

    private func insertScannedPage(_ content: ExtractedContent, into subject: String) -> String {
        guard let index = notebooks.firstIndex(where: { $0.subject == subject }) else { return subject }
        insertScannedPage(content, at: index)
        return notebooks[index].subject
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID) -> String {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return "notes" }
        insertScannedPage(content, at: index)
        return notebooks[index].subject
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID, classifiedSubject: String) -> String {
        insertScannedPage(content, intoNotebookID: notebookID, classifiedSubject: classifiedSubject, pageNumber: nil)
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID, classifiedSubject: String, pageNumber: Int?) -> String {
        guard let fallbackIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else { return "notes" }
        let index = destinationNotebookIndex(for: classifiedSubject, fallbackIndex: fallbackIndex)
        let destinationSubject = notebooks[index].subject
        let suffix = pageNumber.map { " page \($0)" } ?? ""
        insertScannedPage(content, at: index, title: "\(destinationSubject)\(suffix)")
        if index != fallbackIndex {
            notebooks[fallbackIndex].lastActivity = "sent to \(destinationSubject)"
        }
        return destinationSubject
    }

    private func insertScannedPage(_ content: ExtractedContent, at index: Int, title: String = "scanned notes") {
        let enhancedContent = scannedContentWithAutomaticModel(content, title: title)
        let page = NotebookPage(
            title: title,
            createdAt: .now,
            rawScanLabel: "captured page",
            content: enhancedContent,
            studyState: ReviewState(dueLabel: "due tonight", stability: 0.62, difficulty: 0.38)
        )
        withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) {
            notebooks[index].pages.insert(page, at: 0)
            notebooks[index].lastActivity = "new scan sorted"
            notebooks[index].progress = min(notebooks[index].progress + 0.08, 1)
        }
        persist()
    }

    private func destinationNotebookIndex(for classifiedSubject: String, fallbackIndex: Int) -> Int {
        let subject = canonicalSubject(classifiedSubject)
        if let exactIndex = notebooks.firstIndex(where: { canonicalSubject($0.subject) == subject }) {
            return exactIndex
        }
        guard shouldCreateSubjectNotebook(subject) else {
            return fallbackIndex
        }
        notebooks.append(
            SubjectNotebook(
                subject: subject,
                pages: [],
                progress: 0,
                lastActivity: "created by scan",
                isPinned: notebooks.isEmpty,
                accent: ColorToken.allCases[notebooks.count % ColorToken.allCases.count]
            )
        )
        if !onboardingSubjects.contains(subject) {
            onboardingSubjects.append(subject)
        }
        return notebooks.count - 1
    }

    private func canonicalSubject(_ subject: String) -> String {
        let cleaned = subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["mathematics", "algebra", "geometry", "calculus", "equation", "function"].contains(cleaned) { return "math" }
        if ["biology", "chemistry", "physics", "experiment", "science", "cell", "atom"].contains(cleaned) { return "science" }
        if ["literature", "writing", "english", "essay", "poem", "novel"].contains(cleaned) { return "english" }
        if ["government", "civics", "history", "war", "revolution", "empire"].contains(cleaned) { return "history" }
        if ["computer science", "computers", "algorithm", "code", "programming"].contains(cleaned) { return "computer science" }
        return cleaned.isEmpty ? "notes" : cleaned
    }

    private func shouldCreateSubjectNotebook(_ subject: String) -> Bool {
        [
            "math", "science", "english", "history", "computer science",
            "biology", "chemistry", "physics", "literature", "government"
        ].contains(subject)
    }

    private func persist() {
        persistence.save(PersistedNotebookState(
            user: user,
            notebooks: notebooks,
            authSession: authSession,
            hasCompletedOnboarding: hasCompletedOnboarding,
            setupStep: setupStep,
            appTheme: appTheme,
            selectedStudyMode: selectedStudyMode,
            voiceProfile: voiceProfile,
            onboardingSubjects: onboardingSubjects
        ))
    }

    private func voiceSamplesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("vellum-voice-samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func transcribeVoiceSample(at url: URL) async -> String {
        guard await requestSpeechPermission() else {
            authMessage = "speech recognition access is needed to transcribe voice."
            return ""
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            authMessage = "speech recognition is not available right now."
            return ""
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal, !didResume {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString.lowercased())
                } else if error != nil, !didResume {
                    didResume = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func normalizedVoiceLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        return max(0, min(1, Double(rms) * 18))
    }
}

private extension String {
    var normalizedSpeechWords: [String] {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var speechAlias: String {
        switch self {
        case "eye": "i"
        case "ill", "i'll": "will"
        case "im", "i'm": "i"
        case "calmly": "calm"
        case "patients": "patient"
        case "matter": "matters"
        default: self
        }
    }

    func levenshteinDistance(to other: String) -> Int {
        let source = Array(self)
        let target = Array(other)
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }

        var previous = Array(0...target.count)
        var current = Array(repeating: 0, count: target.count + 1)

        for sourceIndex in 1...source.count {
            current[0] = sourceIndex
            for targetIndex in 1...target.count {
                let substitution = previous[targetIndex - 1] + (source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1)
                current[targetIndex] = Swift.min(
                    previous[targetIndex] + 1,
                    current[targetIndex - 1] + 1,
                    substitution
                )
            }
            swap(&previous, &current)
        }

        return previous[target.count]
    }
}

enum MoveDirection {
    case earlier
    case later
}
