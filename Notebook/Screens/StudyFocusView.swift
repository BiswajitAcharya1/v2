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
    @State private var showingExamBlueprint = false
    @State private var showingPageAsk = false
    @State private var selectedModelDrill: DetectedModel?
    @State private var selectedBridgePage: NotebookPage?
    @State private var recallIndex = 0
    @State private var recallRevealed = false
    @State private var recallDrag: CGSize = .zero
    @State private var commandIslandExpanded = false

    let page: NotebookPage

    private var activePage: NotebookPage {
        store.notebooks.flatMap(\.pages).first { $0.id == page.id } ?? page
    }

    private var cards: [Flashcard] {
        store.flashcards(for: activePage)
    }

    private var pathSteps: [StudyPathStep] {
        StudyPathBuilder.steps(for: activePage, cardCount: cards.count)
    }

    private var examPulse: ExamPulse {
        store.examPulse(for: activePage)
    }

    private var forgettingForecast: ForgettingForecast {
        store.forgettingForecast(for: activePage)
    }

    private var inkReplayPlan: InkReplayPlan {
        store.inkReplayPlan(for: activePage)
    }

    private var conceptBridge: ConceptBridgeMap {
        store.conceptBridge(for: activePage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickActions
                examPulsePanel
                forgettingForecastPanel
                conceptBridgePanel
                smartLanes
                insightCard
                studyPathRail
                recallStack
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
        .safeAreaInset(edge: .top, spacing: 0) {
            StudyCommandIsland(
                pulse: examPulse,
                expanded: $commandIslandExpanded,
                isReading: isReading,
                sprintActive: sprintActive,
                sprintRemaining: sprintRemaining,
                onPrimary: {
                    if let first = examPulse.actions.first {
                        performExamPulseAction(first)
                    }
                },
                onSpeak: {
                    toggleReading()
                },
                onSprint: {
                    toggleSprint()
                },
                onPick: { action in
                    performExamPulseAction(action)
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
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
        .sheet(isPresented: $showingExamBlueprint) {
            ExamBlueprintView(page: activePage) { step in
                Haptics.open()
                showingExamBlueprint = false
                if step.kind == .drill {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(260))
                        showingPracticeDrill = true
                    }
                } else {
                    selectedTerm = StudyTerm(text: step.prompt)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPageAsk) {
            PageAskSheet(page: activePage)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedModelDrill) { model in
            ModelReconstructionDrill(model: model) { grade in
                store.recordReview(pageID: activePage.id, grade: grade)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $selectedBridgePage) { page in
            StudyFocusView(page: page)
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
        ScrollView(.horizontal, showsIndicators: false) {
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
                    toggleReading()
                }

                StudyQuickButton(symbol: sprintActive ? "pause.fill" : "timer", text: "\(sprintRemaining)") {
                    toggleSprint()
                }

                StudyQuickButton(symbol: "graduationcap.fill", text: nil) {
                    Haptics.open()
                    showingExamBlueprint = true
                }

                StudyQuickButton(symbol: "text.bubble.fill", text: nil) {
                    Haptics.open()
                    showingPageAsk = true
                }

                StudyQuickButton(symbol: "rectangle.stack.fill", text: nil) {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        recallIndex = 0
                        recallRevealed = false
                        recallDrag = .zero
                    }
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
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.6), lineWidth: 0.8)
        }
        .scrollClipDisabled()
    }

    private func toggleReading() {
        Haptics.open()
        if isReading {
            speechSynthesizer.stopSpeaking(at: .immediate)
            audioPlayer?.stop()
            isReading = false
        } else {
            isReading = true
            Task { @MainActor in
                playback = await store.readAloud(activePage, style: .focusedReview)
                await play(activePage.content.cleanedText, style: .focusedReview, playback: playback)
            }
        }
    }

    private func toggleSprint() {
        Haptics.selection()
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
    private var recallStack: some View {
        if !cards.isEmpty {
            let index = min(recallIndex, cards.count - 1)
            RecallSwipeStack(
                card: cards[index],
                index: index,
                total: cards.count,
                dueLabel: activePage.studyState.dueLabel,
                revealed: recallRevealed,
                drag: recallDrag,
                onTap: {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                        recallRevealed.toggle()
                    }
                },
                onDragChanged: { value in
                    recallDrag = CGSize(
                        width: max(min(value.translation.width, 130), -130),
                        height: max(min(value.translation.height, 120), -120)
                    )
                },
                onDragEnded: { value in
                    finishRecallDrag(value.translation)
                },
                onGrade: { grade in
                    gradeRecall(grade)
                }
            )
        }
    }

    private func finishRecallDrag(_ translation: CGSize) {
        let horizontal = translation.width
        let vertical = translation.height
        if abs(horizontal) < 62 && abs(vertical) < 72 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                recallDrag = .zero
            }
            return
        }
        if abs(horizontal) > abs(vertical) {
            gradeRecall(horizontal > 0 ? .good : .forgot)
        } else {
            gradeRecall(vertical < 0 ? .easy : .hard)
        }
    }

    private func gradeRecall(_ grade: ReviewGrade) {
        Haptics.success()
        store.recordReview(pageID: activePage.id, grade: grade)
        withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
            recallDrag = exitOffset(for: grade)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(210))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                recallIndex = cards.isEmpty ? 0 : (recallIndex + 1) % max(cards.count, 1)
                recallRevealed = false
                recallDrag = .zero
            }
        }
    }

    private func exitOffset(for grade: ReviewGrade) -> CGSize {
        switch grade {
        case .forgot: CGSize(width: -260, height: 24)
        case .hard: CGSize(width: 0, height: 260)
        case .good: CGSize(width: 260, height: 18)
        case .easy: CGSize(width: 28, height: -260)
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

    private var studyPathRail: some View {
        StudyPathRail(steps: pathSteps) { step in
            Haptics.open()
            performPathStep(step)
        }
    }

    private func performPathStep(_ step: StudyPathStep) {
        switch step.kind {
        case .recall:
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                recallIndex = 0
                recallRevealed = false
                recallDrag = .zero
            }
        case .model:
            if let model = activePage.content.models.first {
                selectedModelDrill = model
            } else if let keyword = activePage.content.keywords.first {
                selectedTerm = StudyTerm(text: keyword)
            }
        case .formula:
            selectedTerm = StudyTerm(text: activePage.content.formulas.first ?? step.prompt)
        case .table:
            selectedTerm = StudyTerm(text: step.prompt)
        case .ask:
            showingPageAsk = true
        case .practice:
            showingPracticeDrill = true
        }
    }

    private var examPulsePanel: some View {
        ExamPulsePanel(pulse: examPulse) { action in
            performExamPulseAction(action)
        }
    }

    private var forgettingForecastPanel: some View {
        ForgettingForecastPanel(forecast: forgettingForecast) { point in
            performForecastPoint(point)
        }
    }

    @ViewBuilder
    private var conceptBridgePanel: some View {
        if !conceptBridge.nodes.isEmpty {
            ConceptBridgePanel(map: conceptBridge) { node in
                Haptics.open()
                selectedBridgePage = store.page(with: node.pageID)
            }
        }
    }

    private func performExamPulseAction(_ action: ExamPulseAction) {
        Haptics.open()
        switch action.kind {
        case .recall:
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                recallIndex = 0
                recallRevealed = false
                recallDrag = .zero
            }
        case .model:
            if activePage.content.models.isEmpty {
                store.generateStudyModel(for: activePage.id)
            }
            if let model = store.page(with: activePage.id)?.content.models.first ?? activePage.content.models.first {
                selectedModelDrill = model
            } else {
                selectedTerm = StudyTerm(text: action.prompt)
            }
        case .formula, .table:
            selectedTerm = StudyTerm(text: action.prompt)
        case .ask:
            showingPageAsk = true
        case .drill:
            showingPracticeDrill = true
        }
    }

    private func performForecastPoint(_ point: ForgettingForecastPoint) {
        Haptics.open()
        switch point.action {
        case .recall:
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                recallIndex = 0
                recallRevealed = false
                recallDrag = .zero
            }
        case .model:
            if activePage.content.models.isEmpty {
                store.generateStudyModel(for: activePage.id)
            }
            if let model = store.page(with: activePage.id)?.content.models.first ?? activePage.content.models.first {
                selectedModelDrill = model
            } else {
                selectedTerm = StudyTerm(text: point.prompt)
            }
        case .formula, .table:
            selectedTerm = StudyTerm(text: point.prompt)
        case .ask:
            selectedTerm = StudyTerm(text: point.prompt)
        case .drill:
            showingPracticeDrill = true
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

                InkReplayCoach(plan: inkReplayPlan) {
                    Haptics.open()
                    if (handwriting.signature?.correctionNeed ?? max(0, 1 - handwriting.legibility)) > 0.42 {
                        store.polishPageForStudy(pageID: activePage.id)
                    } else {
                        showingPracticeDrill = true
                    }
                }

                if let signature = handwriting.signature {
                    HandwritingSignaturePanel(signature: signature) {
                        Haptics.open()
                        if signature.correctionNeed > 0.42 {
                            store.polishPageForStudy(pageID: activePage.id)
                        } else {
                            showingPracticeDrill = true
                        }
                    }
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
                            } onDrill: {
                                Haptics.open()
                                selectedModelDrill = model
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

private enum StudyPathKind: Hashable {
    case recall
    case model
    case formula
    case table
    case ask
    case practice
}

private struct StudyPathStep: Identifiable, Hashable {
    let id = UUID()
    var kind: StudyPathKind
    var title: String
    var prompt: String
    var symbol: String
    var tint: ColorToken
}

private enum StudyPathBuilder {
    static func steps(for page: NotebookPage, cardCount: Int) -> [StudyPathStep] {
        var steps: [StudyPathStep] = [
            StudyPathStep(
                kind: .recall,
                title: "recall",
                prompt: page.content.insight.recallPrompts.first ?? "say the main idea.",
                symbol: "brain.head.profile",
                tint: .plum
            )
        ]

        if let model = page.content.models.first {
            steps.append(StudyPathStep(
                kind: .model,
                title: "model",
                prompt: model.title,
                symbol: model.reconstruction?.shape.symbol ?? "cube.transparent",
                tint: .blue
            ))
        }

        if let formula = page.content.formulas.first {
            steps.append(StudyPathStep(
                kind: .formula,
                title: "formula",
                prompt: formula,
                symbol: "function",
                tint: .amber
            ))
        }

        if let table = page.content.tables.first {
            steps.append(StudyPathStep(
                kind: .table,
                title: "table",
                prompt: "recreate \(table.title)",
                symbol: "tablecells",
                tint: .green
            ))
        }

        steps.append(StudyPathStep(
            kind: .ask,
            title: "ask",
            prompt: page.content.insight.quickQuestions.first ?? "what matters?",
            symbol: "text.bubble.fill",
            tint: .blue
        ))

        if cardCount > 0 {
            steps.append(StudyPathStep(
                kind: .practice,
                title: "drill",
                prompt: "\(cardCount) cards",
                symbol: "target",
                tint: .green
            ))
        }

        var seen = Set<StudyPathKind>()
        return Array(steps.filter { seen.insert($0.kind).inserted }.prefix(5))
    }
}

private struct StudyPathRail: View {
    let steps: [StudyPathStep]
    var onPick: (StudyPathStep) -> Void
    @State private var active = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    Button {
                        onPick(step)
                    } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle()
                                    .fill(NotebookTheme.accent(step.tint))
                                Image(systemName: step.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 36, height: 36)
                            .rotation3DEffect(.degrees(active ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                Text(step.prompt)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(NotebookTheme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.68)
                            }
                            .foregroundStyle(NotebookTheme.ink)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .frame(width: 132, height: 54, alignment: .leading)
                        .background(.white.opacity(0.56), in: Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(y: active ? 0 : 8)
                    .opacity(active ? 1 : 0)
                    .animation(.spring(response: 0.48, dampingFraction: 0.84).delay(Double(index) * 0.045), value: active)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .scrollClipDisabled()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct StudyCommandIsland: View {
    let pulse: ExamPulse
    @Binding var expanded: Bool
    var isReading: Bool
    var sprintActive: Bool
    var sprintRemaining: Int
    var onPrimary: () -> Void
    var onSpeak: () -> Void
    var onSprint: () -> Void
    var onPick: (ExamPulseAction) -> Void
    @State private var breathe = false
    @State private var pressed = false

    private var primary: ExamPulseAction? {
        pulse.actions.first
    }

    var body: some View {
        VStack(spacing: expanded ? 10 : 0) {
            HStack(spacing: 9) {
                Button {
                    pressPrimary()
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle()
                                .fill(NotebookTheme.accent(pulse.tint))
                            Circle()
                                .trim(from: 0.08, to: max(0.18, pulse.score))
                                .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                .rotationEffect(.degrees(breathe ? 128 : -22))
                                .padding(5)
                            Image(systemName: pulse.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(primary?.title ?? pulse.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NotebookTheme.ink)
                                .lineLimit(1)
                            Text(primary?.detail ?? pulse.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(NotebookTheme.muted)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                islandButton(symbol: isReading ? "stop.fill" : "speaker.wave.2.fill", active: isReading, action: onSpeak)

                Button(action: onSprint) {
                    HStack(spacing: 4) {
                        Image(systemName: sprintActive ? "pause.fill" : "timer")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(sprintRemaining)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 32)
                    .background(sprintActive ? NotebookTheme.accent(.amber) : NotebookTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.softTap()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.62), in: Circle())
                        .rotationEffect(.degrees(expanded ? 45 : 0))
                }
                .buttonStyle(.plain)
            }

            if expanded {
                HStack(spacing: 8) {
                    ForEach(Array(pulse.actions.prefix(4).enumerated()), id: \.element.id) { index, action in
                        Button {
                            Haptics.open()
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                expanded = false
                            }
                            onPick(action)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(NotebookTheme.accent(action.tint))
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 31, height: 31)
                                .offset(y: breathe ? 0 : 3)

                                Text(action.title)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.44), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.56), lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                        .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(Double(index) * 0.035), value: expanded)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, expanded ? 10 : 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: expanded ? 28 : 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: expanded ? 28 : 25, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 0.8)
        }
        .shadow(color: NotebookTheme.accent(pulse.tint).opacity(0.12), radius: 14, y: 8)
        .scaleEffect(pressed ? 0.985 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func islandButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(active ? NotebookTheme.accent(.green) : NotebookTheme.ink, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func pressPrimary() {
        Haptics.open()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.74)) {
            pressed = true
        }
        onPrimary()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                pressed = false
            }
        }
    }
}

private struct ExamPulsePanel: View {
    let pulse: ExamPulse
    var onPick: (ExamPulseAction) -> Void
    @State private var awake = false
    @State private var pressedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if let first = pulse.actions.first {
                        press(first)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(NotebookTheme.accent(pulse.tint).opacity(0.14))
                            .blur(radius: 1.5)
                        Circle()
                            .fill(.white.opacity(0.5))
                        Circle()
                            .trim(from: 0, to: max(0.1, min(1, pulse.score)))
                            .stroke(NotebookTheme.accent(pulse.tint), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
                            .rotationEffect(.degrees(awake ? -64 : -94))
                        Image(systemName: pulse.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .rotation3DEffect(.degrees(awake ? 10 : -10), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                    }
                    .frame(width: 66, height: 66)
                    .scaleEffect(pressedID == pulse.actions.first?.id ? 0.94 : (awake ? 1.025 : 0.98))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    Text(pulse.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(pulse.prompt)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(pulse.actions.enumerated()), id: \.element.id) { index, action in
                        ExamPulseChip(action: action, active: pressedID == action.id, awake: awake, index: index) {
                            press(action)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 0.8)
        }
        .shadow(color: NotebookTheme.accent(pulse.tint).opacity(0.11), radius: 14, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private func press(_ action: ExamPulseAction) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            pressedID = action.id
        }
        onPick(action)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                pressedID = nil
            }
        }
    }
}

private struct ExamPulseChip: View {
    let action: ExamPulseAction
    var active: Bool
    var awake: Bool
    var index: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(action.tint))
                    Circle()
                        .trim(from: 0.1, to: 0.1 + min(0.76, action.weight * 0.76))
                        .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 118 + Double(index * 18) : -24))
                        .padding(5)
                    Image(systemName: action.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(action.detail)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 11)
            .frame(width: 116, height: 48, alignment: .leading)
            .background(.white.opacity(active ? 0.72 : 0.5), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(active ? 0.82 : 0.58), lineWidth: 0.8)
            }
            .scaleEffect(active ? 0.96 : (awake ? 1.015 : 0.985))
            .rotation3DEffect(.degrees(active ? 8 : 0), axis: (x: 1, y: 0.3, z: 0), perspective: 0.8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}

private struct ForgettingForecastPanel: View {
    let forecast: ForgettingForecast
    var onPick: (ForgettingForecastPoint) -> Void
    @State private var awake = false
    @State private var pressedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: max(0.18, forecast.score))
                        .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 142 : -28))
                        .padding(6)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("forecast")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(forecast.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                }

                Spacer(minLength: 0)
            }

            ZStack {
                ForecastThread(count: forecast.points.count, awake: awake)
                    .frame(height: 72)
                    .padding(.horizontal, 34)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(forecast.points.enumerated()), id: \.element.id) { index, point in
                            ForecastNode(point: point, active: pressedID == point.id, awake: awake, index: index) {
                                press(point)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 13, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private func press(_ point: ForgettingForecastPoint) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            pressedID = point.id
        }
        onPick(point)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                pressedID = nil
            }
        }
    }
}

private struct ForecastThread: View {
    let count: Int
    var awake: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard count > 1 else { return }
            let spacing = size.width / CGFloat(max(1, count - 1))
            var path = Path()
            for index in 0..<count {
                let x = CGFloat(index) * spacing
                let drift = awake ? CGFloat(sin(Double(index) * 0.9) * 2.5) : 0
                let y = size.height * (index.isMultiple(of: 2) ? 0.44 : 0.58) + drift
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addQuadCurve(to: point, control: CGPoint(x: x - spacing * 0.46, y: size.height * 0.5))
                }
            }
            context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.13)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

private struct ForecastNode: View {
    let point: ForgettingForecastPoint
    var active: Bool
    var awake: Bool
    var index: Int
    var action: () -> Void

    private var size: CGFloat {
        50 + CGFloat(point.weight) * 14
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(point.tint).opacity(0.16))
                        .blur(radius: 1.2)
                    Circle()
                        .fill(.white.opacity(active ? 0.78 : 0.55))
                    Circle()
                        .trim(from: 0.08, to: 0.08 + min(0.84, point.weight * 0.84))
                        .stroke(NotebookTheme.accent(point.tint), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 124 + Double(index * 18) : -24))
                        .padding(7)
                    Image(systemName: point.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: size, height: size)
                .scaleEffect(active ? 0.94 : (awake ? 1.02 : 0.98))
                .offset(y: index.isMultiple(of: 2) ? -2 : 3)

                VStack(spacing: 1) {
                    Text(point.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(point.detail)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(point.title)
    }
}

private struct ConceptBridgePanel: View {
    let map: ConceptBridgeMap
    var onPick: (ConceptBridgeNode) -> Void
    @State private var awake = false
    @State private var pressedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: max(0.16, map.score))
                        .stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 138 : -32))
                        .padding(6)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("bridge")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(map.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack {
                    BridgeThread(count: map.nodes.count, awake: awake)
                        .frame(height: 76)
                        .padding(.horizontal, 34)

                    HStack(spacing: 12) {
                        ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                            ConceptBridgeNodeBubble(node: node, active: pressedID == node.id, awake: awake, index: index) {
                                press(node)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .scrollClipDisabled()
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 13, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private func press(_ node: ConceptBridgeNode) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            pressedID = node.id
        }
        onPick(node)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                pressedID = nil
            }
        }
    }
}

private struct BridgeThread: View {
    let count: Int
    var awake: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard count > 1 else { return }
            let spacing = size.width / CGFloat(max(1, count - 1))
            var path = Path()
            for index in 0..<count {
                let drift = awake ? CGFloat(cos(Double(index) * 0.85) * 2.4) : 0
                let x = CGFloat(index) * spacing
                let y = size.height * (index.isMultiple(of: 2) ? 0.4 : 0.6) + drift
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addQuadCurve(to: point, control: CGPoint(x: x - spacing * 0.5, y: size.height * 0.5))
                }
            }
            context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.13)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

private struct ConceptBridgeNodeBubble: View {
    let node: ConceptBridgeNode
    var active: Bool
    var awake: Bool
    var index: Int
    var action: () -> Void

    private var size: CGFloat {
        52 + CGFloat(node.weight) * 15
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(node.tint).opacity(0.16))
                        .blur(radius: 1.2)
                    Circle()
                        .fill(.white.opacity(active ? 0.78 : 0.55))
                    Circle()
                        .trim(from: 0.08, to: 0.08 + min(0.82, node.weight * 0.82))
                        .stroke(NotebookTheme.accent(node.tint), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 124 + Double(index * 18) : -24))
                        .padding(7)
                    Image(systemName: node.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: size, height: size)
                .scaleEffect(active ? 0.94 : (awake ? 1.02 : 0.98))
                .offset(y: index.isMultiple(of: 2) ? -2 : 3)

                VStack(spacing: 1) {
                    Text(node.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(node.detail)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.title)
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

private struct RecallSwipeStack: View {
    let card: Flashcard
    let index: Int
    let total: Int
    let dueLabel: String
    let revealed: Bool
    let drag: CGSize
    var onTap: () -> Void
    var onDragChanged: (DragGesture.Value) -> Void
    var onDragEnded: (DragGesture.Value) -> Void
    var onGrade: (ReviewGrade) -> Void
    @State private var awake = false

    private var gradeHint: ReviewGrade? {
        if abs(drag.width) > abs(drag.height), abs(drag.width) > 42 {
            return drag.width > 0 ? .good : .forgot
        }
        if abs(drag.height) > 52 {
            return drag.height < 0 ? .easy : .hard
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(index + 1)/\(total)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(NotebookTheme.ink, in: Capsule())

                Text(dueLabel)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(1)

                Spacer()

                if let gradeHint {
                    Label(gradeHint.rawValue, systemImage: gradeHint.symbol)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(NotebookTheme.ink, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }

            ZStack {
                ForEach(0..<3, id: \.self) { layer in
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(NotebookTheme.paper.opacity(0.58 - Double(layer) * 0.1))
                        .offset(x: CGFloat(layer) * 4, y: CGFloat(layer) * 7)
                        .scaleEffect(1 - CGFloat(layer) * 0.018)
                        .opacity(layer == 0 ? 0 : 1)
                }

                Button(action: onTap) {
                    NotebookPaperView(cornerRadius: 28) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: revealed ? "checkmark.seal.fill" : "brain.head.profile")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .frame(width: 42, height: 42)
                                    .background(.white.opacity(0.5), in: Circle())
                                    .rotation3DEffect(.degrees(awake ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                                Spacer()
                                Image(systemName: "hand.draw.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(NotebookTheme.muted)
                            }

                            Text(revealed ? card.back : card.front)
                                .font(.system(.title3, design: .serif, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                                .contentTransition(.opacity)

                            HStack(spacing: 8) {
                                gradeButton(.forgot)
                                gradeButton(.hard)
                                gradeButton(.good)
                                gradeButton(.easy)
                            }
                        }
                        .padding(18)
                    }
                }
                .buttonStyle(.plain)
                .rotation3DEffect(.degrees(Double(drag.width / 18)), axis: (x: 0, y: 1, z: 0), perspective: 0.78)
                .rotation3DEffect(.degrees(Double(drag.height / -24)), axis: (x: 1, y: 0, z: 0), perspective: 0.78)
                .rotationEffect(.degrees(Double(drag.width / 34)))
                .offset(drag)
                .scaleEffect(drag == .zero ? 1 : 1.015)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged(onDragChanged)
                        .onEnded(onDragEnded)
                )
            }
            .frame(minHeight: 252)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: drag)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: revealed)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: gradeHint)
    }

    private func gradeButton(_ grade: ReviewGrade) -> some View {
        Button {
            onGrade(grade)
        } label: {
            Image(systemName: grade.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(grade == .forgot ? NotebookTheme.ink : .white)
                .frame(width: 38, height: 38)
                .background(grade == .forgot ? .white.opacity(0.64) : NotebookTheme.ink, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grade.rawValue)
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

private struct PageAskSheet: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    @State private var question = ""
    @State private var answer = ""
    @State private var pulse = false

    private var suggestions: [String] {
        var items: [String] = []
        if let question = page.content.insight.quickQuestions.first { items.append(question) }
        if let prompt = page.content.insight.recallPrompts.first { items.append(prompt) }
        if let keyword = page.content.keywords.first { items.append("explain \(keyword)") }
        if let formula = page.content.formulas.first { items.append("use \(formula)") }
        if let model = page.content.models.first { items.append("explain \(model.title)") }
        return Array(items.prefix(5))
    }

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                askInput
                suggestionStrip
                answerCard
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            answer = store.answer(page.content.insight.quickQuestions.first ?? "", for: page)
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(NotebookTheme.ink)
                Circle()
                    .trim(from: 0.08, to: 0.34)
                    .stroke(.white.opacity(0.32), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(pulse ? 128 : -24))
                    .padding(7)
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("ask page")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(page.title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.softTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
        }
    }

    private var askInput: some View {
        HStack(spacing: 10) {
            TextField("", text: $question)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(NotebookTheme.ink)
                .tint(NotebookTheme.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(answerQuestion)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(.white.opacity(0.58), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
                }

            Button {
                answerQuestion()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(FloatingCircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.selection()
                        question = suggestion
                        answerQuestion()
                    } label: {
                        Text(suggestion)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.white.opacity(0.48), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.56), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var answerCard: some View {
        NotebookPaperView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("answer")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(NotebookTheme.ink)

                Text(answer.isEmpty ? "ask about anything on this page." : answer)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineSpacing(5)
                    .contentTransition(.opacity)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: answer)
    }

    private func answerQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.success()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            answer = store.answer(trimmed, for: page)
        }
    }
}

private struct ExamBlueprintView: View {
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    var onPick: (ExamBlueprintStep) -> Void
    @State private var active = false

    private var steps: [ExamBlueprintStep] {
        ExamBlueprintGenerator.steps(for: page)
    }

    private var risk: Double {
        page.content.insight.retentionRisk
    }

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                header
                stepStack
                startButton
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }

    private var header: some View {
        GlassSurface(radius: 30, padding: 16, interactive: true) {
            HStack(spacing: 14) {
                BlueprintOrbit(risk: risk, active: active)
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 5) {
                    Text("exam map")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(headerLine)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.softTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
            }
        }
    }

    private var headerLine: String {
        if risk > 0.62 { return "start with recall. reread last." }
        if !page.content.models.isEmpty { return "model first, drill second." }
        if !page.content.formulas.isEmpty { return "formula first, practice second." }
        return "short path to test readiness."
    }

    private var stepStack: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                Button {
                    onPick(step)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(step.tint)
                            Image(systemName: step.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 40, height: 40)
                        .rotation3DEffect(.degrees(active ? Double(index) * 1.8 : -Double(index) * 1.4), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                            Text(step.detail)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(NotebookTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text("\(step.minutes)m")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink.opacity(0.6))
                            .frame(width: 38, height: 30)
                            .background(.white.opacity(0.5), in: Capsule())
                    }
                    .padding(12)
                    .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.62), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .offset(y: active ? 0 : 8)
                .opacity(active ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.84).delay(Double(index) * 0.05), value: active)
            }
        }
    }

    private var startButton: some View {
        Button {
            if let first = steps.first {
                onPick(first)
                dismiss()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("start")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PillButtonStyle(tint: NotebookTheme.ink, foreground: .white))
    }
}

private struct BlueprintOrbit: View {
    let risk: Double
    let active: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.34
            for index in 0..<4 {
                let phase = Double(index) / 4.0
                let angle = phase * .pi * 2 + (active ? 0.38 : -0.22)
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius * 0.64
                )
                var line = Path()
                line.move(to: center)
                line.addLine(to: point)
                context.stroke(line, with: .color(NotebookTheme.ink.opacity(0.12)), lineWidth: 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                    with: .color(NotebookTheme.ink.opacity(0.38 + risk * 0.28))
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.9), NotebookTheme.ink.opacity(0.14)]),
                    center: center,
                    startRadius: 1,
                    endRadius: 28
                )
            )
        }
        .padding(8)
        .background(.white.opacity(0.42), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .rotation3DEffect(.degrees(active ? 10 : -10), axis: (x: 0.25, y: 1, z: 0), perspective: 0.8)
    }
}

private struct ExamBlueprintStep: Identifiable {
    enum Kind: Hashable {
        case recall
        case model
        case formula
        case table
        case drill
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let prompt: String
    let symbol: String
    let tint: Color
    let minutes: Int
}

private enum ExamBlueprintGenerator {
    static func steps(for page: NotebookPage) -> [ExamBlueprintStep] {
        let content = page.content
        var steps: [ExamBlueprintStep] = []
        let firstPrompt = content.insight.recallPrompts.first ?? content.insight.quickQuestions.first ?? "explain the page from memory."
        steps.append(ExamBlueprintStep(
            kind: .recall,
            title: "recall",
            detail: content.insight.onlyWhatMatters.isEmpty ? "say the core idea without looking." : content.insight.onlyWhatMatters,
            prompt: firstPrompt,
            symbol: "brain.head.profile",
            tint: NotebookTheme.ink,
            minutes: content.insight.retentionRisk > 0.6 ? 4 : 3
        ))

        if let model = content.models.first {
            let nodes = (model.nodes ?? model.terms).prefix(4).joined(separator: ", ")
            steps.append(ExamBlueprintStep(
                kind: .model,
                title: "model",
                detail: nodes.isEmpty ? model.summary : nodes,
                prompt: "rebuild \(model.title) from memory.",
                symbol: "cube.transparent",
                tint: NotebookTheme.accent(.plum),
                minutes: 3
            ))
        }

        if let formula = content.formulas.first {
            steps.append(ExamBlueprintStep(
                kind: .formula,
                title: "formula",
                detail: formula,
                prompt: "make a new example using \(formula).",
                symbol: "function",
                tint: NotebookTheme.accent(.amber),
                minutes: 3
            ))
        }

        if let table = content.tables.first {
            steps.append(ExamBlueprintStep(
                kind: .table,
                title: "table",
                detail: table.headers.prefix(4).joined(separator: ", "),
                prompt: "recreate \(table.title) without looking.",
                symbol: "tablecells",
                tint: NotebookTheme.accent(.blue),
                minutes: 2
            ))
        }

        steps.append(ExamBlueprintStep(
            kind: .drill,
            title: "drill",
            detail: "\(max(3, min(6, content.keywords.count + content.formulas.count + content.models.count))) checks",
            prompt: "start practice.",
            symbol: "target",
            tint: NotebookTheme.accent(.green),
            minutes: 4
        ))

        var seen = Set<ExamBlueprintStep.Kind>()
        return steps.filter { seen.insert($0.kind).inserted }.prefix(5).map(\.self)
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

private struct InkReplayCoach: View {
    let plan: InkReplayPlan
    var action: () -> Void
    @State private var awake = false
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(plan.tint).opacity(0.16))
                    Circle()
                        .trim(from: 0, to: awake ? max(0.08, plan.score) : 0.08)
                        .stroke(NotebookTheme.accent(plan.tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 48, height: 48)
                .scaleEffect(pressed ? 0.94 : (awake ? 1.03 : 0.98))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Text(plan.detail)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotebookTheme.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(.white.opacity(0.4), in: Capsule())
                    }

                    GeometryReader { proxy in
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.32))
                            ForEach(plan.strokes) { stroke in
                                InkReplayStrokeShape(stroke: stroke)
                                    .trim(from: 0, to: awake ? 1 : 0.04)
                                    .stroke(
                                        NotebookTheme.ink.opacity(0.58),
                                        style: StrokeStyle(lineWidth: stroke.weight, lineCap: .round, lineJoin: .round)
                                    )
                                    .animation(
                                        .easeInOut(duration: 1.3)
                                            .delay(stroke.delay)
                                            .repeatForever(autoreverses: true),
                                        value: awake
                                    )
                            }
                            InkReplayScanLine(active: awake)
                                .fill(NotebookTheme.accent(plan.tint).opacity(0.24))
                                .frame(width: 42, height: proxy.size.height)
                                .blur(radius: 8)
                                .offset(x: awake ? proxy.size.width * 0.38 : -proxy.size.width * 0.38)
                        }
                    }
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 0.8)
            }
            .shadow(color: NotebookTheme.accent(plan.tint).opacity(0.1), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.title)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }
}

private struct InkReplayStrokeShape: Shape {
    let stroke: InkReplayStroke

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(
            x: rect.minX + rect.width * CGFloat(stroke.start.x),
            y: rect.minY + rect.height * CGFloat(stroke.start.y)
        ))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + rect.width * CGFloat(stroke.end.x),
                y: rect.minY + rect.height * CGFloat(stroke.end.y)
            ),
            control: CGPoint(
                x: rect.minX + rect.width * CGFloat(stroke.control.x),
                y: rect.minY + rect.height * CGFloat(stroke.control.y)
            )
        )
        return path
    }
}

private struct InkReplayScanLine: Shape {
    var active: Bool

    var animatableData: Double {
        get { active ? 1 : 0 }
        set { active = newValue > 0.5 }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.height / 2, style: .continuous).path(in: rect)
    }
}

private struct HandwritingSignaturePanel: View {
    let signature: HandwritingSignature
    var action: () -> Void
    @State private var awake = false
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(readinessColor.opacity(0.18))
                    Circle()
                        .trim(from: 0, to: awake ? max(0.08, signature.studyReadiness) : 0.08)
                        .stroke(readinessColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: signature.correctionNeed > 0.42 ? "wand.and.rays" : "bolt.heart.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 48, height: 48)
                .rotation3DEffect(.degrees(awake ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(signature.identity)
                            .font(.system(.callout, design: .serif, weight: .semibold))
                        Text("\(Int((signature.studyReadiness * 100).rounded()))")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(readinessColor.opacity(0.16), in: Capsule())
                    }
                    .foregroundStyle(NotebookTheme.ink)

                    Text(signature.nextStroke.isEmpty ? signature.predictedIssue : signature.nextStroke)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 6) {
                        MiniSignalDot(value: signature.rhythm, color: NotebookTheme.accent(.blue))
                        MiniSignalDot(value: signature.consistency, color: NotebookTheme.accent(.green))
                        MiniSignalDot(value: 1 - signature.correctionNeed, color: NotebookTheme.accent(.amber))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.white.opacity(0.48), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.66), lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.975 : 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private var readinessColor: Color {
        if signature.studyReadiness > 0.72 { return NotebookTheme.accent(.green) }
        if signature.correctionNeed > 0.48 { return NotebookTheme.accent(.amber) }
        return NotebookTheme.ink
    }
}

private struct MiniSignalDot: View {
    let value: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.2))
            .frame(width: 34, height: 5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.86))
                    .frame(width: 34 * max(0.08, min(1, value)), height: 5)
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
    var onDrill: () -> Void
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

            ModelGenerationStatusStrip(reconstruction: reconstruction, nodeCount: anchors.count, active: orbit)

            Text(reconstruction.interactionHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(NotebookTheme.ink.opacity(0.68))
                .lineLimit(2)

            Button {
                onDrill()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.system(size: 12, weight: .bold))
                    Text("drill")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(NotebookTheme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
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

private struct ModelReconstructionDrill: View {
    @Environment(\.dismiss) private var dismiss
    let model: DetectedModel
    var onFinish: (ReviewGrade) -> Void
    @State private var selectedLabels: [String] = []
    @State private var active = false
    @State private var completed = false

    private var nodes: [String] {
        let modelNodes = model.nodes ?? []
        let source = modelNodes.isEmpty ? model.terms : modelNodes
        var seen = Set<String>()
        return source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var reconstruction: ModelReconstruction {
        model.reconstruction ?? ModelReconstructionFactory.make(
            source: "local depth",
            confidence: 0.62,
            shape: .orbit,
            nodes: nodes,
            hint: "tap anchors in order."
        )
    }

    private var anchors: [ModelAnchor] {
        let available = reconstruction.anchors.isEmpty
            ? ModelReconstructionFactory.make(source: reconstruction.source, confidence: reconstruction.confidence, shape: reconstruction.shape, nodes: nodes, hint: reconstruction.interactionHint).anchors
            : reconstruction.anchors
        return Array(available.prefix(8))
    }

    private var nextAnchor: ModelAnchor? {
        anchors.first { !selectedLabels.contains($0.label) }
    }

    private var progress: Double {
        guard !anchors.isEmpty else { return 0 }
        return Double(selectedLabels.count) / Double(anchors.count)
    }

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()

            VStack(spacing: 16) {
                header
                drillSurface
                nodeRail
                gradeRail
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }

    private var header: some View {
        GlassSurface(radius: 30, padding: 16, interactive: true) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: 0.08 + progress * 0.82)
                        .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(6)
                    Image(systemName: reconstruction.shape.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .rotation3DEffect(.degrees(active ? 10 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title.lowercased())
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(completed ? "model rebuilt" : nextAnchor.map { "find \($0.label)" } ?? "rebuild")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    Haptics.softTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
            }
        }
    }

    private var drillSurface: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.white.opacity(0.28))
                    .overlay {
                        ModelMiniGrid()
                            .opacity(0.7)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(.white.opacity(0.62), lineWidth: 0.8)
                    }

                ForEach(Array(anchors.enumerated()), id: \.element.id) { index, anchor in
                    let point = point(for: anchor, in: proxy.size, center: center, index: index)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(NotebookTheme.ink.opacity(selectedLabels.contains(anchor.label) ? 0.28 : 0.1), lineWidth: selectedLabels.contains(anchor.label) ? 1.8 : 1)
                }

                Circle()
                    .fill(NotebookTheme.ink)
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: reconstruction.shape.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .position(center)
                    .rotation3DEffect(.degrees(active ? 12 : -10), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                ForEach(Array(anchors.enumerated()), id: \.element.id) { index, anchor in
                    let isSelected = selectedLabels.contains(anchor.label)
                    let isNext = nextAnchor?.id == anchor.id
                    Button {
                        tap(anchor)
                    } label: {
                        Text(anchor.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(isSelected ? .white : NotebookTheme.ink)
                            .frame(width: isNext ? 92 : 74, height: isNext ? 42 : 34)
                            .background(isSelected ? NotebookTheme.ink : .white.opacity(isNext ? 0.82 : 0.56), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.7), lineWidth: 0.8)
                            }
                            .scaleEffect(isNext && active ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .position(point(for: anchor, in: proxy.size, center: center, index: index))
                }
            }
        }
        .frame(height: 292)
        .rotation3DEffect(.degrees(active ? 1.8 : -1.8), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
    }

    private var nodeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(anchors) { anchor in
                    HStack(spacing: 6) {
                        Image(systemName: selectedLabels.contains(anchor.label) ? "checkmark" : "circle")
                            .font(.system(size: 10, weight: .bold))
                        Text(anchor.label)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedLabels.contains(anchor.label) ? .white : NotebookTheme.ink.opacity(0.74))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(selectedLabels.contains(anchor.label) ? NotebookTheme.ink : .white.opacity(0.48), in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var gradeRail: some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    Haptics.success()
                    onFinish(grade)
                    dismiss()
                } label: {
                    Image(systemName: grade.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(grade == .forgot ? NotebookTheme.ink : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(grade == .forgot ? .white.opacity(0.62) : NotebookTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(completed ? 1 : 0.42)
        .disabled(!completed)
    }

    private func tap(_ anchor: ModelAnchor) {
        guard !selectedLabels.contains(anchor.label) else { return }
        if nextAnchor?.id == anchor.id {
            Haptics.selection()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                selectedLabels.append(anchor.label)
                completed = selectedLabels.count == anchors.count
            }
            if selectedLabels.count == anchors.count {
                Haptics.success()
            }
        } else {
            Haptics.softTap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                selectedLabels.removeAll()
                completed = false
            }
        }
    }

    private func point(for anchor: ModelAnchor, in size: CGSize, center: CGPoint, index: Int) -> CGPoint {
        if reconstruction.shape == .orbit || reconstruction.shape == .cycle {
            let angle = Double(index) / Double(max(anchors.count, 1)) * .pi * 2 - .pi / 2 + (active ? 0.08 : -0.08)
            return CGPoint(x: center.x + cos(angle) * min(size.width, size.height) * 0.36, y: center.y + sin(angle) * min(size.width, size.height) * 0.25)
        }
        return CGPoint(
            x: min(size.width - 48, max(48, anchor.x * size.width)),
            y: min(size.height - 44, max(44, anchor.y * size.height))
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

private struct ModelGenerationStatusStrip: View {
    let reconstruction: ModelReconstruction
    let nodeCount: Int
    var active: Bool

    var body: some View {
        HStack(spacing: 7) {
            statusPill(symbol: reconstruction.shape.symbol, text: reconstruction.shape.rawValue, color: NotebookTheme.accent(.blue))
            statusPill(symbol: "point.3.connected.trianglepath.dotted", text: "\(nodeCount)", color: NotebookTheme.accent(.green))
            statusPill(symbol: "waveform.path.ecg", text: "\(Int((reconstruction.confidence * 100).rounded()))", color: confidenceColor)
        }
        .padding(6)
        .background(.white.opacity(0.34), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.58), lineWidth: 0.7)
        }
        .scaleEffect(active ? 1 : 0.985)
    }

    private func statusPill(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.78))
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var confidenceColor: Color {
        if reconstruction.confidence > 0.78 { return NotebookTheme.accent(.green) }
        if reconstruction.confidence > 0.58 { return NotebookTheme.accent(.amber) }
        return NotebookTheme.redRule
    }
}

private struct StudyTerm: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
