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
    @State private var showingUpload = false
    @State private var closeRotation = 0.0
    @State private var searchCloseRotation = 0.0
    @State private var didAutoOpenScanner = false
    @State private var chromeEntered = false
    @State private var actionRailAwake = false
    @State private var selectedInkPage: NotebookPage?
    @State private var focusedTerm: PageTermFocus?
    @State private var showingShareNotebook = false

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
                pageReader
                    .layoutPriority(1)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                processScannedImages(images)
            } onCancel: {
                Haptics.softTap()
                isScanning = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingUpload) {
            DocumentScannerView(preferPhotoImport: true) { images in
                processScannedImages(images)
            } onCancel: {
                Haptics.softTap()
                isScanning = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingShareNotebook) {
            NotebookShareSheet(notebook: liveNotebook)
                .presentationDetents([.height(430), .medium])
                .presentationDragIndicator(.visible)
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
        .onChange(of: pageIndex) {
            Haptics.selection()
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

            if let currentPage {
                Text(currentPageLabel)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.74))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.5), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .id(currentPage.id)

                Button {
                    Haptics.open()
                    selectedPage = currentPage
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.54), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        textScale = textScale >= 1.32 ? 0.92 : textScale + 0.14
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.54), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if !liveNotebook.pages.isEmpty {
                Button {
                    Haptics.open()
                    showingShareNotebook = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("share notebook")
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
                    clearSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 42, height: 42)
                        .rotationEffect(.degrees(searchCloseRotation))
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
        .frame(maxWidth: .infinity)
    }

    private var spreadCount: Int {
        usesSinglePageLayout ? max(1, pages.count) : max(1, Int(ceil(Double(pages.count) / 2.0)))
    }

    private func pageContent(_ page: NotebookPage, index: Int, compact: Bool = false) -> some View {
        let scale = compact ? textScale * 0.82 : textScale
        return VStack(alignment: .leading, spacing: 12) {
            pageHeader(page, index: index, scale: scale)
            TextEditor(text: editableText(for: page))
                .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(NotebookTheme.ink)
                .tint(NotebookTheme.ink)
                .lineSpacing(5)
                .frame(minHeight: 460, maxHeight: .infinity)

        }
    }

    private func editableText(for page: NotebookPage) -> Binding<String> {
        Binding(
            get: {
                store.page(with: page.id)?.content.cleanedText ?? page.content.cleanedText
            },
            set: { newValue in
                store.updatePageText(pageID: page.id, text: newValue)
            }
        )
    }

    private func pageAction(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.white.opacity(0.56), in: Capsule())
        }
        .buttonStyle(.plain)
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
        }
        .padding(.bottom, 2)
    }

    private var emptyNotebook: some View {
        NotebookPaperView(cornerRadius: 32) {
            ZStack {
                OpenCompositionRules(isLeft: false)
                    .opacity(0.82)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                Button {
                    Haptics.softTap()
                    closeNotebook()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(closeRotation))
                }
                .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.88), foreground: NotebookTheme.ink))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(18)
                .accessibilityLabel("close notebook")

                VStack(spacing: 18) {
                    Spacer()

                    EmptyNotebookCapturePortal(active: actionRailAwake)
                        .frame(height: 316)

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
                            showingUpload = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.82), foreground: NotebookTheme.ink))
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
            .frame(maxWidth: .infinity, minHeight: 620)
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
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 54, height: 54)
                            .rotationEffect(.degrees(searchCloseRotation))
                    }
                    .buttonStyle(FloatingCircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 620)
        }
    }

    private var notebookActionRail: some View {
        HStack(spacing: 10) {
            railButton(symbol: "viewfinder", label: "scan") {
                Haptics.open()
                showingCamera = true
            }
            .disabled(isScanning)

            railButton(symbol: "square.and.arrow.up", label: "upload") {
                Haptics.open()
                showingUpload = true
            }
            .disabled(isScanning)

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

    private func clearSearch() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            searchCloseRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                query = ""
                pageIndex = 0
            }
        }
    }

    private func processScannedImages(_ images: [UIImage]) {
        Task {
            Haptics.open()
            isScanning = true
            await store.scanCapturedImages(images, into: liveNotebook.id)
            Haptics.success()
            pageIndex = 0
            isScanning = false
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

private struct NotebookShareSheet: View {
    let notebook: SubjectNotebook
    @State private var opened = false
    @State private var shimmer = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.white.opacity(0.74))
                        .frame(width: 236, height: 300)
                        .rotationEffect(.degrees(opened ? 7 : -2))
                        .offset(x: opened ? 24 : 0, y: opened ? 8 : 0)
                        .overlay {
                            PaperRules()
                                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                                .opacity(opened ? 0.8 : 0.2)
                        }

                    CompositionCoverFace(
                        subject: notebook.subject,
                        cornerRadius: 24,
                        spineWidth: 14,
                        labelWidth: 136,
                        labelHeight: 104,
                        labelOffsetY: 34,
                        coverStyle: notebook.coverStyle,
                        coverColor: notebook.coverColor,
                        labelStyle: notebook.coverLabelStyle,
                        fontStyle: notebook.coverFontStyle,
                        customCoverImage: notebook.customCoverImage
                    )
                    .frame(width: 220, height: 292)
                    .rotation3DEffect(.degrees(opened ? -42 : -4), axis: (x: 0.08, y: 1, z: 0), anchor: .leading, perspective: 0.72)
                    .offset(x: opened ? -26 : 0, y: opened ? 4 : 0)
                    .overlay {
                        DirectionAwareTouchHighlight(
                            offset: CGSize(width: shimmer ? 24 : -20, height: shimmer ? -12 : 12),
                            isActive: shimmer,
                            cornerRadius: 24
                        )
                        .blendMode(.screen)
                        .opacity(0.28)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 12)
                }
                .frame(height: 318)

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("share journal", systemImage: "paperplane.fill")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(NotebookTheme.ink, in: Capsule())
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(NotebookTheme.ink)
                        Text("wrapping journal")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white.opacity(0.64), in: Capsule())
                }
            }
            .padding(22)
        }
        .onAppear {
            withAnimation(.spring(response: 0.86, dampingFraction: 0.78).delay(0.12)) {
                opened = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                shimmer = true
            }
            shareURL = makeShareBundle()
        }
    }

    private func makeShareBundle() -> URL? {
        let safeSubject = notebook.subject
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = "\(safeSubject.isEmpty ? "journal" : safeSubject).marginalia-notebook"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(notebook)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}
