import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NotebookStore {
    var user = NotebookUser(name: "maya", gradeLevel: "11")
    var notebooks: [SubjectNotebook] = NotebookFixtures.notebooks
    var isAuthenticated = false
    var activeScanJob: ScanJob?
    var selectedStudyMode: MemorizationMode = .longTerm
    var voiceProfile = VoiceProfile()
    var scanPhase: ScanPhase = .framing

    private let scanProcessor: ScanProcessingServing = MockScanProcessingService()
    private let aiService: NoteUnderstandingServing = MockNoteUnderstandingService()
    private let reviewService: SpacedRepetitionServing = MockSpacedRepetitionService()
    private let voiceService: VoiceServing = MockVoiceService()

    var pinnedNotebooks: [SubjectNotebook] {
        notebooks.filter(\.isPinned)
    }

    func signIn() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            isAuthenticated = true
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

    func schedule(for card: Flashcard, mode: MemorizationMode) -> ReviewState {
        reviewService.schedule(card, mode: mode)
    }

    func readAloud(_ page: NotebookPage, style: PlaybackStyle) async -> VoicePlayback {
        await voiceService.makePlayback(page.content.cleanedText, style: style, profile: voiceProfile)
    }

    private func insertScannedPage(_ content: ExtractedContent, into subject: String) {
        guard let index = notebooks.firstIndex(where: { $0.subject == subject }) else { return }
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
