import SwiftUI

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
    @State private var selectedJournalIndex = 0
    @State private var journalDragOffset: CGFloat = 0
    @State private var doodleDrift = false
    @State private var modelReadyPulse = false
    @State private var actionLensAwake = false
    private let allowedSubjects = [
        "math", "pre algebra", "algebra", "geometry", "trigonometry", "precalculus", "calculus", "statistics",
        "science", "biology", "chemistry", "physics", "environmental science", "earth science", "anatomy",
        "history", "world history", "us history", "european history", "government", "civics",
        "english", "literature", "writing", "creative writing", "spanish", "french", "latin",
        "computer science", "coding", "data science", "robotics", "economics", "psychology", "sociology",
        "art", "music", "theater", "health", "business", "engineering"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                header
                journalCarousel
                shelfNotes
                actionLens
                quickDock
                modelReadyToast
                reviewPulseStrip
            }
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()
                HomeDoodleLayer(animated: doodleDrift)
                    .ignoresSafeArea()
            }
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
                .presentationDetents([.height(430)])
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
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                doodleDrift = true
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                actionLensAwake = true
            }
        }
    }

    private var header: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.34))
                .frame(width: 92, height: 92)
                .blur(radius: 18)
                .scaleEffect(sparkleSpin ? 1.08 : 0.92)

            MinimalAppLogo()
                .frame(width: 68, height: 68)
                .rotation3DEffect(.degrees(sparkleSpin ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                .scaleEffect(sparkleSpin ? 1.02 : 0.98)

            HStack {
                Button {
                    Haptics.open()
                    showingCourseComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
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
            let cardWidth = min(proxy.size.width * (store.notebooks.count == 1 ? 0.86 : 0.76), 356)

            ZStack(alignment: .top) {
                ShelfBackdrop(subjectCount: store.notebooks.count)
                    .padding(.horizontal, 30)
                    .padding(.top, 350)

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
                .frame(height: 478)
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

                journalIndexRail
                    .padding(.top, 478)
            }
        }
        .frame(height: 526)
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

    private var shelfNotes: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("vellum")
                    .font(.system(.callout, design: .serif, weight: .semibold))
                ContainerTextFlip(words: ["scan", "sort", "study", "listen", "remember", "rebuild", "review", "focus", "recall", "diagram", "practice", "master"])
            }
            .foregroundStyle(NotebookTheme.ink.opacity(0.78))

            HStack(spacing: 10) {
                MiniSignal(text: "\(store.notebooks.count) journals", systemName: "books.vertical.fill")
                MiniSignal(text: activeJournalText, systemName: "sparkle.magnifyingglass")
            }
        }
        .padding(.horizontal, 20)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 10)
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

    private var recommendedPage: NotebookPage? {
        store.reviewQueue(limit: 1).first
    }

    private var modelCandidatePage: NotebookPage? {
        activeNotebook?.pages.first { $0.content.models.isEmpty } ?? activeNotebook?.pages.first ?? recommendedPage
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

    private var actionLensScore: Double {
        let pages = store.notebooks.flatMap(\.pages)
        guard !pages.isEmpty else { return 0.18 }
        let clarity = pages.reduce(0) { $0 + $1.content.insight.clarityScore } / Double(pages.count)
        let progress = store.notebooks.isEmpty ? 0 : store.notebooks.reduce(0) { $0 + $1.progress } / Double(store.notebooks.count)
        let reviews = min(1, Double(pages.reduce(0) { $0 + $1.studyState.reviewCount }) / Double(max(pages.count * 2, 1)))
        return min(1, max(0.12, clarity * 0.46 + progress * 0.34 + reviews * 0.2))
    }

    private var actionLens: some View {
        HStack(spacing: 12) {
            ActionLensMeter(score: actionLensScore, awake: actionLensAwake)
                .frame(width: 58, height: 58)

            HStack(spacing: 9) {
                ForEach(actionLensItems) { item in
                    ActionLensButton(item: item, awake: actionLensAwake) {
                        performActionLens(item.kind)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
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
            Haptics.open()
            showingCourseComposer = true
        }
    }

    private var quickDock: some View {
        HStack(spacing: 12) {
            QuickDockButton(symbol: "viewfinder", tint: NotebookTheme.ink, disabled: activeNotebook == nil || quickScanning) {
                Haptics.open()
                showingQuickScanner = true
            }

            QuickDockButton(symbol: "brain.head.profile", tint: NotebookTheme.accent(.plum), disabled: recommendedPage == nil) {
                if let page = recommendedPage {
                    Haptics.open()
                    selectedStudyPage = page
                }
            }

            QuickDockButton(symbol: "cube.transparent", tint: NotebookTheme.accent(.blue), disabled: modelCandidatePage == nil) {
                if let page = modelCandidatePage {
                    Haptics.success()
                    openGeneratedModel(for: page)
                }
            }

            QuickDockButton(symbol: "sparkles", tint: NotebookTheme.accent(.green), disabled: activeNotebook == nil) {
                if let notebook = activeNotebook {
                    Haptics.open()
                    selectedNotebook = store.notebook(with: notebook.id) ?? notebook
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 14)
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
                                .frame(width: 50, height: 50)
                        }
                        .buttonStyle(FloatingCircleButtonStyle())
                        .disabled(bestCourseMatch == nil)
                        .padding(.bottom, 1)
                    }

                    VStack(spacing: 8) {
                        ForEach(courseSuggestions, id: \.self) { subject in
                            Button {
                                Haptics.selection()
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                    courseDraft = subject
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(NotebookTheme.ink, in: Circle())
                                    Text(subject)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(NotebookTheme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.white.opacity(0.58), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(response: 0.5, dampingFraction: 0.84), value: courseSuggestions)
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
        let draft = courseDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let availableSubjects = allowedSubjects.filter { subject in
            !store.notebooks.contains(where: { $0.subject == subject })
        }
        guard !draft.isEmpty else {
            let featured = ["biology", "math", "computer science", "chemistry", "history", "english"]
            return featured.filter { availableSubjects.contains($0) } + Array(availableSubjects.filter { !featured.contains($0) }.prefix(2))
        }
        let matches = availableSubjects.filter { subject in
            subject.hasPrefix(draft) || subject.localizedCaseInsensitiveContains(draft)
        }
        return Array(matches.prefix(4))
    }

    private var bestCourseMatch: String? {
        let draft = courseDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !draft.isEmpty else { return nil }
        if allowedSubjects.contains(draft), !store.notebooks.contains(where: { $0.subject == draft }) { return draft }
        return allowedSubjects.first { subject in
            !store.notebooks.contains(where: { $0.subject == subject }) && subject.hasPrefix(draft)
        }
    }

    private func addCourse() {
        guard let subject = bestCourseMatch else { return }
        Haptics.success()
        store.addCourse(subject)
        courseDraft = ""
        showingCourseComposer = false
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

private struct ActionLensItem: Identifiable {
    var kind: ActionLensKind
    var symbol: String
    var label: String
    var tint: Color

    var id: ActionLensKind { kind }
}

private struct ActionLensMeter: View {
    var score: Double
    var awake: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.42))
            Circle()
                .trim(from: 0, to: min(1, max(0, score)))
                .stroke(
                    AngularGradient(
                        colors: [
                            NotebookTheme.accent(.green),
                            NotebookTheme.accent(.blue),
                            NotebookTheme.ink
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + (awake ? 8 : -8)))
                .padding(5)
            Circle()
                .fill(NotebookTheme.ink)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(awake ? 1.04 : 0.96)
        }
        .accessibilityLabel("study readiness")
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

private struct QuickDockButton: View {
    let symbol: String
    let tint: Color
    var disabled = false
    var action: () -> Void

    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint.opacity(disabled ? 0.28 : 1))
                Circle()
                    .trim(from: 0.06, to: 0.28)
                    .stroke(.white.opacity(disabled ? 0.16 : 0.34), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    .rotationEffect(.degrees(breathe ? 120 : -24))
                    .padding(6)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(disabled ? 0.48 : 1))
            }
            .frame(width: 52, height: 52)
            .scaleEffect(breathe && !disabled ? 1.025 : 0.985)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

private struct ReviewSprintView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var gradedIDs: Set<NotebookPage.ID> = []
    @State private var cardTilt = false
    var onOpen: (NotebookPage) -> Void

    private var queue: [NotebookPage] {
        store.reviewQueue(limit: 6)
    }

    private var remainingQueue: [NotebookPage] {
        queue.filter { !gradedIDs.contains($0.id) }
    }

    private var currentPage: NotebookPage? {
        guard !remainingQueue.isEmpty else { return nil }
        return remainingQueue[min(index, remainingQueue.count - 1)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()

                VStack(spacing: 16) {
                    sprintHeader

                    if let page = currentPage {
                        sprintCard(page)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        completeCard
                    }

                    progressDots
                }
                .padding(20)
            }
            .navigationTitle("sprint")
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
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    cardTilt = true
                }
            }
        }
    }

    private var sprintHeader: some View {
        GlassSurface(radius: 28, padding: 14, interactive: true) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.05, to: 0.34)
                        .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(cardTilt ? 130 : -28))
                        .padding(6)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(max(0, remainingQueue.count)) left")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text("grade and move")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                }

                Spacer()
            }
        }
    }

    private func sprintCard(_ page: NotebookPage) -> some View {
        NotebookPaperView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: page.content.models.isEmpty ? "doc.text.magnifyingglass" : "cube.transparent")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(NotebookTheme.ink, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title.lowercased())
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(1)
                        Text(page.studyState.dueLabel)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(NotebookTheme.muted)
                    }
                    Spacer()
                }

                Text(page.content.insight.onlyWhatMatters.isEmpty ? firstUsefulLine(page) : page.content.insight.onlyWhatMatters)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineSpacing(5)
                    .lineLimit(5)

                if let prompt = (page.content.insight.recallPrompts + page.content.insight.quickQuestions).first {
                    Text(prompt)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.5), in: Capsule())
                }

                HStack(spacing: 9) {
                    ForEach(ReviewGrade.allCases) { grade in
                        SprintGradeButton(grade: grade) {
                            gradePage(page, grade: grade)
                        }
                    }
                }

                Button {
                    Haptics.open()
                    onOpen(page)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                        Text("open")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(NotebookTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .rotation3DEffect(.degrees(cardTilt ? 2 : -2), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: currentPage?.id)
    }

    private var completeCard: some View {
        GlassSurface(radius: 30, padding: 20, interactive: true) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(NotebookTheme.accent(.green), in: Circle())
                Text("done")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Button {
                    Haptics.success()
                    dismiss()
                } label: {
                    Text("close")
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

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, min(6, queue.count)), id: \.self) { dot in
                Capsule()
                    .fill(dot < gradedIDs.count ? NotebookTheme.accent(.green) : NotebookTheme.ink.opacity(0.16))
                    .frame(width: dot == gradedIDs.count ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.32, dampingFraction: 0.8), value: gradedIDs.count)
            }
        }
        .padding(.vertical, 6)
    }

    private func gradePage(_ page: NotebookPage, grade: ReviewGrade) {
        Haptics.success()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            store.recordReview(pageID: page.id, grade: grade)
            gradedIDs.insert(page.id)
            index = 0
        }
    }

    private func firstUsefulLine(_ page: NotebookPage) -> String {
        page.content.cleanedText
            .split(separator: "\n")
            .map(String.init)
            .first?
            .lowercased() ?? "review this page once."
    }
}

private struct SprintGradeButton: View {
    var grade: ReviewGrade
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: grade.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: Circle())
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch grade {
        case .forgot: "again"
        case .hard: "hard"
        case .good: "good"
        case .easy: "easy"
        }
    }

    private var tint: Color {
        switch grade {
        case .forgot: NotebookTheme.redRule
        case .hard: NotebookTheme.accent(.amber)
        case .good: NotebookTheme.accent(.green)
        case .easy: NotebookTheme.accent(.blue)
        }
    }
}

private struct SmartSearchView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pulse = false
    var onOpen: (NotebookPage) -> Void
    var onModel: (NotebookPage) -> Void

    private var results: [SmartSearchResult] {
        SmartSearchIndex.results(in: store.notebooks, query: query)
    }

    private var suggestions: [String] {
        SmartSearchIndex.suggestions(in: store.notebooks)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()

                VStack(spacing: 16) {
                    GlassSurface(radius: 30, padding: 16, interactive: true) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(NotebookTheme.ink)
                                Circle()
                                    .trim(from: 0.12, to: 0.4)
                                    .stroke(.white.opacity(0.32), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                                    .rotationEffect(.degrees(pulse ? 140 : -28))
                                    .padding(6)
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 46, height: 46)

                            GooeyInput(label: nil, systemName: nil, text: $query)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        suggestionShelf
                    } else {
                        resultList
                    }
                }
            }
            .navigationTitle("find")
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
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var suggestionShelf: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                        query = suggestion
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(suggestion)
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                    }
                                    .foregroundStyle(NotebookTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(.white.opacity(0.58), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(SmartSearchIndex.recent(in: store.notebooks)) { result in
                        SmartSearchResultRow(result: result, onOpen: open, onModel: makeModel)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 26)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if results.isEmpty {
                    GlassSurface(radius: 24, padding: 16, interactive: true) {
                        HStack(spacing: 12) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(NotebookTheme.ink, in: Circle())
                            Text("no match")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(NotebookTheme.ink)
                            Spacer()
                        }
                    }
                } else {
                    ForEach(results) { result in
                        SmartSearchResultRow(result: result, onOpen: open, onModel: makeModel)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: results.map(\.id))
    }

    private func open(_ page: NotebookPage) {
        Haptics.open()
        dismiss()
        onOpen(page)
    }

    private func makeModel(_ page: NotebookPage) {
        Haptics.success()
        dismiss()
        onModel(page)
    }
}

private struct SmartSearchResultRow: View {
    var result: SmartSearchResult
    var onOpen: (NotebookPage) -> Void
    var onModel: (NotebookPage) -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            onOpen(result.page)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(result.tint)
                    Image(systemName: result.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                    Text(result.snippet)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    onModel(result.page)
                } label: {
                    Image(systemName: result.page.content.models.isEmpty ? "cube.transparent" : "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(NotebookTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 0.8)
            }
            .scaleEffect(pressed ? 0.985 : 1)
            .rotation3DEffect(.degrees(pressed ? 2.5 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.72)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { Haptics.softTap() }
                    pressed = true
                }
                .onEnded { _ in
                    pressed = false
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: pressed)
    }
}

private struct SmartSearchResult: Identifiable, Hashable {
    var id: NotebookPage.ID
    var page: NotebookPage
    var subject: String
    var title: String
    var snippet: String
    var score: Int
    var tint: Color
    var symbol: String

    static func == (lhs: SmartSearchResult, rhs: SmartSearchResult) -> Bool {
        lhs.id == rhs.id && lhs.score == rhs.score && lhs.snippet == rhs.snippet
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(score)
        hasher.combine(snippet)
    }
}

private enum SmartSearchIndex {
    static func results(in notebooks: [SubjectNotebook], query: String) -> [SmartSearchResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return recent(in: notebooks) }

        return notebooks.flatMap { notebook in
            notebook.pages.compactMap { page in
                let searchable = searchableText(page: page, subject: notebook.subject)
                let score = terms.reduce(0) { partial, term in
                    partial + weightedScore(term: term, in: searchable, page: page, subject: notebook.subject)
                }
                guard score > 0 else { return nil }
                return SmartSearchResult(
                    id: page.id,
                    page: page,
                    subject: notebook.subject,
                    title: "\(notebook.subject) \(page.title.lowercased())",
                    snippet: snippet(for: terms, page: page),
                    score: score,
                    tint: NotebookTheme.accent(notebook.accent),
                    symbol: symbol(for: page)
                )
            }
        }
        .sorted { first, second in
            if first.score == second.score {
                return first.page.createdAt > second.page.createdAt
            }
            return first.score > second.score
        }
        .prefix(12)
        .map(\.self)
    }

    static func recent(in notebooks: [SubjectNotebook]) -> [SmartSearchResult] {
        notebooks.flatMap { notebook in
            notebook.pages.prefix(3).map { page in
                SmartSearchResult(
                    id: page.id,
                    page: page,
                    subject: notebook.subject,
                    title: "\(notebook.subject) \(page.title.lowercased())",
                    snippet: page.content.insight.onlyWhatMatters.isEmpty ? firstLine(page.content.cleanedText) : page.content.insight.onlyWhatMatters,
                    score: 1,
                    tint: NotebookTheme.accent(notebook.accent),
                    symbol: symbol(for: page)
                )
            }
        }
        .sorted { $0.page.createdAt > $1.page.createdAt }
        .prefix(6)
        .map(\.self)
    }

    static func suggestions(in notebooks: [SubjectNotebook]) -> [String] {
        var seen = Set<String>()
        let terms = notebooks.flatMap(\.pages).flatMap { page in
            page.content.keywords + page.content.formulas + page.content.models.flatMap { ($0.nodes ?? $0.terms) }
        }
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 2 && seen.insert($0).inserted }
            .prefix(12)
            .map(\.self)
    }

    private static func searchableText(page: NotebookPage, subject: String) -> String {
        let tableText = page.content.tables
            .map { table in
                let rowText = table.rows.map { $0.joined(separator: " ") }.joined(separator: " ")
                return (table.headers.joined(separator: " ") + " " + rowText).lowercased()
            }
            .joined(separator: " ")
        let modelText = page.content.models
            .map { model in
                (model.terms + (model.nodes ?? [])).joined(separator: " ")
            }
            .joined(separator: " ")
        let pieces: [String] = [
            subject,
            page.title,
            page.content.cleanedText,
            page.content.rawText,
            page.content.keywords.joined(separator: " "),
            page.content.formulas.joined(separator: " "),
            tableText,
            modelText
        ]
        return pieces.joined(separator: " ").lowercased()
    }

    private static func weightedScore(term: String, in searchable: String, page: NotebookPage, subject: String) -> Int {
        guard searchable.contains(term) else { return 0 }
        var score = 1
        if subject.contains(term) { score += 5 }
        if page.title.lowercased().contains(term) { score += 4 }
        if page.content.keywords.contains(where: { $0.lowercased().contains(term) }) { score += 3 }
        if page.content.formulas.contains(where: { $0.lowercased().contains(term) }) { score += 3 }
        let modelNodes = page.content.models.flatMap { model in
            model.nodes ?? model.terms
        }
        if modelNodes.contains(where: { $0.lowercased().contains(term) }) { score += 3 }
        return score
    }

    private static func snippet(for terms: [String], page: NotebookPage) -> String {
        let lines = (page.content.cleanedText + "\n" + page.content.insight.onlyWhatMatters)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return lines.first { line in
            terms.contains { line.contains($0) }
        } ?? firstLine(page.content.cleanedText)
    }

    private static func firstLine(_ text: String) -> String {
        text
            .split(separator: "\n")
            .map(String.init)
            .first?
            .lowercased() ?? "saved page"
    }

    private static func symbol(for page: NotebookPage) -> String {
        if !page.content.models.isEmpty { return "cube.transparent" }
        if !page.content.tables.isEmpty { return "tablecells" }
        if !page.content.formulas.isEmpty { return "function" }
        return "doc.text.magnifyingglass"
    }
}

private struct AccountCenterView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var legalDocument: LegalDocument?
    @State private var editingAvatar = false
    @State private var expanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassSurface(radius: 30, padding: 18, interactive: true) {
                        HStack(spacing: 14) {
                            Button {
                                Haptics.open()
                                editingAvatar = true
                            } label: {
                                ProfileAvatarView(avatar: store.user.avatar, size: 62, animated: true)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(NotebookTheme.ink, in: Circle())
                                    }
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.user.name.lowercased())
                                    .font(.system(.title3, design: .serif, weight: .semibold))
                                    .foregroundStyle(NotebookTheme.ink)
                                Text(store.authSession?.email ?? "student")
                                    .font(.system(.footnote, design: .rounded, weight: .medium))
                                    .foregroundStyle(NotebookTheme.muted)
                            }
                            Spacer()
                        }
                    }
                    .scaleEffect(expanded ? 1 : 0.96)
                    .opacity(expanded ? 1 : 0)

                    accountSection("notebooks") {
                        accountRow(systemName: "books.vertical.fill", title: "\(store.notebooks.count) journals", detail: "\(store.notebooks.reduce(0) { $0 + $1.pages.count }) pages")
                        accountRow(systemName: "mic.fill", title: "personal voice", detail: store.voiceProfile.isPersonalized ? "ready" : "not set")
                    }

                    accountSection("study") {
                        accountRow(systemName: "rectangle.stack.fill", title: "\(flashcardCount) flashcards", detail: "ready from scanned pages")
                        accountRow(systemName: "cube.transparent", title: "\(modelCount) models", detail: "interactive diagrams found")
                        accountRow(systemName: "text.magnifyingglass", title: "\(keywordCount) keywords", detail: "searchable across journals")
                    }

                    accountSection("insights") {
                        accountRow(systemName: "flame.fill", title: "\(studyStreak) day streak", detail: "from saved pages")
                        accountRow(systemName: "checkmark.seal.fill", title: "\(reviewCount) reviews", detail: "graded flashcards")
                        accountRow(systemName: "sparkles", title: strongestSubject, detail: "strongest journal")
                    }

                    accountSection("preferences") {
                        Toggle("personal voice", isOn: Bindable(store).voiceProfile.wantsPersonalVoice)
                            .tint(NotebookTheme.ink)
                        Button {
                            Haptics.open()
                            editingAvatar = true
                        } label: {
                            accountRow(systemName: "person.crop.circle.fill", title: "profile picture", detail: "build your own avatar")
                        }
                        .buttonStyle(.plain)
                    }

                    accountSection("legal") {
                        legalButton(.terms)
                        legalButton(.privacy)
                    }

                    Button {
                        Haptics.warning()
                        dismiss()
                        store.signOut()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .bold))
                            Text("sign out")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(NotebookTheme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(LivingPaperBackground().ignoresSafeArea())
            .navigationTitle("account")
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
            .sheet(item: $legalDocument) { document in
                LegalDocumentView(document: document)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $editingAvatar) {
                AvatarBuilderView()
                    .presentationDetents([.height(560), .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                    expanded = true
                }
            }
        }
    }

    private func accountSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassSurface(radius: 24, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                content()
                    .font(.system(.body, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(expanded ? 1 : 0)
        .offset(y: expanded ? 0 : 12)
    }

    private func accountRow(systemName: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(NotebookTheme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }
            Spacer()
        }
    }

    private func legalButton(_ document: LegalDocument) -> some View {
        Button {
            Haptics.open()
            legalDocument = document
        } label: {
            accountRow(
                systemName: document == .terms ? "doc.text.fill" : "hand.raised.fill",
                title: document.title,
                detail: document.summary
            )
        }
        .buttonStyle(.plain)
    }

    private var flashcardCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { count, page in
            count + max(1, page.content.sections.count)
        }
    }

    private var modelCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { $0 + $1.content.models.count }
    }

    private var keywordCount: Int {
        Set(store.notebooks.flatMap(\.pages).flatMap(\.content.keywords)).count
    }

    private var reviewCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { $0 + $1.studyState.reviewCount }
    }

    private var strongestSubject: String {
        store.notebooks.max { first, second in
            first.progress < second.progress
        }?.subject ?? "none"
    }

    private var studyStreak: Int {
        let calendar = Calendar.current
        let days = Set(store.notebooks.flatMap(\.pages).map { calendar.startOfDay(for: $0.createdAt) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var day = calendar.startOfDay(for: .now)
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}

private struct AvatarBuilderView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AvatarProfile.default
    @State private var previewPulse = false

    private let symbols = ["book.closed.fill", "pencil.and.scribble", "sparkles", "brain.head.profile", "cube.transparent", "graduationcap.fill", "atom", "function", "paintpalette.fill"]

    var body: some View {
        NavigationStack {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(NotebookTheme.accent(draft.base).opacity(0.12))
                                .frame(width: 196, height: 196)
                                .blur(radius: 22)
                                .scaleEffect(previewPulse ? 1.08 : 0.94)
                            ProfileAvatarView(avatar: draft, size: 132, animated: true)
                                .scaleEffect(previewPulse ? 1.02 : 0.98)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        avatarSection("color") {
                            HStack(spacing: 12) {
                                ForEach(ColorToken.allCases, id: \.self) { token in
                                    avatarColorButton(token, selected: draft.base == token) {
                                        draft.base = token
                                    }
                                }
                            }
                        }

                        avatarSection("highlight") {
                            HStack(spacing: 12) {
                                ForEach(ColorToken.allCases, id: \.self) { token in
                                    avatarColorButton(token, selected: draft.accent == token) {
                                        draft.accent = token
                                    }
                                }
                            }
                        }

                        avatarSection("mark") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(symbols, id: \.self) { symbol in
                                    avatarChoiceButton(active: draft.symbol == symbol) {
                                        draft.symbol = symbol
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 19, weight: .semibold))
                                    }
                                }
                            }
                        }

                        avatarSection("texture") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(AvatarDetail.allCases) { detail in
                                    avatarChoiceButton(active: draft.detail == detail) {
                                        draft.detail = detail
                                    } label: {
                                        Text(detail.rawValue)
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                Haptics.selection()
                                store.randomizeAvatar()
                                draft = store.user.avatar
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))

                            Button {
                                Haptics.success()
                                store.updateAvatar(draft)
                                dismiss()
                            } label: {
                                Text("save avatar")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(NotebookTheme.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("avatar")
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
                draft = store.user.avatar
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    previewPulse = true
                }
            }
        }
    }

    private func avatarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassSurface(radius: 24, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func avatarColorButton(_ token: ColorToken, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            Circle()
                .fill(NotebookTheme.accent(token))
                .frame(width: selected ? 42 : 34, height: selected ? 42 : 34)
                .overlay {
                    Circle()
                        .stroke(selected ? NotebookTheme.ink.opacity(0.8) : .white.opacity(0.74), lineWidth: selected ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func avatarChoiceButton<Content: View>(active: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            label()
                .foregroundStyle(active ? .white : NotebookTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(active ? NotebookTheme.ink : .white.opacity(0.58), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(active ? 0.18 : 0.62), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
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
        let text = Text("f(x)  notes")
            .font(.system(size: 14, weight: .semibold, design: .serif))
            .foregroundStyle(color)
        context.draw(text, at: point)
    }
}
