import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace
    @State private var sparkleSpin = false
    @State private var selectedNotebook: SubjectNotebook?
    @State private var entered = false
    @State private var showingCourseComposer = false
    @State private var showingAccountCenter = false
    @State private var showingQuickScanner = false
    @State private var showingSmartSearch = false
    @State private var showingReviewSprint = false
    @State private var quickScanning = false
    @State private var selectedStudyPage: NotebookPage?
    @State private var courseDraft = ""
    @State private var courseCloseRotation = 0.0
    @State private var addButtonRotation = 0.0
    @State private var selectedJournalIndex = 0
    @State private var journalDragOffset: CGFloat = 0
    @State private var doodleDrift = false
    @State private var modelReadyPulse = false
    @State private var actionLensAwake = false
    @State private var revealDetailSurfaces = false
    @State private var stylingNotebook: SubjectNotebook?
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                header
                journalCarousel
            }
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background {
            LivingPaperBackground().ignoresSafeArea()
        }
        .navigationDestination(item: $selectedNotebook) { notebook in
            NotebookDetailView(notebook: notebook)
        }
        .navigationDestination(item: $selectedStudyPage) { page in
            StudyFocusView(page: page)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCourseComposer) {
            addCourseSheet
                .presentationDetents([.height(492)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $stylingNotebook) { notebook in
            NotebookStyleSheet(notebook: notebook)
                .presentationDetents([.height(620), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAccountCenter) {
            AccountCenterView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingQuickScanner) {
            DocumentScannerView { images in
                guard let notebook = activeNotebook else { return }
                Task {
                    quickScanning = true
                    await store.scanCapturedImages(images, into: notebook.id)
                    Haptics.success()
                    quickScanning = false
                }
            } onCancel: {
                quickScanning = false
                Haptics.softTap()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingSmartSearch) {
            SmartSearchView { page in
                showingSmartSearch = false
                selectedStudyPage = page
            } onModel: { page in
                showingSmartSearch = false
                openGeneratedModel(for: page)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReviewSprint) {
            ReviewSprintView { page in
                showingReviewSprint = false
                selectedStudyPage = page
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6.2).repeatForever(autoreverses: true)) {
                sparkleSpin = true
            }
            withAnimation(.spring(response: 0.96, dampingFraction: 0.88).delay(0.12)) {
                entered = true
            }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                    doodleDrift = true
                }
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    actionLensAwake = true
                }
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button {
                    openCourseComposer()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(addButtonRotation))
                }
                .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                .accessibilityLabel("add course")

                Spacer()

                Button {
                    Haptics.open()
                    showingAccountCenter = true
                } label: {
                    AccountOrb(avatar: store.user.avatar)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("account")
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : -8)
    }

    private var journalCarousel: some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * (store.notebooks.count == 1 ? 0.94 : 0.86), 410)

            ZStack(alignment: .top) {
                ZStack {
                    ForEach(Array(store.notebooks.enumerated()), id: \.element.id) { index, notebook in
                        let distance = index - selectedJournalIndex
                        if abs(distance) <= 2 {
                            ZStack {
                                if index == selectedJournalIndex {
                                    JournalHalo(accent: NotebookTheme.accent(notebook.accent), animated: sparkleSpin)
                                }
                                CompositionNotebookCard(notebook: notebook, namespace: notebookNamespace) {
                                    if index == selectedJournalIndex {
                                        withAnimation(.spring(response: 0.76, dampingFraction: 0.88)) {
                                            selectedNotebook = store.notebook(with: notebook.id) ?? notebook
                                        }
                                    } else {
                                        Haptics.selection()
                                        withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
                                            selectedJournalIndex = index
                                        }
                                    }
                                } onCustomize: {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                        selectedJournalIndex = index
                                        stylingNotebook = store.notebook(with: notebook.id) ?? notebook
                                    }
                                }
                                .frame(width: cardWidth)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .scaleEffect(journalScale(for: distance))
                            .rotationEffect(.degrees(Double(distance) * -3.8))
                            .rotation3DEffect(.degrees(Double(distance) * 5.5), axis: (x: 0, y: 1, z: 0), perspective: 0.74)
                            .offset(x: journalXOffset(for: distance), y: journalYOffset(for: distance))
                            .opacity(journalOpacity(for: distance))
                            .zIndex(Double(10 - abs(distance)))
                            .offset(y: entered ? 0 : 24)
                            .opacity(entered ? journalOpacity(for: distance) : 0)
                            .animation(.spring(response: 0.94, dampingFraction: 0.88).delay(Double(index) * 0.08), value: entered)
                            .animation(.spring(response: 0.76, dampingFraction: 0.88), value: selectedJournalIndex)
                            .animation(.spring(response: 0.46, dampingFraction: 0.9), value: journalDragOffset)
                        }
                    }
                }
                .frame(height: 548)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            journalDragOffset = max(min(value.translation.width, 96), -96)
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 46
                            withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
                                if value.translation.width < -threshold, selectedJournalIndex < store.notebooks.count - 1 {
                                    selectedJournalIndex += 1
                                    Haptics.selection()
                                } else if value.translation.width > threshold, selectedJournalIndex > 0 {
                                    selectedJournalIndex -= 1
                                    Haptics.selection()
                                }
                                journalDragOffset = 0
                            }
                        }
                )

            }
        }
        .frame(height: 562)
    }

    private var journalIndexRail: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.notebooks.enumerated()), id: \.element.id) { index, notebook in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) {
                        selectedJournalIndex = index
                    }
                } label: {
                    Capsule()
                        .fill(index == selectedJournalIndex ? NotebookTheme.accent(notebook.accent) : NotebookTheme.ink.opacity(0.14))
                        .frame(width: index == selectedJournalIndex ? 28 : 8, height: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(notebook.subject) journal")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var journalCommandSurface: some View {
        JournalCommandSurface(
            notebook: activeNotebook,
            move: nextBestMove,
            items: actionLensItems,
            score: actionLensScore,
            awake: actionLensAwake
        ) { kind in
            performActionLens(kind)
        }
        .padding(.horizontal, 20)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 14)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: nextBestMove.kind)
    }

    private var activeJournalText: String {
        guard store.notebooks.indices.contains(selectedJournalIndex) else { return "ready" }
        let notebook = store.notebooks[selectedJournalIndex]
        return notebook.pages.isEmpty ? "ready to scan" : "\(notebook.pages.count) pages"
    }

    private var activeNotebook: SubjectNotebook? {
        guard store.notebooks.indices.contains(selectedJournalIndex) else { return store.notebooks.first }
        return store.notebooks[selectedJournalIndex]
    }

    private var dailyBrief: StudyDailyBrief {
        store.dailyBrief(in: activeNotebook?.id)
    }

    private var memoryMap: StudyMemoryMap {
        store.memoryMap(in: activeNotebook?.id)
    }

    private var presentationRunway: PresentationRunway {
        store.presentationRunway(in: activeNotebook?.id)
    }

    private var recommendedPage: NotebookPage? {
        store.reviewQueue(limit: 1).first
    }

    private var modelCandidatePage: NotebookPage? {
        if let notebook = activeNotebook,
           let page = store.bestModelPage(in: notebook.id),
           store.modelReadiness(for: page).score > 0.28 {
            return page
        }
        return store.bestModelPage() ?? recommendedPage
    }

    private var hasSearchablePages: Bool {
        store.notebooks.contains { !$0.pages.isEmpty }
    }

    private var actionLensItems: [ActionLensItem] {
        var items: [ActionLensItem] = []
        if activeNotebook != nil {
            items.append(ActionLensItem(kind: .scan, symbol: "viewfinder", label: "scan", tint: NotebookTheme.ink))
        }
        if hasSearchablePages {
            items.append(ActionLensItem(kind: .search, symbol: "magnifyingglass", label: "find", tint: NotebookTheme.accent(.amber)))
        }
        if recommendedPage != nil {
            items.append(ActionLensItem(kind: .review, symbol: "brain.head.profile", label: "review", tint: NotebookTheme.accent(.plum)))
        }
        if modelCandidatePage != nil {
            items.append(ActionLensItem(kind: .model, symbol: "cube.transparent", label: "model", tint: NotebookTheme.accent(.blue)))
        }
        if activeNotebook != nil {
            items.append(ActionLensItem(kind: .open, symbol: "book.pages.fill", label: "open", tint: NotebookTheme.accent(.green)))
        }
        if items.count < 4 {
            items.append(ActionLensItem(kind: .add, symbol: "plus", label: "add", tint: NotebookTheme.accent(.amber)))
        }
        return Array(items.prefix(4))
    }

    private var nextBestMove: NextBestMove {
        if activeNotebook?.pages.isEmpty == true {
            return NextBestMove(
                kind: .scan,
                symbol: "viewfinder",
                title: "scan",
                detail: activeNotebook?.subject ?? "notes",
                tint: NotebookTheme.ink,
                score: 0.22
            )
        }
        if let page = store.reviewQueue(limit: 1).first, page.content.insight.retentionRisk > 0.42 {
            return NextBestMove(
                kind: .review,
                symbol: "brain.head.profile",
                title: "review",
                detail: page.title.lowercased(),
                tint: NotebookTheme.accent(.plum),
                score: page.content.insight.retentionRisk
            )
        }
        if let page = modelCandidatePage, page.content.models.isEmpty || page.content.insight.detectedFeatures.contains("sketch") {
            return NextBestMove(
                kind: .model,
                symbol: "cube.transparent",
                title: "rebuild",
                detail: page.title.lowercased(),
                tint: NotebookTheme.accent(.blue),
                score: page.content.insight.handwriting.structure
            )
        }
        if let notebook = activeNotebook {
            return NextBestMove(
                kind: .open,
                symbol: "book.pages.fill",
                title: "open",
                detail: notebook.subject,
                tint: NotebookTheme.accent(notebook.accent),
                score: max(0.22, notebook.progress)
            )
        }
        return NextBestMove(
            kind: .add,
            symbol: "plus",
            title: "add",
            detail: "course",
            tint: NotebookTheme.accent(.amber),
            score: 0.16
        )
    }

    @ViewBuilder
    private var presentationRunwayPanel: some View {
        if !presentationRunway.steps.isEmpty {
            PresentationRunwayPanel(runway: presentationRunway, avatar: store.user.avatar, awake: actionLensAwake) { step in
                performRunway(step)
            }
            .padding(.horizontal, 20)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 12)
            .animation(.spring(response: 0.62, dampingFraction: 0.86), value: presentationRunway)
        }
    }

    @ViewBuilder
    private var dailyBriefStrip: some View {
        if !dailyBrief.items.isEmpty {
            DailyBriefStrip(brief: dailyBrief, awake: actionLensAwake) { item in
                performBrief(item)
            }
            .padding(.horizontal, 20)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 12)
        }
    }

    @ViewBuilder
    private var memoryMapRibbon: some View {
        if !memoryMap.nodes.isEmpty {
            MemoryMapRibbon(map: memoryMap, awake: actionLensAwake) { node in
                performMemoryNode(node)
            }
            .padding(.horizontal, 20)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 12)
            .animation(.spring(response: 0.62, dampingFraction: 0.86), value: memoryMap.nodes)
        }
    }

    private var autopilotPlan: StudyAutopilotPlan {
        store.studyAutopilot(in: activeNotebook?.id)
    }

    private var autopilotCapsule: some View {
        AutopilotCapsule(plan: autopilotPlan, awake: actionLensAwake) {
            performAutopilot(autopilotPlan)
        }
        .padding(.horizontal, 20)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
    }

    @ViewBuilder
    private var modelReadinessCapsule: some View {
        if let page = modelCandidatePage {
            ModelReadinessCapsule(page: page, readiness: store.modelReadiness(for: page), awake: actionLensAwake) {
                Haptics.success()
                openGeneratedModel(for: page)
            }
            .padding(.horizontal, 20)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 12)
        }
    }

    private func performAutopilot(_ plan: StudyAutopilotPlan) {
        Haptics.open()
        switch plan.kind {
        case .scan:
            if let notebookID = plan.notebookID,
               let notebook = store.notebook(with: notebookID) {
                selectedJournalIndex = store.notebooks.firstIndex(where: { $0.id == notebook.id }) ?? selectedJournalIndex
                showingQuickScanner = true
            } else {
                performActionLens(.scan)
            }
        case .clean:
            if let pageID = plan.pageID {
                store.polishPageForStudy(pageID: pageID)
                if let page = store.page(with: pageID) {
                    selectedStudyPage = page
                }
            }
        case .model:
            if let pageID = plan.pageID,
               let page = store.page(with: pageID) {
                Haptics.success()
                openGeneratedModel(for: page)
            }
        case .review, .study:
            if let pageID = plan.pageID,
               let page = store.page(with: pageID) {
                selectedStudyPage = page
            } else if let notebookID = plan.notebookID,
                      let notebook = store.notebook(with: notebookID) {
                selectedNotebook = notebook
            }
        case .add:
            openCourseComposer()
        }
    }

    private func performBrief(_ item: StudyBriefItem) {
        Haptics.open()
        switch item.kind {
        case .scan:
            if let notebookID = item.notebookID,
               let notebook = store.notebook(with: notebookID) {
                selectedJournalIndex = store.notebooks.firstIndex(where: { $0.id == notebook.id }) ?? selectedJournalIndex
            }
            showingQuickScanner = true
        case .clean:
            if let pageID = item.pageID {
                store.polishPageForStudy(pageID: pageID)
                if let page = store.page(with: pageID) {
                    selectedStudyPage = page
                }
            }
        case .model:
            if let pageID = item.pageID,
               let page = store.page(with: pageID) {
                Haptics.success()
                openGeneratedModel(for: page)
            }
        case .review:
            if let pageID = item.pageID,
               let page = store.page(with: pageID) {
                selectedStudyPage = page
            }
        case .search:
            if hasSearchablePages {
                showingSmartSearch = true
            }
        }
    }

    private func performMemoryNode(_ node: StudyMemoryNode) {
        Haptics.open()
        switch node.kind {
        case .keyword:
            if let pageID = node.pageID,
               let page = store.page(with: pageID) {
                selectedStudyPage = page
            } else {
                showingSmartSearch = true
            }
        case .model, .table, .formula:
            if let pageID = node.pageID,
               let page = store.page(with: pageID) {
                Haptics.success()
                openGeneratedModel(for: page)
            }
        case .review:
            if let pageID = node.pageID,
               let page = store.page(with: pageID) {
                selectedStudyPage = page
            } else {
                showingReviewSprint = true
            }
        case .notebook:
            if let notebookID = node.notebookID,
               let notebook = store.notebook(with: notebookID) {
                if notebook.pages.isEmpty {
                    selectedJournalIndex = store.notebooks.firstIndex(where: { $0.id == notebook.id }) ?? selectedJournalIndex
                    showingQuickScanner = true
                } else {
                    selectedNotebook = notebook
                }
            }
        }
    }

    private func performRunway(_ step: PresentationRunwayStep) {
        Haptics.open()
        switch step.kind {
        case .scan:
            if let empty = store.notebooks.first(where: { $0.pages.isEmpty }) {
                selectedJournalIndex = store.notebooks.firstIndex(where: { $0.id == empty.id }) ?? selectedJournalIndex
            }
            showingQuickScanner = activeNotebook != nil
        case .sort, .search:
            if hasSearchablePages {
                showingSmartSearch = true
            } else {
                showingQuickScanner = activeNotebook != nil
            }
        case .model:
            if let page = modelCandidatePage {
                Haptics.success()
                openGeneratedModel(for: page)
            } else if hasSearchablePages {
                showingSmartSearch = true
            }
        case .review:
            if recommendedPage != nil {
                showingReviewSprint = true
            } else if let notebook = activeNotebook {
                selectedNotebook = store.notebook(with: notebook.id) ?? notebook
            }
        case .avatar:
            showingAccountCenter = true
        }
    }

    private var actionLensScore: Double {
        let pages = store.notebooks.flatMap(\.pages)
        guard !pages.isEmpty else { return 0.18 }
        let clarity = pages.reduce(0) { $0 + $1.content.insight.clarityScore } / Double(pages.count)
        let progress = store.notebooks.isEmpty ? 0 : store.notebooks.reduce(0) { $0 + $1.progress } / Double(store.notebooks.count)
        let reviews = min(1, Double(pages.reduce(0) { $0 + $1.studyState.reviewCount }) / Double(max(pages.count * 2, 1)))
        return min(1, max(0.12, clarity * 0.46 + progress * 0.34 + reviews * 0.2))
    }

    private func performActionLens(_ kind: ActionLensKind) {
        switch kind {
        case .scan:
            guard activeNotebook != nil, !quickScanning else { return }
            Haptics.open()
            showingQuickScanner = true
        case .search:
            guard hasSearchablePages else { return }
            Haptics.open()
            showingSmartSearch = true
        case .review:
            guard recommendedPage != nil else { return }
            Haptics.open()
            showingReviewSprint = true
        case .model:
            guard let page = modelCandidatePage else { return }
            Haptics.success()
            openGeneratedModel(for: page)
        case .open:
            guard let notebook = activeNotebook else { return }
            Haptics.open()
            selectedNotebook = store.notebook(with: notebook.id) ?? notebook
        case .add:
            openCourseComposer()
        }
    }

    private var modelReadyToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(NotebookTheme.accent(.blue), in: Circle())
            Text("model ready")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .scaleEffect(modelReadyPulse ? 1 : 0.82)
        .opacity(modelReadyPulse ? 1 : 0)
        .offset(y: modelReadyPulse ? 0 : -8)
    }

    private var reviewPulseStrip: some View {
        let queue = store.reviewQueue(limit: 4)
        return Group {
            if !queue.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(queue) { page in
                            Button {
                                Haptics.open()
                                selectedStudyPage = page
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.heart.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(NotebookTheme.ink, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(page.title.lowercased())
                                            .font(.system(.caption, design: .serif, weight: .semibold))
                                            .foregroundStyle(NotebookTheme.ink)
                                            .lineLimit(1)
                                        Text(page.studyState.dueLabel)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(NotebookTheme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 12)
                                .frame(height: 46)
                                .background(.white.opacity(0.5), in: Capsule())
                                .overlay {
                                    Capsule().stroke(.white.opacity(0.6), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 10)
            }
        }
    }

    private var addCourseSheet: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            GlassSurface(radius: 30, padding: 20, interactive: true) {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(NotebookTheme.ink, in: Circle())
                        Text("add course")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Spacer()
                        Button {
                            closeCourseSheet()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 38, height: 38)
                                .rotationEffect(.degrees(courseCloseRotation))
                        }
                        .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        GooeyInput(
                            label: "course",
                            systemName: "magnifyingglass",
                            text: $courseDraft,
                            onSubmit: addCourse
                        )

                        Button(action: addCourse) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 54, height: 54)
                        }
                        .buttonStyle(FloatingCircleButtonStyle())
                        .disabled(bestCourseMatch == nil)
                        .opacity(bestCourseMatch == nil ? 0.42 : 1)
                    }

                    CourseSuggestionCarousel(
                        subjects: courseSuggestions,
                        activeSubject: bestCourseMatch,
                        onSelect: addCourse
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 1.04, dampingFraction: 0.9), value: courseSuggestions)
                }
            }
            .padding(20)
        }
    }

    private func openGeneratedModel(for page: NotebookPage) {
        guard store.generateStudyModel(for: page.id) != nil else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
            modelReadyPulse = true
            selectedStudyPage = store.notebooks.flatMap(\.pages).first { $0.id == page.id } ?? page
        }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.26)) {
                    modelReadyPulse = false
                }
            }
        }
    }

    private var courseSuggestions: [String] {
        SubjectCatalog.suggestions(
            for: courseDraft,
            excluding: Set(store.notebooks.map(\.subject)),
            limit: courseDraft.isEmpty ? 8 : 4
        )
    }

    private var bestCourseMatch: String? {
        SubjectCatalog.bestMatch(for: courseDraft, excluding: Set(store.notebooks.map(\.subject)))
    }

    private func addCourse() {
        guard let subject = bestCourseMatch else { return }
        addCourse(subject)
    }

    private func addCourse(_ subject: String) {
        Haptics.success()
        store.addCourse(subject)
        courseDraft = ""
        showingCourseComposer = false
    }

    private func openCourseComposer() {
        Haptics.open()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            addButtonRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            showingCourseComposer = true
        }
    }

    private func closeCourseSheet() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            courseCloseRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            showingCourseComposer = false
        }
    }

    private func journalScale(for distance: Int) -> CGFloat {
        let depth = min(abs(distance), 2)
        return 1 - CGFloat(depth) * 0.085
    }

    private func journalXOffset(for distance: Int) -> CGFloat {
        CGFloat(distance) * 34 + journalDragOffset * (distance == 0 ? 0.42 : 0.16)
    }

    private func journalYOffset(for distance: Int) -> CGFloat {
        CGFloat(abs(distance)) * 18
    }

    private func journalOpacity(for distance: Int) -> Double {
        abs(distance) > 1 ? 0.42 : 1
    }
}

private struct CourseSuggestionCarousel: View {
    var subjects: [String]
    var activeSubject: String?
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(subjects.enumerated()), id: \.element) { index, subject in
                    CourseSuggestionBook(
                        subject: subject,
                        active: subject == activeSubject,
                        delay: Double(index) * 0.09
                    ) {
                        onSelect(subject)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
        }
        .frame(height: 142)
    }
}

private struct NotebookStyleSheet: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let notebook: SubjectNotebook
    @State private var closeRotation = 0.0
    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var previewPressed = false

    private var liveNotebook: SubjectNotebook {
        store.notebook(with: notebook.id) ?? notebook
    }

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("cover")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Spacer()
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(closeRotation))
                    }
                    .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                }

                HStack(spacing: 18) {
                    CompositionCoverFace(
                        subject: liveNotebook.subject,
                        cornerRadius: 18,
                        spineWidth: 16,
                        labelWidth: 106,
                        labelHeight: 82,
                        labelOffsetY: 24,
                        paperGrainDensity: 70,
                        coverStyle: liveNotebook.coverStyle,
                        coverColor: liveNotebook.coverColor,
                        labelStyle: liveNotebook.coverLabelStyle,
                        fontStyle: liveNotebook.coverFontStyle,
                        customCoverImage: liveNotebook.customCoverImage
                    )
                    .frame(width: 164, height: 222)
                    .rotation3DEffect(.degrees(previewPressed ? -16 : -7), axis: (x: 0.1, y: 1, z: 0), perspective: 0.7)
                    .scaleEffect(previewPressed ? 1.035 : 1)
                    .shadow(color: .black.opacity(previewPressed ? 0.22 : 0.16), radius: previewPressed ? 22 : 16, y: previewPressed ? 14 : 10)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.38)
                            .onChanged { _ in
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                                    previewPressed = true
                                }
                            }
                            .onEnded { _ in
                                Haptics.success()
                                cycleCoverLook()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                                    previewPressed = false
                                }
                            }
                    )
                    .overlay(alignment: .bottom) {
                        Text("hold to remix")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotebookTheme.ink.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.68), in: Capsule())
                            .offset(y: 18)
                            .opacity(previewPressed ? 1 : 0.82)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("style")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(NotebookCoverStyle.allCases) { style in
                                styleButton(style)
                            }
                        }

                        Text("color")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)

                        HStack(spacing: 10) {
                            ForEach(ColorToken.allCases, id: \.self) { color in
                                colorButton(color)
                            }
                        }

                        Text("label")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(NotebookLabelStyle.allCases) { labelStyle in
                                labelStyleButton(labelStyle)
                            }
                        }

                        Text("font")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(NotebookCoverFontStyle.allCases) { fontStyle in
                                fontStyleButton(fontStyle)
                            }
                        }

                        PhotosPicker(selection: $coverPhotoItem, matching: .images) {
                            Label("upload cover", systemImage: "photo.fill")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(.white.opacity(0.58), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .onChange(of: coverPhotoItem) { _, item in
                            loadCoverPhoto(item)
                        }

                        if liveNotebook.customCoverData != nil {
                            Button {
                                Haptics.softTap()
                                store.updateNotebookCoverImage(id: notebook.id, data: nil)
                            } label: {
                                Label("remove cover", systemImage: "trash")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(.white.opacity(0.48), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Haptics.success()
                    close()
                } label: {
                    Text("done")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(NotebookTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            }
        }
    }

    private func styleButton(_ style: NotebookCoverStyle) -> some View {
        Button {
            Haptics.selection()
            store.updateNotebookAppearance(id: notebook.id, style: style)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: style.symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(style.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(liveNotebook.coverStyle == style ? .white : NotebookTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(liveNotebook.coverStyle == style ? NotebookTheme.ink : .white.opacity(0.58), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorButton(_ color: ColorToken) -> some View {
        Button {
            Haptics.selection()
            store.updateNotebookAppearance(id: notebook.id, color: color)
        } label: {
            Circle()
                .fill(color == .graphite ? NotebookTheme.ink : NotebookTheme.accent(color))
                .frame(width: liveNotebook.coverColor == color ? 38 : 32, height: liveNotebook.coverColor == color ? 38 : 32)
                .overlay {
                    Circle().stroke(.white.opacity(0.78), lineWidth: 1)
                }
                .overlay {
                    if liveNotebook.coverColor == color {
                        Circle().stroke(NotebookTheme.ink.opacity(0.64), lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func labelStyleButton(_ labelStyle: NotebookLabelStyle) -> some View {
        Button {
            Haptics.selection()
            store.updateNotebookAppearance(id: notebook.id, labelStyle: labelStyle)
        } label: {
            Text(labelStyle.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(liveNotebook.coverLabelStyle == labelStyle ? .white : NotebookTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(liveNotebook.coverLabelStyle == labelStyle ? NotebookTheme.ink : .white.opacity(0.58), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fontStyleButton(_ fontStyle: NotebookCoverFontStyle) -> some View {
        Button {
            Haptics.selection()
            store.updateNotebookAppearance(id: notebook.id, fontStyle: fontStyle)
        } label: {
            Text(fontStyle.title)
                .font(fontStyle.previewFont)
                .foregroundStyle(liveNotebook.coverFontStyle == fontStyle ? .white : NotebookTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(liveNotebook.coverFontStyle == fontStyle ? NotebookTheme.ink : .white.opacity(0.58), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadCoverPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                Haptics.success()
                store.updateNotebookCoverImage(id: notebook.id, data: data)
            }
        }
    }

    private func cycleCoverLook() {
        let styles = NotebookCoverStyle.allCases
        let colors = ColorToken.allCases
        let labels = NotebookLabelStyle.allCases
        guard let styleIndex = styles.firstIndex(of: liveNotebook.coverStyle),
              let colorIndex = colors.firstIndex(of: liveNotebook.coverColor),
              let labelIndex = labels.firstIndex(of: liveNotebook.coverLabelStyle) else { return }
        store.updateNotebookAppearance(
            id: notebook.id,
            style: styles[(styleIndex + 1) % styles.count],
            color: colors[(colorIndex + 2) % colors.count],
            labelStyle: labels[(labelIndex + 1) % labels.count]
        )
    }

    private func close() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            closeRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            dismiss()
        }
    }
}

private struct CourseSuggestionBook: View {
    var subject: String
    var active: Bool
    var delay: Double
    var onSelect: () -> Void

    @State private var entered = false
    @State private var glow = false

    var body: some View {
        Button {
            Haptics.open()
            onSelect()
        } label: {
            ZStack(alignment: .topLeading) {
                CompositionCoverFace(
                    subject: subject,
                    cornerRadius: 16,
                    spineWidth: 14,
                    labelWidth: 58,
                    labelHeight: 46,
                    labelOffsetY: 16,
                    paperGrainDensity: 44
                )
                .overlay {
                    DirectionAwareTouchHighlight(
                        offset: CGSize(width: glow ? 18 : -14, height: glow ? -10 : 10),
                        isActive: active || glow,
                        cornerRadius: 16
                    )
                    .blendMode(.screen)
                    .opacity(active ? 0.36 : 0.18)
                }

                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .offset(x: 64, y: 80)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
            }
            .frame(width: 98, height: 128)
            .rotationEffect(.degrees(entered ? (active ? -2.4 : 1.4) : 7))
            .rotation3DEffect(.degrees(active ? 8 : -3), axis: (x: 0.16, y: 1, z: 0), perspective: 0.74)
            .scaleEffect(active ? 1.04 : 1)
            .offset(y: entered ? 0 : 18)
            .opacity(entered ? 1 : 0)
            .shadow(color: .black.opacity(active ? 0.2 : 0.12), radius: active ? 15 : 10, y: active ? 10 : 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("add \(subject)")
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84).delay(delay)) {
                entered = true
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true).delay(delay)) {
                glow = true
            }
        }
    }

    private var symbol: String {
        switch subject {
        case let text where text.contains("math") || text.contains("calculus") || text.contains("algebra") || text.contains("geometry"):
            return "function"
        case let text where text.contains("biology") || text.contains("anatomy"):
            return "leaf.fill"
        case let text where text.contains("chemistry"):
            return "atom"
        case let text where text.contains("physics"):
            return "scope"
        case let text where text.contains("computer") || text.contains("coding"):
            return "chevron.left.forwardslash.chevron.right"
        case let text where text.contains("history") || text.contains("government"):
            return "building.columns.fill"
        case let text where text.contains("english") || text.contains("literature") || text.contains("writing"):
            return "text.book.closed.fill"
        default:
            return "book.closed.fill"
        }
    }
}

private extension NotebookCoverFontStyle {
    var previewFont: Font {
        switch self {
        case .serif:
            return .system(.caption, design: .serif, weight: .semibold)
        case .rounded:
            return .system(.caption, design: .rounded, weight: .semibold)
        case .mono:
            return .system(.caption, design: .monospaced, weight: .semibold)
        case .handwritten:
            return .custom("MarkerFelt-Thin", size: 13)
        }
    }
}

private struct ShelfBackdrop: View {
    var subjectCount: Int

    var body: some View {
        VStack(spacing: subjectCount <= 2 ? 184 : 236) {
            ForEach(0..<max(1, Int(ceil(Double(max(subjectCount, 1)) / 2.0))), id: \.self) { row in
                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.09))
                        .frame(height: 18)
                        .blur(radius: 12)
                        .offset(y: 14)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.72, green: 0.68, blue: 0.58).opacity(0.22),
                                    .white.opacity(0.46),
                                    Color(red: 0.48, green: 0.45, blue: 0.38).opacity(0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 16)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.48), lineWidth: 0.8)
                        }
                }
                .opacity(row == 0 || subjectCount > 2 ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AccountOrb: View {
    var avatar: AvatarProfile

    var body: some View {
        ProfileAvatarView(avatar: avatar, size: 48, animated: true)
    }
}

private struct JournalHalo: View {
    var accent: Color
    var animated: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(accent.opacity(0.12))
                .frame(width: 264, height: 350)
                .blur(radius: 24)
                .scaleEffect(animated ? 1.04 : 0.96)
            Capsule()
                .stroke(accent.opacity(0.18), lineWidth: 1)
                .frame(width: 246, height: 332)
                .rotationEffect(.degrees(animated ? 2 : -2))
        }
        .allowsHitTesting(false)
    }
}

private struct MiniSignal: View {
    var text: String
    var systemName: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.58), lineWidth: 0.8)
        }
    }
}

private enum ActionLensKind: Hashable {
    case scan
    case search
    case review
    case model
    case open
    case add
}

private enum NextBestMoveKind: Hashable {
    case scan
    case review
    case model
    case open
    case add

    var actionLensKind: ActionLensKind {
        switch self {
        case .scan:
            return .scan
        case .review:
            return .review
        case .model:
            return .model
        case .open:
            return .open
        case .add:
            return .add
        }
    }
}

private struct NextBestMove {
    var kind: NextBestMoveKind
    var symbol: String
    var title: String
    var detail: String
    var tint: Color
    var score: Double
}

private struct ActionLensItem: Identifiable {
    var kind: ActionLensKind
    var symbol: String
    var label: String
    var tint: Color

    var id: ActionLensKind { kind }
}

private struct JournalCommandSurface: View {
    var notebook: SubjectNotebook?
    var move: NextBestMove
    var items: [ActionLensItem]
    var score: Double
    var awake: Bool
    var onPick: (ActionLensKind) -> Void

    @State private var primaryPressed = false

    private var title: String {
        notebook?.subject ?? "journal"
    }

    private var detail: String {
        switch move.kind {
        case .scan:
            return "capture notes into \(title)"
        case .review:
            return "review the page most likely to fade"
        case .model:
            return "rebuild sketches into study objects"
        case .open:
            return "open the current composition book"
        case .add:
            return "add a new course journal"
        }
    }

    private var auxiliaryItems: [ActionLensItem] {
        Array(items.filter { $0.kind != move.kind.actionLensKind }.prefix(3))
    }

    var body: some View {
        HStack(spacing: 11) {
            Button {
                Haptics.open()
                withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                    primaryPressed = true
                }
                onPick(move.kind.actionLensKind)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(190))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        primaryPressed = false
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(move.tint.opacity(0.2))
                    Circle()
                        .trim(from: 0, to: min(1, max(0.08, score)))
                        .stroke(
                            AngularGradient(
                                colors: [move.tint, NotebookTheme.accent(.blue), NotebookTheme.ink],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(awake ? -64 : -98))
                        .padding(4)
                    Circle()
                        .fill(move.tint)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: move.symbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .rotation3DEffect(.degrees(primaryPressed ? 15 : (awake ? 5 : -5)), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                }
                .frame(width: 62, height: 62)
                .scaleEffect(primaryPressed ? 0.92 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(move.title)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .lineLimit(1)
                    ContainerTextFlip(words: ["scan", "study", "review", "model", "listen", "recall", "focus", "practice"])
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(NotebookTheme.ink)

                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 2)

            HStack(spacing: 7) {
                ForEach(auxiliaryItems) { item in
                    ActionLensButton(item: item, awake: awake) {
                        Haptics.open()
                        onPick(item.kind)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.42), .clear, move.tint.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        .scaleEffect(awake ? 1 : 0.985)
    }
}

private struct MemoryMapRibbon: View {
    let map: StudyMemoryMap
    var awake: Bool
    var onPick: (StudyMemoryNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: max(0.2, map.score))
                        .stroke(.white.opacity(0.36), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 146 : -34))
                        .padding(6)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                Text("memory")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack {
                    MemoryThread(count: map.nodes.count, awake: awake)
                        .frame(height: 76)
                        .padding(.horizontal, 28)

                    HStack(spacing: 14) {
                        ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                            MemoryNodeBubble(node: node, awake: awake, index: index) {
                                onPick(node)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 13, y: 8)
    }
}

private struct MemoryThread: View {
    let count: Int
    var awake: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard count > 1 else { return }
            let spacing = size.width / CGFloat(max(count - 1, 1))
            var path = Path()
            for index in 0..<count {
                let phase = CGFloat(index) / CGFloat(max(count - 1, 1))
                let x = CGFloat(index) * spacing
                let y = size.height * (index.isMultiple(of: 2) ? 0.42 : 0.58) + (awake ? sin(phase * .pi * 2) * 3 : 0)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addQuadCurve(to: point, control: CGPoint(x: x - spacing * 0.45, y: size.height * 0.5))
                }
            }
            context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.14)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

private struct MemoryNodeBubble: View {
    let node: StudyMemoryNode
    var awake: Bool
    var index: Int
    var action: () -> Void
    @State private var pressed = false

    private var diameter: CGFloat {
        54 + CGFloat(min(1, max(0, node.weight))) * 18
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    pressed = false
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(node.tint).opacity(0.16))
                        .blur(radius: 1.5)
                    Circle()
                        .fill(.white.opacity(0.58))
                    Circle()
                        .stroke(NotebookTheme.accent(node.tint).opacity(0.3), lineWidth: 1)
                    Circle()
                        .trim(from: 0.1, to: 0.28 + node.weight * 0.5)
                        .stroke(NotebookTheme.accent(node.tint), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 118 + Double(index * 18) : -24))
                        .padding(7)
                    Image(systemName: node.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .rotation3DEffect(.degrees(pressed ? 12 : (awake ? 5 : -5)), axis: (x: 0.3, y: 1, z: 0), perspective: 0.8)
                }
                .frame(width: diameter, height: diameter)
                .scaleEffect(pressed ? 0.93 : (awake ? 1.025 : 0.98))
                .offset(y: index.isMultiple(of: 2) ? -2 : 3)

                Text(node.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.title)
    }
}

private struct ModelReadinessCapsule: View {
    let page: NotebookPage
    let readiness: ModelReadiness
    var awake: Bool
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(170))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(readiness.tint).opacity(0.16))
                    Circle()
                        .trim(from: 0, to: max(0.08, readiness.score))
                        .stroke(NotebookTheme.accent(readiness.tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(awake ? -78 : -98))
                    Image(systemName: readiness.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .rotation3DEffect(.degrees(awake ? 9 : -9), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text(readiness.action)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text("\(page.title.lowercased())  \(readiness.reason)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 0)

                ModelSparkline(score: readiness.score, color: NotebookTheme.accent(readiness.tint), awake: awake)
                    .frame(width: 58, height: 34)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.64), lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.98 : 1)
            .shadow(color: .black.opacity(0.07), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(readiness.action)
    }
}

private struct PresentationRunwayPanel: View {
    let runway: PresentationRunway
    let avatar: AvatarProfile
    var awake: Bool
    var onPick: (PresentationRunwayStep) -> Void
    @State private var pressedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ZStack {
                    ProfileAvatarView(avatar: avatar, size: 42, animated: true)
                    Circle()
                        .trim(from: 0.04, to: max(0.14, runway.score))
                        .stroke(NotebookTheme.ink.opacity(0.68), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 128 : -32))
                        .frame(width: 54, height: 54)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(runway.title)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(runway.detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                RunwayPulse(score: runway.score, awake: awake)
                    .frame(width: 54, height: 34)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(runway.steps.enumerated()), id: \.element.id) { index, step in
                        RunwayStepOrb(
                            step: step,
                            awake: awake,
                            index: index,
                            pressed: pressedID == step.id
                        ) {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                pressedID = step.id
                            }
                            onPick(step)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(160))
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    pressedID = nil
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 8)
        .accessibilityLabel("runway")
    }
}

private struct RunwayStepOrb: View {
    let step: PresentationRunwayStep
    var awake: Bool
    var index: Int
    var pressed: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(step.tint).opacity(step.isReady ? 0.22 : 0.12))
                        .blur(radius: 2)
                    Circle()
                        .fill(step.isReady ? .white.opacity(0.62) : .white.opacity(0.44))
                    Circle()
                        .trim(from: 0.08, to: 0.08 + min(0.76, max(0.12, step.weight * 0.76)))
                        .stroke(NotebookTheme.accent(step.tint), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 114 + Double(index * 17) : -28))
                        .padding(6)
                    Image(systemName: step.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .rotation3DEffect(.degrees(pressed ? 14 : (awake ? 6 : -6)), axis: (x: 0.2, y: 1, z: 0), perspective: 0.78)
                }
                .frame(width: 58, height: 58)
                .scaleEffect(pressed ? 0.92 : (awake ? 1.025 : 0.98))
                .offset(y: index.isMultiple(of: 2) ? -1 : 3)

                VStack(spacing: 1) {
                    Text(step.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.8))
                        .lineLimit(1)
                    Text(step.detail)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step.title)
    }
}

private struct RunwayPulse: View {
    var score: Double
    var awake: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let points = 7
            var path = Path()
            for index in 0..<points {
                let phase = Double(index) / Double(points - 1)
                let wave = sin(phase * .pi * 2 + (awake ? 0.46 : -0.46))
                let x = size.width * phase
                let y = size.height * (0.7 - score * 0.34) + wave * 3.2
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addQuadCurve(to: point, control: CGPoint(x: x - size.width / CGFloat(points), y: size.height * 0.5))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 1.7, y: y - 1.7, width: 3.4, height: 3.4)), with: .color(NotebookTheme.ink.opacity(0.42)))
            }
            context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.52)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct DailyBriefStrip: View {
    let brief: StudyDailyBrief
    var awake: Bool
    var onPick: (StudyBriefItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: max(0.12, brief.score))
                        .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 132 : -42))
                        .padding(6)
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                Text(brief.title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(brief.items.enumerated()), id: \.element.id) { index, item in
                        DailyBriefChip(item: item, awake: awake) {
                            onPick(item)
                        }
                        .offset(y: awake ? 0 : 5)
                        .animation(.spring(response: 0.44, dampingFraction: 0.84).delay(Double(index) * 0.04), value: awake)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 12, y: 7)
    }
}

private struct DailyBriefChip: View {
    let item: StudyBriefItem
    var awake: Bool
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(item.tint))
                    Circle()
                        .trim(from: 0.08, to: 0.32)
                        .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 96 : -18))
                        .padding(5)
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(item.value)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(width: 112, height: 48, alignment: .leading)
            .background(.white.opacity(0.52), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.66), lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

private struct AutopilotCapsule: View {
    let plan: StudyAutopilotPlan
    var awake: Bool
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: 0.32)
                        .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 138 : -28))
                        .padding(7)
                    Image(systemName: plan.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .scaleEffect(pressed ? 0.94 : (awake ? 1.03 : 0.98))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(1)
                        Text("\(Int((plan.score * 100).rounded()))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(NotebookTheme.accent(plan.tint).opacity(0.14), in: Capsule())
                    }

                    Text(plan.detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    ForEach(plan.steps.prefix(3)) { step in
                        ZStack {
                            Circle()
                                .fill(step.done ? NotebookTheme.ink : NotebookTheme.accent(plan.tint).opacity(0.18))
                                .frame(width: 26, height: 26)
                            Image(systemName: step.done ? "checkmark" : step.symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.done ? .white : NotebookTheme.ink)
                        }
                        .offset(y: awake ? 0 : 3)
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(0.58), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.72), lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.985 : 1)
            .shadow(color: NotebookTheme.accent(plan.tint).opacity(0.12), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.title)
    }
}

private struct ModelSparkline: View {
    let score: Double
    let color: Color
    var awake: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let points = 8
            var path = Path()
            for index in 0..<points {
                let phase = Double(index) / Double(points - 1)
                let wave = sin(phase * .pi * 2 + (awake ? 0.5 : -0.5))
                let x = size.width * phase
                let y = size.height * (0.68 - score * 0.34) + wave * 3.4
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
                context.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)), with: .color(color.opacity(0.72)))
            }
            context.stroke(path, with: .color(color.opacity(0.78)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct ActionLensButton: View {
    var item: ActionLensItem
    var awake: Bool
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(170))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    pressed = false
                }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(item.tint.opacity(pressed ? 0.92 : 1))
                    Circle()
                        .trim(from: 0.12, to: 0.36)
                        .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 128 : -18))
                        .padding(6)
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 43, height: 43)
                Text(item.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 50)
            .scaleEffect(pressed ? 0.92 : (awake ? 1.02 : 0.98))
            .rotation3DEffect(.degrees(pressed ? 9 : 0), axis: (x: 1, y: 0.4, z: 0), perspective: 0.8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
    }
}

private struct HomeDoodleLayer: View {
    var animated: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas(rendersAsynchronously: true) { context, size in
                let ink = NotebookTheme.ink.opacity(0.12)
                let orange = Color(red: 1.0, green: 0.47, blue: 0.16).opacity(0.16)
                let offset = animated ? CGFloat(8) : CGFloat(-8)

                drawLoop(in: &context, at: CGPoint(x: size.width * 0.12, y: 112 + offset), color: ink)
                drawArrow(in: &context, from: CGPoint(x: size.width * 0.82, y: 148 - offset), color: orange)
                drawSpark(in: &context, at: CGPoint(x: size.width * 0.16, y: size.height * 0.62), color: orange)
                drawFormula(in: &context, at: CGPoint(x: size.width * 0.72, y: size.height * 0.72 + offset), color: ink)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func drawLoop(in context: inout GraphicsContext, at point: CGPoint, color: Color) {
        var path = Path()
        path.move(to: point)
        path.addCurve(
            to: CGPoint(x: point.x + 52, y: point.y + 6),
            control1: CGPoint(x: point.x + 10, y: point.y - 28),
            control2: CGPoint(x: point.x + 42, y: point.y - 28)
        )
        path.addCurve(
            to: CGPoint(x: point.x + 4, y: point.y + 20),
            control1: CGPoint(x: point.x + 50, y: point.y + 38),
            control2: CGPoint(x: point.x + 12, y: point.y + 40)
        )
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private func drawArrow(in context: inout GraphicsContext, from point: CGPoint, color: Color) {
        var path = Path()
        path.move(to: point)
        path.addCurve(
            to: CGPoint(x: point.x + 44, y: point.y + 30),
            control1: CGPoint(x: point.x + 16, y: point.y - 8),
            control2: CGPoint(x: point.x + 34, y: point.y + 8)
        )
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        var head = Path()
        head.move(to: CGPoint(x: point.x + 34, y: point.y + 31))
        head.addLine(to: CGPoint(x: point.x + 45, y: point.y + 30))
        head.addLine(to: CGPoint(x: point.x + 41, y: point.y + 19))
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private func drawSpark(in context: inout GraphicsContext, at point: CGPoint, color: Color) {
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2
            var path = Path()
            path.move(to: CGPoint(x: point.x + cos(angle) * 4, y: point.y + sin(angle) * 4))
            path.addLine(to: CGPoint(x: point.x + cos(angle) * 20, y: point.y + sin(angle) * 20))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }

    private func drawFormula(in context: inout GraphicsContext, at point: CGPoint, color: Color) {
        let text = Text("scan  study")
            .font(.system(size: 14, weight: .semibold, design: .serif))
            .foregroundStyle(color)
        context.draw(text, at: point)
    }
}
