import SwiftUI
import UIKit

struct NotebookDetailView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var displayMode: PageDisplayMode = .cleaned
    @State private var textScale: Double = 1
    @State private var query = ""
    @State private var selectedPage: NotebookPage?
    @State private var pageIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var showingComposer = false
    @State private var typedText = ""
    @State private var isScanning = false
    @State private var composerCloseRotation = 0.0
    @State private var showingCamera = false
    @State private var closeRotation = 0.0
    @State private var didAutoOpenScanner = false
    @State private var chromeEntered = false
    @State private var actionRailAwake = false
    @State private var selectedInkPage: NotebookPage?
    @State private var focusedTerm: PageTermFocus?

    let notebook: SubjectNotebook

    private var liveNotebook: SubjectNotebook {
        store.notebook(with: notebook.id) ?? notebook
    }

    private var pages: [NotebookPage] {
        let allPages = liveNotebook.pages
        guard !query.isEmpty else { return allPages }
        return allPages.filter { page in
            page.title.localizedCaseInsensitiveContains(query) ||
            page.content.cleanedText.localizedCaseInsensitiveContains(query)
        }
    }

    private var currentPage: NotebookPage? {
        guard !pages.isEmpty else { return nil }
        let index = usesSinglePageLayout ? pageIndex : pageIndex * 2
        return pages[min(index, pages.count - 1)]
    }

    private var usesSinglePageLayout: Bool {
        UIScreen.main.bounds.width < 560
    }

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            NotebookDetailAtmosphere(accent: NotebookTheme.accent(liveNotebook.accent))
                .ignoresSafeArea()

            VStack(spacing: 8) {
                notebookChrome
                if !liveNotebook.pages.isEmpty {
                    notebookSearch
                }
                pageReader
                if !pages.isEmpty {
                    notebookActionRail
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isScanning {
                ScanProcessingOverlay(phase: store.scanPhase)
            }

            if let notice = store.scanRouteNotice {
                ScanRouteToast(notice: notice)
                    .padding(.horizontal, 22)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 72)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPage) { page in
            StudyFocusView(page: page)
        }
        .sheet(item: $selectedInkPage) { page in
            InkCoachSheet(page: page) {
                Haptics.success()
                store.polishPageForStudy(pageID: page.id)
                selectedInkPage = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $focusedTerm) { focus in
            TermLensSheet(focus: focus)
                .presentationDetents([.height(360), .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingComposer) {
            typedPageComposer
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCamera) {
            DocumentScannerView { images in
                Task {
                    Haptics.open()
                    isScanning = true
                    await store.scanCapturedImages(images, into: liveNotebook.id)
                    Haptics.success()
                    pageIndex = 0
                    isScanning = false
                }
            } onCancel: {
                Haptics.softTap()
                isScanning = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: currentPage?.id) {
            editedText = currentPage?.content.cleanedText ?? ""
            isEditing = false
        }
        .onAppear {
            editedText = currentPage?.content.cleanedText ?? ""
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                chromeEntered = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                actionRailAwake = true
            }
            autoOpenScannerIfNeeded()
        }
        .onChange(of: liveNotebook.pages.count) {
            if liveNotebook.pages.isEmpty {
                autoOpenScannerIfNeeded()
            } else {
                pageIndex = min(pageIndex, spreadCount - 1)
            }
        }
        .onChange(of: query) {
            pageIndex = 0
        }
        .onChange(of: store.scanRouteNotice?.id) {
            guard store.scanRouteNotice != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    store.scanRouteNotice = nil
                }
            }
        }
    }

    private var notebookChrome: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.softTap()
                closeNotebook()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.62), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
                    }
                    .rotationEffect(.degrees(closeRotation))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("close notebook")

            Spacer(minLength: 8)

            MinimalAppLogo()
                .frame(width: 34, height: 34)
                .opacity(0.9)

            Spacer(minLength: 8)

            if let currentPage {
                Text(currentPageLabel)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.74))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.5), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .id(currentPage.id)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.66), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 7)
        .offset(y: chromeEntered ? 0 : -16)
        .opacity(chromeEntered ? 1 : 0)
    }

    private var notebookSearch: some View {
        HStack(spacing: 10) {
            GooeyInput(
                label: "search notes",
                systemName: "magnifyingglass",
                text: $query,
                onSubmit: {
                    Haptics.selection()
                    pageIndex = 0
                }
            )

            if !query.isEmpty {
                Button {
                    Haptics.softTap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        query = ""
                        pageIndex = 0
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .opacity(chromeEntered ? 1 : 0)
        .offset(y: chromeEntered ? 0 : -8)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: query.isEmpty)
    }

    private var notebookStatusLine: String {
        guard !pages.isEmpty else { return "ready for notes" }
        let tables = pages.reduce(0) { $0 + $1.content.tables.count }
        let models = pages.reduce(0) { $0 + $1.content.models.count }
        let extras = [
            tables > 0 ? "\(tables) tables" : nil,
            models > 0 ? "\(models) models" : nil
        ].compactMap(\.self).joined(separator: "  ")
        return extras.isEmpty ? "\(pages.count) pages" : "\(pages.count) pages  \(extras)"
    }

    private var currentPageLabel: String {
        guard !pages.isEmpty else { return "page" }
        if usesSinglePageLayout {
            return "page \(min(pageIndex + 1, pages.count))"
        }
        let left = min(pageIndex * 2 + 1, pages.count)
        let right = left + 1
        if right <= pages.count {
            return "pages \(left) and \(right)"
        }
        return "page \(left)"
    }

    private var pageReader: some View {
        ZStack {
            if currentPage != nil {
                ZStack {
                    PageStackBackdrop(pageCount: pages.count)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    TabView(selection: $pageIndex) {
                        ForEach(0..<spreadCount, id: \.self) { spread in
                            let leftIndex = usesSinglePageLayout ? spread : spread * 2
                            let rightIndex = leftIndex + 1
                            NotebookSpreadView(
                                left: pages[leftIndex],
                                right: !usesSinglePageLayout && pages.indices.contains(rightIndex) ? pages[rightIndex] : nil,
                                singlePage: usesSinglePageLayout,
                                leftContent: { pageContent(pages[leftIndex], index: leftIndex, compact: false) },
                                rightContent: {
                                    if !usesSinglePageLayout, pages.indices.contains(rightIndex) {
                                        pageContent(pages[rightIndex], index: rightIndex, compact: true)
                                    } else {
                                        EmptyView()
                                    }
                                },
                                onSelect: { page in
                                    guard !isEditing else { return }
                                    Haptics.open()
                                    selectedPage = page
                                }
                            )
                            .tag(spread)
                            .rotation3DEffect(.degrees(pageIndex == spread ? 0 : 2.5), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: pageIndex)
            } else if !liveNotebook.pages.isEmpty {
                noSearchResults
            } else {
                emptyNotebook
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var spreadCount: Int {
        usesSinglePageLayout ? max(1, pages.count) : max(1, Int(ceil(Double(pages.count) / 2.0)))
    }

    private func pageContent(_ page: NotebookPage, index: Int, compact: Bool = false) -> some View {
        let scale = compact ? textScale * 0.82 : textScale
        return VStack(alignment: .leading, spacing: 12) {
            pageHeader(page, index: index, scale: scale)
            PageInsightStrip(insight: page.content.insight, scale: scale) { prompt in
                Haptics.selection()
                selectedPage = page
            }
            SmartPageActionDock(
                page: page,
                scale: scale,
                cardCount: store.flashcards(for: page).count,
                textScale: textScale,
                onBoost: {
                    Haptics.success()
                    store.preparePageForStudy(pageID: page.id)
                },
                onStudy: {
                    Haptics.open()
                    selectedPage = page
                },
                onModel: {
                    Haptics.success()
                    store.generateStudyModel(for: page.id)
                },
                onInk: {
                    Haptics.open()
                    selectedInkPage = page
                },
                onResize: {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        textScale = textScale >= 1.32 ? 0.92 : textScale + 0.14
                    }
                }
            )
            ModelForgeStrip(plan: store.modelForgePlan(for: page), scale: scale) {
                Haptics.success()
                if page.content.models.isEmpty {
                    store.generateStudyModel(for: page.id)
                }
                selectedPage = store.page(with: page.id) ?? page
            }
            PageCaptureDeck(
                page: page,
                cardCount: store.flashcards(for: page).count,
                scale: scale,
                onInk: {
                    Haptics.open()
                    selectedInkPage = page
                },
                onModel: {
                    Haptics.success()
                    store.generateStudyModel(for: page.id)
                },
                onStudy: {
                    Haptics.open()
                    selectedPage = page
                },
                onRepair: {
                    Haptics.success()
                    store.repairScanLayout(pageID: page.id)
                }
            )

            if isEditing && currentPage?.id == page.id {
                TextEditor(text: $editedText)
                    .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(minHeight: 360, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if page.content.sections.count > 1 {
                            ForEach(page.content.sections) { section in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(section.title)
                                        .font(.system(size: 15 * scale, weight: .semibold, design: .serif))
                                        .foregroundStyle(NotebookTheme.ink.opacity(0.76))
                                    InteractiveStudyText(
                                        text: section.body,
                                        keywords: page.content.keywords,
                                        formulas: page.content.formulas,
                                        scale: scale
                                    ) { term in
                                        Haptics.selection()
                                        focusedTerm = PageTermFocus(term: term, page: page)
                                    }
                                }
                            }
                        } else {
                            InteractiveStudyText(
                                text: page.content.cleanedText,
                                keywords: page.content.keywords,
                                formulas: page.content.formulas,
                                scale: scale
                            ) { term in
                                Haptics.selection()
                                focusedTerm = PageTermFocus(term: term, page: page)
                            }
                        }

                        ForEach(page.content.formulas, id: \.self) { formula in
                            Button {
                                Haptics.selection()
                                focusedTerm = PageTermFocus(term: formula, page: page)
                            } label: {
                                Text(formula)
                                    .font(.system(size: 17 * scale, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(page.content.tables) { table in
                            DetectedTableView(table: table)
                        }

                        ForEach(page.content.models) { model in
                            DetectedModelView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 360, maxHeight: .infinity)
            }
        }
    }

    private func pageHeader(_ page: NotebookPage, index: Int, scale: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title.lowercased())
                    .font(.system(size: 18 * scale, weight: .semibold, design: .serif))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineLimit(2)
                Text(page.createdAt.formatted(date: .abbreviated, time: .omitted).lowercased())
                    .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                PageSignalDot(symbol: "text.viewfinder", count: page.content.keywords.count)
                if !page.content.tables.isEmpty {
                    PageSignalDot(symbol: "tablecells", count: page.content.tables.count)
                }
                if !page.content.models.isEmpty {
                    PageSignalDot(symbol: "cube.transparent", count: page.content.models.count)
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var emptyNotebook: some View {
        NotebookPaperView(cornerRadius: 32) {
            ZStack {
                OpenCompositionRules(isLeft: false)
                    .opacity(0.82)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                VStack(spacing: 18) {
                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(NotebookTheme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [10, 11]))
                            .frame(width: 220, height: 276)
                        EdgeLockCorners()
                            .stroke(NotebookTheme.ink.opacity(0.44), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 198, height: 254)
                            .scaleEffect(actionRailAwake ? 1.04 : 0.98)
                        ScannerGlow()
                            .frame(width: 188, height: 20)
                            .offset(y: actionRailAwake ? 96 : -96)
                            .opacity(0.58)
                    }
                    .frame(height: 302)

                    HStack(spacing: 12) {
                        Button {
                            Haptics.open()
                            showingCamera = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 17, weight: .bold))
                                Text("scan notes")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 58)
                        }
                        .buttonStyle(PillButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                        .disabled(isScanning)

                        Button {
                            Haptics.open()
                            typedText = ""
                            showingComposer = true
                        } label: {
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 17, weight: .bold))
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.82), foreground: NotebookTheme.ink))
                        .disabled(isScanning)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 560)
        }
    }

    private var noSearchResults: some View {
        NotebookPaperView(cornerRadius: 32) {
            ZStack {
                OpenCompositionRules(isLeft: false)
                    .opacity(0.78)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 72, height: 72)
                        .background(.white.opacity(0.56), in: Circle())
                    Text("no matching notes")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Button {
                        Haptics.softTap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            query = ""
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(FloatingCircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 560)
        }
    }

    private var notebookActionRail: some View {
        HStack(spacing: 10) {
            railButton(symbol: "viewfinder", label: "scan") {
                Haptics.open()
                showingCamera = true
            }
            .disabled(isScanning)

            railButton(symbol: "pencil.and.scribble", label: "write") {
                Haptics.open()
                typedText = ""
                showingComposer = true
            }
            .disabled(isScanning || isEditing)

            railButton(symbol: "sparkles", label: "study") {
                if let page = currentPage {
                    Haptics.open()
                    selectedPage = page
                }
            }
            .disabled(currentPage == nil || isEditing)

            railButton(symbol: "cube.transparent", label: "model") {
                if let page = currentPage {
                    Haptics.success()
                    store.generateStudyModel(for: page.id)
                }
            }
            .disabled(currentPage == nil || isEditing)

            railButton(symbol: isEditing ? "checkmark" : "pencil", label: isEditing ? "save" : "edit") {
                Haptics.selection()
                if let page = currentPage {
                    if isEditing {
                        store.updatePageText(pageID: page.id, text: editedText)
                    } else {
                        editedText = page.content.cleanedText
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEditing.toggle()
                    }
                }
            }
            .disabled(currentPage == nil)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.11), radius: 18, y: 10)
        .scaleEffect(actionRailAwake ? 1.01 : 0.985)
    }

    private func railButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .foregroundStyle(.white)
            .accessibilityLabel(label)
        }
        .buttonStyle(FloatingCircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
    }

    private var typedPageComposer: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("write notes")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Spacer()
                    Button {
                        closeComposer()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 42, height: 42)
                            .rotationEffect(.degrees(composerCloseRotation))
                    }
                    .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.76), foreground: NotebookTheme.ink))
                }

                NotebookPaperView(cornerRadius: 20) {
                    TextEditor(text: $typedText)
                        .scrollContentBackground(.hidden)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink)
                        .tint(NotebookTheme.ink)
                        .frame(minHeight: 250)
                }

                Button {
                    Haptics.success()
                    store.addTypedPage(to: liveNotebook.id, text: typedText)
                    typedText = ""
                    pageIndex = 0
                    showingComposer = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle())
                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
    }

    private func turnPage(_ delta: Int) {
        guard !pages.isEmpty else { return }
        pageIndex = min(max(pageIndex + delta, 0), spreadCount - 1)
    }

    private func closeComposer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            composerCloseRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            showingComposer = false
        }
    }

    private func closeNotebook() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            closeRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            dismiss()
        }
    }

    private func autoOpenScannerIfNeeded() {
        guard pages.isEmpty, !didAutoOpenScanner, !showingCamera else { return }
        didAutoOpenScanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            Haptics.open()
            showingCamera = true
        }
    }
}
