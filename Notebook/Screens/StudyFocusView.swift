import SwiftUI
import AVFoundation
import UIKit

struct StudyFocusView: View {
    @Environment(NotebookStore.self) private var store
    @State private var selectedTerm: StudyTerm?
    @State private var playback: VoicePlayback?
    @State private var isReading = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = SpeechCompletionDelegate()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var copied = false
    @State private var sprintRemaining = 30
    @State private var sprintActive = false
    @State private var sprintTask: Task<Void, Never>?
    @State private var showingPracticeDrill = false

    let page: NotebookPage

    private var activePage: NotebookPage {
        store.notebooks.flatMap(\.pages).first { $0.id == page.id } ?? page
    }

    private var cards: [Flashcard] {
        store.flashcards(for: activePage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickActions
                smartLanes
                insightCard
                modelWorkbench
                handwritingCard
                coachBoard
                recallPrompts
                tapToStudy
                flashcards
                voiceControls
            }
            .padding(20)
        }
        .background(LivingPaperBackground().ignoresSafeArea())
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $selectedTerm) { term in
            ExplanationSheet(term: term.text)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPracticeDrill) {
            PracticeDrillView(page: activePage) { grade in
                store.recordReview(pageID: activePage.id, grade: grade)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            speechSynthesizer.delegate = speechDelegate
            speechDelegate.onFinish = {
                isReading = false
            }
        }
        .onDisappear {
            speechSynthesizer.stopSpeaking(at: .immediate)
            sprintTask?.cancel()
            isReading = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activePage.title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
            Text("focus on the smallest ideas that move your score.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(NotebookTheme.muted)
            if !activePage.content.insight.nextBestStep.isEmpty {
                Text(activePage.content.insight.nextBestStep)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.58), in: Capsule())
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            StudyQuickButton(symbol: copied ? "checkmark" : "doc.on.doc.fill", text: copied ? "" : nil) {
                Haptics.success()
                UIPasteboard.general.string = activePage.content.cleanedText
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    copied = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            }

            StudyQuickButton(symbol: isReading ? "stop.fill" : "speaker.wave.2.fill", text: nil) {
                Haptics.open()
                if isReading {
                    speechSynthesizer.stopSpeaking(at: .immediate)
                    isReading = false
                } else {
                    isReading = true
                    Task { @MainActor in
                        playback = await store.readAloud(activePage, style: .focusedReview)
                        await play(activePage.content.cleanedText, style: .focusedReview, playback: playback)
                    }
                }
            }

            StudyQuickButton(symbol: sprintActive ? "pause.fill" : "timer", text: "\(sprintRemaining)") {
                Haptics.selection()
                toggleSprint()
            }

            StudyQuickButton(symbol: "questionmark.bubble.fill", text: nil) {
                Haptics.selection()
                selectedTerm = StudyTerm(text: (activePage.content.insight.quickQuestions.first ?? activePage.content.insight.recallPrompts.first) ?? "what matters most?")
            }

            StudyQuickButton(symbol: "target", text: nil) {
                Haptics.open()
                showingPracticeDrill = true
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.6), lineWidth: 0.8)
        }
    }

    private func toggleSprint() {
        if sprintActive {
            sprintTask?.cancel()
            sprintTask = nil
            sprintActive = false
            return
        }
        sprintRemaining = 30
        sprintActive = true
        sprintTask?.cancel()
        sprintTask = Task { @MainActor in
            while sprintRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                sprintRemaining -= 1
            }
            if !Task.isCancelled {
                Haptics.success()
                sprintActive = false
                selectedTerm = StudyTerm(text: activePage.content.insight.recallPrompts.first ?? "say the page from memory.")
            }
        }
    }

    @ViewBuilder
    private var smartLanes: some View {
        if activePage.content.insight.studyLanes.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(activePage.content.insight.studyLanes) { lane in
                        Button {
                            Haptics.selection()
                            selectedTerm = StudyTerm(text: lane.title)
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: lane.systemName)
                                    .font(.system(size: 16, weight: .bold))
                                Text(lane.value)
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 86, height: 74)
                            .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(.white.opacity(0.62), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var insightCard: some View {
        NotebookPaperView {
            VStack(alignment: .leading, spacing: 14) {
                Label("only what matters", systemImage: "sparkles")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(activePage.content.insight.onlyWhatMatters.isEmpty ? (activePage.content.sections.first?.body ?? activePage.content.cleanedText) : activePage.content.insight.onlyWhatMatters)
                    .font(.system(.body, design: .rounded))
                    .lineSpacing(5)
                HStack {
                    PageChip(text: "recall", systemName: "brain.head.profile")
                    PageChip(text: activePage.studyState.dueLabel, systemName: "calendar")
                }
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private var handwritingCard: some View {
        let handwriting = activePage.content.insight.handwriting
        return GlassSurface(radius: 24, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("handwriting")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(NotebookTheme.ink)

                HStack(spacing: 10) {
                    HandwritingGauge(title: "read", value: handwriting.legibility)
                    HandwritingGauge(title: "space", value: handwriting.spacing)
                    HandwritingGauge(title: "shape", value: handwriting.structure)
                }

                HStack(spacing: 8) {
                    PageChip(text: handwriting.pace.rawValue, systemName: "speedometer")
                    PageChip(text: handwriting.pressure.rawValue, systemName: "scribble.variable")
                    PageChip(text: handwriting.noteStyle.rawValue, systemName: "square.grid.2x2")
                }

                if !handwriting.coaching.isEmpty {
                    Text(handwriting.coaching)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                }
            }
        }
    }

    @ViewBuilder
    private var modelWorkbench: some View {
        if !activePage.content.models.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("models")
                    .font(.notebookSection)
                    .foregroundStyle(NotebookTheme.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(activePage.content.models) { model in
                            StudyModelCard(model: model) { node in
                                selectedTerm = StudyTerm(text: node)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var recallPrompts: some View {
        let prompts = activePage.content.insight.recallPrompts + activePage.content.insight.quickQuestions
        return VStack(alignment: .leading, spacing: 12) {
            Text("quick recall")
                .font(.notebookSection)
                .foregroundStyle(NotebookTheme.ink)
            VStack(spacing: 10) {
                ForEach(Array(prompts.prefix(5).enumerated()), id: \.offset) { index, prompt in
                    Button {
                        Haptics.selection()
                        selectedTerm = StudyTerm(text: prompt)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(NotebookTheme.ink, in: Circle())
                            Text(prompt)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NotebookTheme.muted)
                        }
                        .padding(12)
                        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var coachBoard: some View {
        let groups: [(String, String, [String])] = [
            ("hooks", "link.fill", activePage.content.insight.memoryHooks),
            ("exam", "target", activePage.content.insight.examAngles),
            ("alerts", "exclamationmark.triangle.fill", activePage.content.insight.confusionAlerts),
            ("clean", "wand.and.rays", activePage.content.insight.cleanupSuggestions)
        ].filter { !$0.2.isEmpty }

        return VStack(alignment: .leading, spacing: 12) {
            Text("coach")
                .font(.notebookSection)
                .foregroundStyle(NotebookTheme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Button {
                        Haptics.selection()
                        selectedTerm = StudyTerm(text: group.2.first ?? group.0)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: group.1)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(NotebookTheme.ink, in: Circle())
                                Spacer()
                                Text("\(group.2.count)")
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(NotebookTheme.muted)
                            }
                            Text(group.2.first ?? group.0)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(13)
                        .frame(minHeight: 116)
                        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.62), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tapToStudy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tap to study")
                .font(.notebookSection)
                .foregroundStyle(NotebookTheme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                ForEach(activePage.content.keywords + activePage.content.formulas, id: \.self) { token in
                    Button {
                        Haptics.selection()
                        selectedTerm = StudyTerm(text: token)
                    } label: {
                        Text(token)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var flashcards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("flashcards")
                    .font(.notebookSection)
                Spacer()
                Picker("mode", selection: Bindable(store).selectedStudyMode) {
                    ForEach(MemorizationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .onChange(of: store.selectedStudyMode) {
                    Haptics.selection()
                }
            }
            .foregroundStyle(NotebookTheme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        FlashcardPaper(
                            card: card,
                            dueLabel: activePage.studyState.dueLabel,
                            tilt: index.isMultiple(of: 2) ? -1.2 : 1.2,
                            onGrade: { grade in
                                Haptics.success()
                                store.recordReview(pageID: activePage.id, grade: grade)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var voiceControls: some View {
        GlassSurface(radius: 22, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("read aloud")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                HStack(spacing: 14) {
                    ForEach(PlaybackStyle.allCases) { style in
                        Button {
                            Haptics.open()
                            if isReading {
                                speechSynthesizer.stopSpeaking(at: .immediate)
                                isReading = false
                            } else {
                                isReading = true
                                Task { @MainActor in
                                    playback = await store.readAloud(activePage, style: style)
                                    await play(activePage.content.cleanedText, style: style, playback: playback)
                                }
                            }
                        } label: {
                            VoiceStyleButton(style: style, active: isReading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(playback?.summary ?? (isReading ? "reading now" : "choose a playback style"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private func speak(_ text: String, style: PlaybackStyle) {
        speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        switch style {
        case .calmTutor:
            utterance.rate = 0.43
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 0.96 : 1.0
        case .focusedReview:
            utterance.rate = 0.52
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 0.98 : 1.02
        case .examPrep:
            utterance.rate = 0.58
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 1.0 : 1.05
        }
        speechSynthesizer.speak(utterance)
    }

    private func play(_ text: String, style: PlaybackStyle, playback: VoicePlayback?) async {
        if let audioURL = playback?.audioURL,
           let (data, _) = try? await URLSession.shared.data(from: audioURL),
           let player = try? AVAudioPlayer(data: data) {
            audioPlayer = player
            player.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) {
                isReading = false
            }
            return
        }
        speak(text, style: style)
    }

}

private final class SpeechCompletionDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }
}

private struct StudyQuickButton: View {
    let symbol: String
    let text: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                if let text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(NotebookTheme.accent(.amber), in: Capsule())
                        .offset(x: 16, y: -17)
                }
            }
            .frame(width: 50, height: 50)
        }
        .buttonStyle(FloatingCircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
    }
}

private struct ExplanationSheet: View {
    @Environment(NotebookStore.self) private var store
    let term: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(NotebookTheme.muted.opacity(0.28))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
            Text(term.lowercased())
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
            Text(store.explain(term.lowercased()))
                .font(.notebookBody)
                .foregroundStyle(NotebookTheme.muted)
            Spacer()
        }
        .padding(24)
        .background(NotebookTheme.field)
    }
}

private struct PracticeDrillView: View {
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    var onFinish: (ReviewGrade) -> Void
    @State private var currentIndex = 0
    @State private var selectedOption: String?
    @State private var correctCount = 0
    @State private var answeredIDs: Set<PracticeQuestion.ID> = []
    @State private var pulse = false

    private var questions: [PracticeQuestion] {
        PracticeDrillGenerator.questions(for: page)
    }

    private var current: PracticeQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    private var isComplete: Bool {
        !questions.isEmpty && answeredIDs.count >= questions.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()

                VStack(spacing: 16) {
                    header
                    if isComplete {
                        doneCard
                    } else if let current {
                        questionCard(current)
                    }
                    dots
                }
                .padding(20)
            }
            .navigationTitle("practice")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.softTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var header: some View {
        GlassSurface(radius: 28, padding: 14, interactive: true) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.12, to: 0.38)
                        .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(pulse ? 128 : -24))
                        .padding(6)
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(min(answeredIDs.count + 1, max(questions.count, 1)))/\(max(questions.count, 1))")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(page.studyState.dueLabel)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                }
                Spacer()
            }
        }
    }

    private func questionCard(_ question: PracticeQuestion) -> some View {
        NotebookPaperView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: question.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(NotebookTheme.ink, in: Circle())
                    Text(question.kind)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                    Spacer()
                }

                Text(question.prompt)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineSpacing(4)

                VStack(spacing: 10) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            choose(option, for: question)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: optionSymbol(option, question: question))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(optionTint(option, question: question), in: Circle())
                                Text(option)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(.white.opacity(selectedOption == option ? 0.78 : 0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedOption != nil {
                    Text(question.reason)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: selectedOption)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var doneCard: some View {
        GlassSurface(radius: 30, padding: 20, interactive: true) {
            VStack(spacing: 14) {
                Image(systemName: finalGrade.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(finalTint, in: Circle())
                Text("\(correctCount)/\(questions.count)")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(finalCopy)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                Button {
                    Haptics.success()
                    onFinish(finalGrade)
                    dismiss()
                } label: {
                    Text("save")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(NotebookTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, questions.count), id: \.self) { dot in
                Capsule()
                    .fill(dot < answeredIDs.count ? NotebookTheme.accent(.green) : NotebookTheme.ink.opacity(0.16))
                    .frame(width: dot == currentIndex ? 24 : 8, height: 8)
            }
        }
    }

    private func choose(_ option: String, for question: PracticeQuestion) {
        guard selectedOption == nil else { return }
        Haptics.selection()
        selectedOption = option
        if option == question.answer {
            correctCount += 1
        }
        answeredIDs.insert(question.id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(760))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selectedOption = nil
                currentIndex = min(currentIndex + 1, questions.count)
            }
        }
    }

    private func optionSymbol(_ option: String, question: PracticeQuestion) -> String {
        guard let selectedOption else { return "circle" }
        if option == question.answer { return "checkmark" }
        if option == selectedOption { return "xmark" }
        return "circle"
    }

    private func optionTint(_ option: String, question: PracticeQuestion) -> Color {
        guard selectedOption != nil else { return NotebookTheme.ink.opacity(0.82) }
        if option == question.answer { return NotebookTheme.accent(.green) }
        if option == selectedOption { return NotebookTheme.redRule }
        return NotebookTheme.ink.opacity(0.34)
    }

    private var finalGrade: ReviewGrade {
        let ratio = questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
        if ratio < 0.34 { return .forgot }
        if ratio < 0.67 { return .hard }
        if ratio < 0.92 { return .good }
        return .easy
    }

    private var finalTint: Color {
        switch finalGrade {
        case .forgot: NotebookTheme.redRule
        case .hard: NotebookTheme.accent(.amber)
        case .good: NotebookTheme.accent(.green)
        case .easy: NotebookTheme.accent(.blue)
        }
    }

    private var finalCopy: String {
        switch finalGrade {
        case .forgot: "review again soon"
        case .hard: "one more pass"
        case .good: "solid"
        case .easy: "locked in"
        }
    }
}

private struct PracticeQuestion: Identifiable, Hashable {
    var id = UUID()
    var kind: String
    var symbol: String
    var prompt: String
    var options: [String]
    var answer: String
    var reason: String
}

private enum PracticeDrillGenerator {
    static func questions(for page: NotebookPage) -> [PracticeQuestion] {
        var questions: [PracticeQuestion] = []
        let content = page.content
        let pool = answerPool(for: content)

        if let keyword = content.keywords.first {
            questions.append(makeQuestion(
                kind: "term",
                symbol: "text.magnifyingglass",
                prompt: "what best explains \(keyword)?",
                answer: keyword,
                options: options(answer: keyword, pool: pool),
                reason: content.insight.onlyWhatMatters.isEmpty ? "this term appears in the captured page." : content.insight.onlyWhatMatters
            ))
        }

        if let formula = content.formulas.first {
            questions.append(makeQuestion(
                kind: "formula",
                symbol: "function",
                prompt: "which formula belongs here?",
                answer: formula,
                options: options(answer: formula, pool: pool),
                reason: "vellum found this formula in the scanned notes."
            ))
        }

        if let model = content.models.first {
            let nodes = model.nodes ?? model.terms
            let answer = nodes.first ?? model.title
            questions.append(makeQuestion(
                kind: "model",
                symbol: "cube.transparent",
                prompt: "which anchor starts the model?",
                answer: answer,
                options: options(answer: answer, pool: pool + nodes),
                reason: model.summary
            ))
        }

        if let prompt = (content.insight.quickQuestions + content.insight.recallPrompts).first {
            let answer = content.keywords.dropFirst().first ?? content.keywords.first ?? page.title
            questions.append(makeQuestion(
                kind: "recall",
                symbol: "brain.head.profile",
                prompt: prompt,
                answer: answer,
                options: options(answer: answer, pool: pool),
                reason: content.insight.nextBestStep.isEmpty ? "this matches the page's study focus." : content.insight.nextBestStep
            ))
        }

        if questions.isEmpty {
            let answer = page.title.lowercased()
            questions.append(makeQuestion(
                kind: "page",
                symbol: "doc.text.magnifyingglass",
                prompt: "what page are you reviewing?",
                answer: answer,
                options: options(answer: answer, pool: pool),
                reason: "this drill is built from the current notebook page."
            ))
        }

        return Array(questions.prefix(4))
    }

    private static func answerPool(for content: ExtractedContent) -> [String] {
        var seen = Set<String>()
        let modelNodes = content.models.flatMap { $0.nodes ?? $0.terms }
        let tableTerms = content.tables.flatMap { $0.headers }
        let terms = content.keywords + content.formulas + modelNodes + tableTerms + content.sections.map(\.title)
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 1 && seen.insert($0).inserted }
    }

    private static func options(answer: String, pool: [String]) -> [String] {
        var seen = Set<String>()
        var options = [answer.lowercased()]
        for item in pool where item.lowercased() != answer.lowercased() && options.count < 4 {
            let cleaned = item.lowercased()
            if seen.insert(cleaned).inserted {
                options.append(cleaned)
            }
        }
        let fallback = ["main idea", "example", "definition", "diagram", "evidence", "formula"]
        for item in fallback where options.count < 4 {
            if item != answer.lowercased(), seen.insert(item).inserted {
                options.append(item)
            }
        }
        return options.sorted { first, second in
            stableHash(first) < stableHash(second)
        }
    }

    private static func makeQuestion(kind: String, symbol: String, prompt: String, answer: String, options: [String], reason: String) -> PracticeQuestion {
        PracticeQuestion(kind: kind, symbol: symbol, prompt: prompt.lowercased(), options: options, answer: answer.lowercased(), reason: reason.lowercased())
    }

    private static func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
    }
}

private struct HandwritingGauge: View {
    let title: String
    let value: Double
    @State private var animated = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(NotebookTheme.ink.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: animated ? max(0.04, value) : 0.04)
                    .stroke(
                        LinearGradient(
                            colors: [NotebookTheme.ink.opacity(0.92), NotebookTheme.accent(.green).opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink)
            }
            .frame(width: 64, height: 64)

            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.1)) {
                animated = true
            }
        }
    }
}

private struct FlashcardPaper: View {
    let card: Flashcard
    let dueLabel: String
    let tilt: Double
    var onGrade: (ReviewGrade) -> Void
    @State private var touchOffset: CGSize = .zero
    @State private var pressed = false
    @State private var flipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(flipped ? card.back : card.front)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .lineLimit(flipped ? 5 : 3)
                .contentTransition(.opacity)
            if !flipped {
                Text(card.back)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineSpacing(4)
                    .lineLimit(3)
            }
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                PageChip(text: dueLabel, systemName: "arrow.triangle.2.circlepath")
                Spacer(minLength: 0)
                ForEach(ReviewGrade.allCases) { grade in
                    Button {
                        onGrade(grade)
                    } label: {
                        Image(systemName: grade.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 25, height: 25)
                            .background(gradeTint(grade), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 264, height: 196, alignment: .leading)
        .background(NotebookTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            PaperRules()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(0.42)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 0.8)
        }
        .overlay {
            DirectionAwareTouchHighlight(offset: touchOffset, isActive: pressed, cornerRadius: 18)
                .opacity(0.7)
        }
        .rotationEffect(.degrees(tilt))
        .scaleEffect(pressed ? 0.985 : 1)
        .rotation3DEffect(.degrees(flipped ? 8 : (pressed ? Double(touchOffset.width / 8) : 0)), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
        .shadow(color: .black.opacity(pressed ? 0.07 : 0.1), radius: pressed ? 8 : 12, y: pressed ? 5 : 8)
        .onTapGesture {
            Haptics.selection()
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
                flipped.toggle()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        Haptics.softTap()
                    }
                    pressed = true
                    touchOffset = CGSize(width: max(min(value.translation.width, 34), -34), height: max(min(value.translation.height, 34), -34))
                }
                .onEnded { _ in
                    pressed = false
                    touchOffset = .zero
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: pressed)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: touchOffset)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: flipped)
    }

    private func gradeTint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .forgot: NotebookTheme.redRule
        case .hard: NotebookTheme.accent(.amber)
        case .good: NotebookTheme.accent(.green)
        case .easy: NotebookTheme.accent(.blue)
        }
    }
}

private struct VoiceStyleButton: View {
    let style: PlaybackStyle
    var active: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(active ? .white : NotebookTheme.ink)
                .frame(width: 52, height: 52)
                .background(active ? NotebookTheme.ink : .white.opacity(0.66), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
                }
                .scaleEffect(active ? 1.08 : 1)
            Text(shortLabel)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var symbol: String {
        switch style {
        case .calmTutor: "sparkle"
        case .focusedReview: "waveform"
        case .examPrep: "bolt.fill"
        }
    }

    private var shortLabel: String {
        switch style {
        case .calmTutor: "calm"
        case .focusedReview: "focus"
        case .examPrep: "exam"
        }
    }
}

private struct StudyModelCard: View {
    let model: DetectedModel
    var onSelect: (String) -> Void
    @State private var orbit = false
    @State private var selected: String?

    private var reconstruction: ModelReconstruction {
        model.reconstruction ?? ModelReconstructionFactory.make(
            source: "local depth",
            confidence: 0.62,
            shape: .orbit,
            nodes: nodes,
            hint: "tap an anchor."
        )
    }

    private var nodes: [String] {
        let modelNodes = model.nodes ?? []
        return modelNodes.isEmpty ? model.terms : modelNodes
    }

    private var anchors: [ModelAnchor] {
        let available = reconstruction.anchors.isEmpty
            ? ModelReconstructionFactory.make(source: reconstruction.source, confidence: reconstruction.confidence, shape: reconstruction.shape, nodes: nodes, hint: reconstruction.interactionHint).anchors
            : reconstruction.anchors
        return Array(available.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: reconstruction.shape.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(NotebookTheme.ink, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text("\(Int((reconstruction.confidence * 100).rounded()))% \(reconstruction.shape.rawValue)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.3))
                    .overlay {
                        ModelMiniGrid()
                            .opacity(0.55)
                    }

                ForEach(Array(anchors.enumerated()), id: \.element.id) { index, anchor in
                    let point = point(for: anchor, index: index, count: anchors.count)
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            selected = anchor.label
                        }
                        onSelect(anchor.label)
                    } label: {
                        Text(anchor.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: selected == anchor.label ? 78 : 62, height: selected == anchor.label ? 34 : 30)
                            .background(.white.opacity(selected == anchor.label ? 0.86 : 0.58), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.7), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }
            }
            .frame(height: 132)
            .rotation3DEffect(.degrees(orbit ? 4 : -4), axis: (x: 0.1, y: 1, z: 0), perspective: 0.7)

            Text(reconstruction.interactionHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(NotebookTheme.ink.opacity(0.68))
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 248, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.66), lineWidth: 0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                orbit = true
            }
        }
    }

    private func point(for anchor: ModelAnchor, index: Int, count: Int) -> CGPoint {
        if reconstruction.shape == .orbit {
            let angle = (Double(index) / Double(max(count, 1))) * .pi * 2 - .pi / 2 + (orbit ? 0.08 : -0.08)
            return CGPoint(x: 124 + cos(angle) * 72, y: 66 + sin(angle) * 38)
        }
        let shift = orbit ? 3.0 : -3.0
        return CGPoint(
            x: min(220, max(28, anchor.x * 248 + (index.isMultiple(of: 2) ? shift : -shift))),
            y: min(112, max(24, anchor.y * 132))
        )
    }
}

private struct ModelMiniGrid: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let color = NotebookTheme.ink.opacity(0.08)
            for index in 1..<4 {
                let y = size.height * CGFloat(index) / 4
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.6)
            }
        }
    }
}

private struct StudyTerm: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
