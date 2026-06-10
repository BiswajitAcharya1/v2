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
        guard await requestMicrophonePermission() else {
            authMessage = "microphone access is needed to record voice."
            return
        }
        let speechAllowed = await requestSpeechPermission()
        let recognizer = speechAllowed ? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) : nil
        let session = AVAudioSession.sharedInstance()
        let fileName = "margins-voice-\(UUID().uuidString).caf"
        let url = voiceSamplesDirectory().appendingPathComponent(fileName)

        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
            var recognitionTask: SFSpeechRecognitionTask?
            if let recognizer, recognizer.isAvailable {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.addsPunctuation = false
                request.taskHint = .dictation
                request.contextualStrings = prompt.normalizedSpeechWords + ["margins", "study", "tutor", "remember"]
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

            liveRecognitionRequest = recognitionRequest
            liveRecognitionTask = recognitionTask
            audioEngine = engine
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
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        voiceAudioFile = nil
        voiceSignalActive = false
        voiceRecognitionAvailable = false
        voiceSignalStartedAt = nil
        voiceNoiseFloor = 0.025
        voiceActiveSpeechDuration = 0
        lastVoiceActivityTick = nil
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
        for (offset, page) in processedPages.enumerated().reversed() {
            insertScannedPage(page.0, intoNotebookID: notebookID, classifiedSubject: page.1, pageNumber: offset + 1)
        }
        await ScanLiveActivityCenter.shared.end(subject: activeScanJob?.targetSubject ?? notebook.subject, pageCount: images.count)
        try? await Task.sleep(for: .milliseconds(760))
    }

    func resetScan() {
        let subject = activeScanJob?.targetSubject ?? "notes"
        Task { await ScanLiveActivityCenter.shared.end(phase: .framing, subject: subject, pageCount: 0) }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            scanPhase = .framing
            activeScanJob = nil
        }
    }

    func flashcards(for page: NotebookPage) -> [Flashcard] {
        aiService.makeFlashcards(from: page.content)
    }

    func explain(_ term: String) -> String {
        aiService.explain(term)
    }

    func schedule(for card: Flashcard, mode: MemorizationMode) -> ReviewState {
        reviewService.schedule(card, mode: mode)
    }

    func readAloud(_ page: NotebookPage, style: PlaybackStyle) async -> VoicePlayback {
        await voiceService.makePlayback(page.content.cleanedText, style: style, profile: voiceProfile)
    }

    private func insertScannedPage(_ content: ExtractedContent, into subject: String) {
        guard let index = notebooks.firstIndex(where: { $0.subject == subject }) else { return }
        insertScannedPage(content, at: index)
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        insertScannedPage(content, at: index)
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID, classifiedSubject: String) {
        insertScannedPage(content, intoNotebookID: notebookID, classifiedSubject: classifiedSubject, pageNumber: nil)
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID, classifiedSubject: String, pageNumber: Int?) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        let suffix = pageNumber.map { " page \($0)" } ?? ""
        insertScannedPage(content, at: index, title: "\(classifiedSubject)\(suffix)")
    }

    private func insertScannedPage(_ content: ExtractedContent, at index: Int, title: String = "scanned notes") {
        let page = NotebookPage(
            title: title,
            createdAt: .now,
            rawScanLabel: "captured page",
            content: content,
            studyState: ReviewState(dueLabel: "due tonight", stability: 0.62, difficulty: 0.38)
        )
        withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) {
            notebooks[index].pages.insert(page, at: 0)
            notebooks[index].lastActivity = "new scan sorted"
            notebooks[index].progress = min(notebooks[index].progress + 0.08, 1)
        }
        persist()
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
        let directory = base.appendingPathComponent("margins-voice-samples", isDirectory: true)
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
