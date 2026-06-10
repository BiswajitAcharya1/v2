import Foundation
import Observation
import SwiftUI
import AVFoundation

@MainActor
@Observable
final class NotebookStore {
    var user = NotebookUser(name: "maya", gradeLevel: "11")
    var notebooks: [SubjectNotebook] = NotebookFixtures.notebooks
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
    var gemmaVoiceModeEnabled = false
    var latestVoiceQuestion: String?
    var onboardingSubjects: [String] = ["math", "science", "history", "english"]
    var isRecordingVoice = false
    var isVoicePaused = false
    var voiceRecordingElapsed: TimeInterval = 0
    var voiceRecordingLevel: Double = 0

    private let authService: LocalAuthServing = LocalAuthService()
    private let scanProcessor: ScanProcessingServing = LocalScanProcessingService()
    private let aiService: NoteUnderstandingServing = LocalNoteUnderstandingService()
    private let reviewService: SpacedRepetitionServing = LocalSpacedRepetitionService()
    private let voiceService: VoiceServing = MossTTSVoiceService()
    @ObservationIgnored private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var recordingPrompt: String?
    @ObservationIgnored private var voiceMeterTask: Task<Void, Never>?

    var pinnedNotebooks: [SubjectNotebook] {
        notebooks.filter(\.isPinned)
    }

    var preferredColorScheme: ColorScheme? {
        .light
    }

    func signIn(provider: AuthProvider) async {
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

    func finishOnboarding() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            hasCompletedOnboarding = true
            setupStep = .voiceRecording
        }
    }

    func choosePersonalVoice(_ wantsPersonalVoice: Bool) {
        voiceProfile.wantsPersonalVoice = wantsPersonalVoice
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            setupStep = wantsPersonalVoice ? .voiceRecording : .subjects
        }
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
        audioRecorder?.pause()
        isVoicePaused = true
    }

    func resumeVoiceRecording() {
        guard isRecordingVoice, isVoicePaused else { return }
        audioRecorder?.record()
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
        voiceMeterTask?.cancel()
        voiceMeterTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        recordingURL = nil
        recordingPrompt = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            setupStep = .subjects
        }
    }

    func retakeVoicePrompt() {
        guard !voiceProfile.samples.isEmpty else { return }
        voiceProfile.samples.removeLast()
        voiceProfile.isPersonalized = false
    }

    func chooseTheme(_ theme: AppTheme) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            appTheme = theme
        }
    }

    func continueToSubjects() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            setupStep = .subjects
        }
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

    private func completeAuth(_ session: AuthSession) {
        authSession = session
        authMessage = "\(session.provider.rawValue) ready"
        user.name = session.username.lowercased()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            isAuthenticated = true
            hasCompletedOnboarding = false
            setupStep = .voiceRecording
        }
    }

    private func startVoicePrompt(_ prompt: String) async {
        guard await requestMicrophonePermission() else {
            authMessage = "microphone access is needed to record voice."
            return
        }
        let session = AVAudioSession.sharedInstance()
        let fileName = "notebook-voice-\(UUID().uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            recordingURL = url
            recordingPrompt = prompt
            voiceProfile.wantsPersonalVoice = true
            isRecordingVoice = true
            isVoicePaused = false
            voiceRecordingElapsed = 0
            voiceRecordingLevel = 0
            beginVoiceMetering()
        } catch {
            audioRecorder?.stop()
            audioRecorder = nil
            recordingURL = nil
            recordingPrompt = nil
            isVoicePaused = false
            voiceRecordingElapsed = 0
            voiceRecordingLevel = 0
            voiceMeterTask?.cancel()
            voiceMeterTask = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            authMessage = "voice recording could not start."
        }
    }

    private func finishVoicePrompt() {
        guard let url = recordingURL else { return }
        voiceMeterTask?.cancel()
        voiceMeterTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecordingVoice = false
        isVoicePaused = false

        let prompt = recordingPrompt ?? ""
        let duration = voiceRecordingElapsed
        voiceRecordingElapsed = 0
        voiceRecordingLevel = 0
        recordingURL = nil
        recordingPrompt = nil
        voiceProfile.samples.append(VoiceSample(prompt: prompt, isRecorded: true, audioURL: url, duration: duration))
        voiceProfile.isPersonalized = voiceProfile.samples.count == 3
        if voiceProfile.isPersonalized {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                setupStep = .subjects
            }
        }
    }

    private func beginVoiceMetering() {
        voiceMeterTask?.cancel()
        voiceMeterTask = Task { @MainActor in
            while !Task.isCancelled {
                if let recorder = audioRecorder {
                    recorder.updateMeters()
                    voiceRecordingElapsed = recorder.currentTime
                    let power = recorder.averagePower(forChannel: 0)
                    let normalized = max(0, min(1, (Double(power) + 55) / 55))
                    voiceRecordingLevel = isVoicePaused ? 0 : normalized
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
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

    func notebook(with id: SubjectNotebook.ID) -> SubjectNotebook? {
        notebooks.first { $0.id == id }
    }

    func pin(_ notebook: SubjectNotebook) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isPinned.toggle()
    }

    func rename(_ notebook: SubjectNotebook, to name: String) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].subject = name.lowercased()
    }

    func move(_ notebook: SubjectNotebook, direction: MoveDirection) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        let target = direction == .earlier ? max(index - 1, 0) : min(index + 1, notebooks.count - 1)
        guard target != index else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            notebooks.swapAt(index, target)
        }
    }

    func updatePageText(pageID: NotebookPage.ID, text: String) {
        for notebookIndex in notebooks.indices {
            guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else { continue }
            notebooks[notebookIndex].pages[pageIndex].content.cleanedText = text.lowercased()
            notebooks[notebookIndex].lastActivity = "edited notes"
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
    }

    @MainActor
    func scanPage(into notebookID: SubjectNotebook.ID) async {
        guard let notebook = notebooks.first(where: { $0.id == notebookID }) else { return }
        scanPhase = .capturing
        activeScanJob = ScanJob(targetSubject: notebook.subject, phase: .capturing)
        try? await Task.sleep(for: .seconds(0.55))

        scanPhase = .processing
        activeScanJob?.phase = .processing
        let extracted = await scanProcessor.processDemoCapture()
        try? await Task.sleep(for: .seconds(0.55))

        scanPhase = .organizing
        activeScanJob?.phase = .organizing
        try? await Task.sleep(for: .seconds(0.45))

        scanPhase = .sorted
        activeScanJob?.phase = .sorted
        insertScannedPage(extracted, intoNotebookID: notebookID)
    }

    @MainActor
    func runDemoScan() async {
        scanPhase = .capturing
        activeScanJob = ScanJob(targetSubject: nil, phase: .capturing)
        try? await Task.sleep(for: .seconds(0.8))

        scanPhase = .processing
        activeScanJob?.phase = .processing
        let extracted = await scanProcessor.processDemoCapture()
        try? await Task.sleep(for: .seconds(0.8))

        scanPhase = .organizing
        activeScanJob?.phase = .organizing
        let subject = await aiService.classify(extracted)
        try? await Task.sleep(for: .seconds(0.7))

        scanPhase = .sorted
        activeScanJob?.targetSubject = subject
        activeScanJob?.phase = .sorted
        insertScannedPage(extracted, into: subject)
    }

    func resetScan() {
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

    func askGemmaByVoice() async {
        gemmaVoiceModeEnabled = true
        latestVoiceQuestion = await voiceService.transcribeQuestion()
    }

    private func insertScannedPage(_ content: ExtractedContent, into subject: String) {
        guard let index = notebooks.firstIndex(where: { $0.subject == subject }) else { return }
        insertScannedPage(content, at: index)
    }

    private func insertScannedPage(_ content: ExtractedContent, intoNotebookID notebookID: SubjectNotebook.ID) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        insertScannedPage(content, at: index)
    }

    private func insertScannedPage(_ content: ExtractedContent, at index: Int) {
        let page = NotebookPage(
            title: "limits review",
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
    }
}

enum MoveDirection {
    case earlier
    case later
}
