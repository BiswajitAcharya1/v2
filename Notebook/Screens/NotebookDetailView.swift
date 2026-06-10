import SwiftUI

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
        return pages[min(pageIndex * 2, pages.count - 1)]
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
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPage) { page in
            StudyFocusView(page: page)
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
                Text("page \(min(pageIndex * 2 + 1, pages.count))")
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

    private var pageReader: some View {
        ZStack {
            if currentPage != nil {
                ZStack {
                    PageStackBackdrop(pageCount: pages.count)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    TabView(selection: $pageIndex) {
                        ForEach(0..<spreadCount, id: \.self) { spread in
                            NotebookSpreadView(
                                left: pages[spread * 2],
                                right: pages.indices.contains(spread * 2 + 1) ? pages[spread * 2 + 1] : nil,
                                leftContent: { pageContent(pages[spread * 2], index: spread * 2, compact: pages.indices.contains(spread * 2 + 1)) },
                                rightContent: {
                                    if pages.indices.contains(spread * 2 + 1) {
                                        pageContent(pages[spread * 2 + 1], index: spread * 2 + 1, compact: true)
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
        max(1, Int(ceil(Double(pages.count) / 2.0)))
    }

    private func pageContent(_ page: NotebookPage, index: Int, compact: Bool = false) -> some View {
        let scale = compact ? textScale * 0.82 : textScale
        return VStack(alignment: .leading, spacing: 12) {
            pageHeader(page, index: index, scale: scale)

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
                                    Text(section.body)
                                        .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                                        .foregroundStyle(NotebookTheme.ink)
                                        .lineSpacing(6)
                                }
                            }
                        } else {
                            Text(page.content.cleanedText)
                                .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                                .foregroundStyle(NotebookTheme.ink)
                                .lineSpacing(6)
                        }

                        ForEach(page.content.formulas, id: \.self) { formula in
                            Text(formula)
                                .font(.system(size: 17 * scale, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NotebookTheme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            railButton(symbol: "sparkles", label: "study") {
                if let page = currentPage {
                    Haptics.open()
                    selectedPage = page
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
                    Text("type notes")
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

private struct NotebookDetailAtmosphere: View {
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 18.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<9 {
                    var path = Path()
                    let y = size.height * (0.1 + CGFloat(index) * 0.105)
                    let drift = CGFloat(sin(t * 0.16 + Double(index))) * 18
                    path.move(to: CGPoint(x: -30, y: y + drift))
                    path.addCurve(
                        to: CGPoint(x: size.width + 40, y: y + CGFloat(cos(t * 0.12 + Double(index))) * 14),
                        control1: CGPoint(x: size.width * 0.28, y: y - 22 + drift),
                        control2: CGPoint(x: size.width * 0.68, y: y + 24 - drift)
                    )
                    context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.025 + Double(index % 3) * 0.01)), lineWidth: 1)
                }

                for index in 0..<18 {
                    let x = size.width * CGFloat((index * 37) % 101) / 100
                    let y = size.height * CGFloat((index * 53) % 97) / 100
                    let offset = CGFloat(sin(t * 0.22 + Double(index))) * 5
                    let rect = CGRect(x: x + offset, y: y, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(index.isMultiple(of: 3) ? 0.16 : 0.07)))
                }
            }
        }
    }
}

private struct PageSignalDot: View {
    let symbol: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(.white.opacity(0.44), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.5), lineWidth: 0.6)
        }
    }
}

private struct PageStackBackdrop: View {
    var pageCount: Int

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NotebookTheme.paper.opacity(0.72 - Double(index) * 0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.42), lineWidth: 0.8)
                    }
                    .offset(x: CGFloat(index + 1) * 5, y: CGFloat(index + 1) * 7)
                    .scaleEffect(1 - CGFloat(index) * 0.012)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                    .opacity(pageCount > index ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NotebookSpreadView<LeftContent: View, RightContent: View>: View {
    let left: NotebookPage
    let right: NotebookPage?
    let leftContent: LeftContent
    let rightContent: RightContent
    let onSelect: (NotebookPage) -> Void
    @State private var touchOffset: CGSize = .zero
    @State private var touching = false

    init(
        left: NotebookPage,
        right: NotebookPage?,
        @ViewBuilder leftContent: () -> LeftContent,
        @ViewBuilder rightContent: () -> RightContent,
        onSelect: @escaping (NotebookPage) -> Void
    ) {
        self.left = left
        self.right = right
        self.leftContent = leftContent()
        self.rightContent = rightContent()
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 560
            let pageGap = isWide ? 18.0 : 2.0

            ZStack {
                OpenCompositionSpreadBackground()

                HStack(spacing: pageGap) {
                    leftContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, isWide ? 34 : 18)
                        .padding(.trailing, isWide ? 14 : 10)
                        .padding(.top, 38)
                        .padding(.bottom, 18)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(left)
                        }

                    rightContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, isWide ? 12 : 6)
                        .padding(.trailing, isWide ? 34 : 18)
                        .padding(.top, 38)
                        .padding(.bottom, 18)
                        .opacity(right == nil ? 0.42 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let right {
                                onSelect(right)
                            }
                        }
                }
                .padding(.horizontal, isWide ? 4 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                DirectionAwareTouchHighlight(offset: touchOffset, isActive: touching, cornerRadius: 30)
                    .opacity(0.42)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.07), radius: 7, y: 4)
            .scaleEffect(touching ? 0.995 : 1)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !touching {
                            Haptics.softTap()
                        }
                        touching = true
                        touchOffset = CGSize(
                            width: max(min(value.translation.width, 46), -46),
                            height: max(min(value.translation.height, 46), -46)
                        )
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            touching = false
                            touchOffset = .zero
                        }
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: touching)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: touchOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
}

private struct OpenCompositionSpreadBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap: CGFloat = size.width > 560 ? 18 : 2
            let pageWidth = max(0, (size.width - gap) / 2)
            ZStack {
                bottomPageStack(size: size)
                HStack(spacing: gap) {
                    pageSurface(isLeft: true)
                        .frame(width: pageWidth)
                    pageSurface(isLeft: false)
                        .frame(width: pageWidth)
                }
                .padding(.horizontal, 0)
                centerFold
                pageCrown(size: size)
                HStack {
                    sidePageEdges()
                    Spacer()
                    sidePageEdges()
                }
            }
        }
    }

    private func bottomPageStack(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.74, blue: 0.78).opacity(0.2 - Double(index) * 0.025))
                    .frame(width: max(0, size.width - CGFloat(index * 6)), height: max(0, size.height - CGFloat(index * 4)))
                    .offset(x: CGFloat(index % 2 == 0 ? -1 : 1) * CGFloat(index + 4), y: CGFloat(index + 3) * 3)
            }
        }
    }

    private func pageSurface(isLeft: Bool) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: isLeft ? 30 : 10,
                bottomLeading: isLeft ? 30 : 10,
                bottomTrailing: isLeft ? 10 : 30,
                topTrailing: isLeft ? 10 : 30
            ),
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.968, blue: 0.982),
                    Color(red: 0.94, green: 0.948, blue: 0.968),
                    Color(red: 0.905, green: 0.915, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(OpenCompositionRules(isLeft: isLeft))
        .overlay {
            if isLeft {
                ClassProgramInset()
                    .padding(.top, 38)
                    .padding(.leading, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(PaperGrain(density: 420).opacity(0.16))
        .overlay(alignment: isLeft ? .trailing : .leading) {
            LinearGradient(
                colors: [.black.opacity(0.08), .clear],
                startPoint: isLeft ? .trailing : .leading,
                endPoint: isLeft ? .leading : .trailing
            )
            .frame(width: 34)
            .allowsHitTesting(false)
        }
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: isLeft ? 30 : 10,
                    bottomLeading: isLeft ? 30 : 10,
                    bottomTrailing: isLeft ? 10 : 30,
                    topTrailing: isLeft ? 10 : 30
                ),
                style: .continuous
            )
            .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var centerFold: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.16), .white.opacity(0.34), .black.opacity(0.11)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 36)
                .blur(radius: 3)
            Capsule()
                .fill(.black.opacity(0.16))
                .frame(width: 1.3)
            Capsule()
                .stroke(.white.opacity(0.44), lineWidth: 0.8)
                .frame(width: 10)
        }
        .allowsHitTesting(false)
    }

    private func pageCrown(size: CGSize) -> some View {
        VStack {
            HStack(spacing: 0) {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 30, bottomLeading: 6, bottomTrailing: 0, topTrailing: 8),
                    style: .continuous
                )
                .fill(.white.opacity(0.38))
                .frame(width: size.width * 0.5, height: 10)
                .offset(y: -2)
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 8, bottomLeading: 0, bottomTrailing: 6, topTrailing: 30),
                    style: .continuous
                )
                .fill(.white.opacity(0.34))
                .frame(width: size.width * 0.5, height: 10)
                .offset(y: -2)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func sidePageEdges() -> some View {
        VStack(spacing: 4) {
            ForEach(0..<26, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.58, green: 0.62, blue: 0.68).opacity(index.isMultiple(of: 2) ? 0.34 : 0.2))
                    .frame(width: 8 + CGFloat(index % 3), height: 1)
            }
        }
        .frame(width: 16)
        .padding(.vertical, 30)
        .frame(maxHeight: .infinity)
    }
}

private struct OpenCompositionRules: View {
    var isLeft: Bool

    var body: some View {
        Canvas { context, size in
            let margin = isLeft ? size.width * 0.16 : size.width * 0.14
            let farMargin = size.width * 0.9

            for x in [margin, farMargin] {
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vertical, with: .color(NotebookTheme.redRule.opacity(0.32)), lineWidth: 0.75)
            }

            var y: CGFloat = 72
            while y < size.height - 22 {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y + (isLeft ? -0.8 : 0.8)))
                context.stroke(line, with: .color(NotebookTheme.blueLine.opacity(0.48)), lineWidth: 0.65)
                y += 18
            }

            var top = Path()
            top.move(to: CGPoint(x: 0, y: 56))
            top.addLine(to: CGPoint(x: size.width, y: 56))
            context.stroke(top, with: .color(NotebookTheme.blueLine.opacity(0.38)), lineWidth: 0.8)
        }
    }
}

private struct ClassProgramInset: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("class program")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(NotebookTheme.ink.opacity(0.52))
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .stroke(NotebookTheme.ink.opacity(row == 0 || column == 0 ? 0.26 : 0.16), lineWidth: 0.45)
                                .frame(width: column == 0 ? 22 : 28, height: row == 0 ? 10 : 13)
                        }
                    }
                }
            }
            Text("notes")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(NotebookTheme.muted.opacity(0.62))
                .padding(.top, 1)
        }
        .padding(9)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(NotebookTheme.ink.opacity(0.14), lineWidth: 0.6)
        }
        .frame(width: 140, alignment: .leading)
        .allowsHitTesting(false)
    }
}

private struct ScanProcessingOverlay: View {
    let phase: ScanPhase
    @State private var entered = false
    @State private var sweep = false
    @State private var fold = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .overlay {
                    ScanAtmosphere(phase: phase, active: sweep)
                }

            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    ProcessingNotebookPocket(phase: phase, active: fold)
                        .offset(y: phase == .sorted ? 34 : 58)
                        .opacity(phase == .capturing ? 0.48 : 1)

                    ProcessingPage(phase: phase, sweep: sweep)
                        .frame(width: 178, height: 238)
                        .rotationEffect(.degrees(pageRotation))
                        .scaleEffect(pageScale)
                        .offset(x: pageOffset.width, y: pageOffset.height)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                        .animation(.spring(response: 0.7, dampingFraction: 0.78), value: phase)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: sweep)
                }
                .frame(width: 242, height: 292)

                VStack(spacing: 9) {
                    Text(phase.caption)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(phaseDetail)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(width: 230)
                }

                ScanPhaseRail(current: phase)
                ScanIntelligenceRibbon(phase: phase, active: sweep)
                ScanModelStackRibbon(phase: phase)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.2), radius: 24, y: 16)
            .scaleEffect(entered ? 1 : 0.94)
            .opacity(entered ? 1 : 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.58, dampingFraction: 0.84), value: entered)
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: phase)
        .onAppear {
            entered = true
            sweep = true
            fold = true
        }
    }

    private var pageScale: CGFloat {
        switch phase {
        case .framing: 1
        case .capturing: 1.02
        case .processing: 0.96
        case .organizing: 0.86
        case .sorted: 0.42
        }
    }

    private var pageRotation: Double {
        switch phase {
        case .framing: 0
        case .capturing: -1.4
        case .processing: 1.8
        case .organizing: -7
        case .sorted: -14
        }
    }

    private var pageOffset: CGSize {
        switch phase {
        case .framing: .zero
        case .capturing: CGSize(width: 0, height: -5)
        case .processing: CGSize(width: 0, height: -12)
        case .organizing: CGSize(width: 18, height: 0)
        case .sorted: CGSize(width: 36, height: 66)
        }
    }

    private var phaseDetail: String {
        switch phase {
        case .framing:
            "lining up the page"
        case .capturing:
            "locking the page edges"
        case .processing:
            "surya reads ink while sam 3d and triposr rebuild diagrams"
        case .organizing:
            "gemma files the page by subject"
        case .sorted:
            "sliding it into your notebook"
        }
    }
}

private struct ProcessingPage: View {
    let phase: ScanPhase
    let sweep: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NotebookTheme.paper)
                .overlay {
                    PaperRules()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .overlay {
                    PaperGrain(density: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(index == 0 ? 0.34 : 0.18))
                        .frame(width: CGFloat(64 + (index * 17) % 76), height: index == 0 ? 5 : 4)
                }
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NotebookTheme.ink.opacity(0.1 + Double(index) * 0.03))
                            .frame(width: 34, height: 28)
                    }
                }
                Spacer()
            }
            .padding(24)
            .opacity(phase == .capturing ? 0.5 : 1)

            EdgeLockCorners()
                .stroke(.white.opacity(phase == .capturing ? 0.96 : 0.58), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(10)
                .scaleEffect(phase == .capturing && sweep ? 1.04 : 1)

            if phase == .processing || phase == .capturing {
                ScannerGlow()
                    .offset(y: sweep ? 92 : -92)
                    .opacity(phase == .processing ? 0.9 : 0.72)
            }

            if phase == .organizing || phase == .sorted {
                ProcessingParticles(active: sweep)
                    .padding(18)
                ReconstructedObjectGlyph(active: sweep)
                    .frame(width: 96, height: 96)
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.82), .black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

private struct ScanIntelligenceRibbon: View {
    let phase: ScanPhase
    let active: Bool

    private let steps: [(ScanPhase, String, String)] = [
        (.capturing, "viewfinder", "capture"),
        (.processing, "text.viewfinder", "ocr"),
        (.organizing, "tablecells", "tables"),
        (.sorted, "cube.transparent", "models")
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(steps, id: \.2) { step in
                VStack(spacing: 6) {
                    Image(systemName: step.1)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(isActive(step.0) ? .white.opacity(0.28) : .white.opacity(0.1), in: Circle())
                        .scaleEffect(isCurrent(step.0) && active ? 1.08 : 1)
                    Text(step.2)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(isActive(step.0) ? 0.92 : 0.42))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
    }

    private func isActive(_ target: ScanPhase) -> Bool {
        guard let currentIndex = ScanPhase.allCases.firstIndex(of: phase),
              let targetIndex = ScanPhase.allCases.firstIndex(of: target) else { return false }
        return targetIndex <= currentIndex
    }

    private func isCurrent(_ target: ScanPhase) -> Bool {
        phase == target
    }
}

private struct ScanModelStackRibbon: View {
    let phase: ScanPhase

    private let models: [(ScanPhase, String, String)] = [
        (.processing, "surya", "text.viewfinder"),
        (.processing, "sam 3d", "scope"),
        (.processing, "triposr", "cube.transparent"),
        (.organizing, "gemma", "sparkle.magnifyingglass")
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(models, id: \.1) { model in
                HStack(spacing: 5) {
                    Image(systemName: model.2)
                        .font(.system(size: 10, weight: .bold))
                    Text(model.1)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(isActive(model.0) ? 0.9 : 0.4))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.white.opacity(isActive(model.0) ? 0.16 : 0.07), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(isActive(model.0) ? 0.26 : 0.12), lineWidth: 0.7)
                }
            }
        }
    }

    private func isActive(_ target: ScanPhase) -> Bool {
        guard let currentIndex = ScanPhase.allCases.firstIndex(of: phase),
              let targetIndex = ScanPhase.allCases.firstIndex(of: target) else { return false }
        return targetIndex <= currentIndex
    }
}

private struct ReconstructedObjectGlyph: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            Canvas { context, size in
                let points = [
                    CGPoint(x: size.width * 0.5, y: size.height * 0.16),
                    CGPoint(x: size.width * 0.78, y: size.height * 0.36),
                    CGPoint(x: size.width * 0.68, y: size.height * 0.74),
                    CGPoint(x: size.width * 0.32, y: size.height * 0.74),
                    CGPoint(x: size.width * 0.22, y: size.height * 0.36)
                ]

                var shell = Path()
                shell.move(to: points[0])
                for point in points.dropFirst() {
                    shell.addLine(to: point)
                }
                shell.closeSubpath()
                context.stroke(shell, with: .color(.white.opacity(0.72)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                for point in points {
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: point)
                    context.stroke(line, with: .color(.white.opacity(0.24)), lineWidth: 1)
                }
            }
            .rotation3DEffect(.degrees(active ? 18 : -18), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: active)
        }
        .padding(12)
        .background(.white.opacity(0.12), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.28), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

private struct ScannerGlow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.86), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 18)
            .blur(radius: 0.4)
            .blendMode(.screen)
    }
}

private struct EdgeLockCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 28

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct ProcessingParticles: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<11, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index.isMultiple(of: 2) ? 0.74 : 0.42))
                        .frame(width: CGFloat(4 + index % 4), height: CGFloat(4 + index % 4))
                        .position(
                            x: proxy.size.width * CGFloat((index * 23) % 91) / 100,
                            y: proxy.size.height * CGFloat((index * 41) % 87) / 100
                        )
                        .offset(y: active ? CGFloat(-10 + index % 5) : CGFloat(8 - index % 4))
                        .blur(radius: index.isMultiple(of: 3) ? 0.6 : 0)
                }
            }
        }
    }
}

private struct ProcessingNotebookPocket: View {
    let phase: ScanPhase
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.11))
                .frame(width: 168, height: 112)
                .overlay {
                    SpeckledCompositionTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .opacity(0.5)
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 22), style: .continuous)
                        .fill(.black.opacity(0.82))
                        .frame(width: 24)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(phase == .sorted ? 0.48 : 0.2))
                        .frame(width: active ? 116 : 86, height: 2)
                        .offset(y: 12)
                }
                .rotation3DEffect(.degrees(phase == .sorted ? -8 : -2), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
                .scaleEffect(phase == .sorted ? 1.08 : 1)
        }
        .animation(.spring(response: 0.62, dampingFraction: 0.78), value: phase)
        .allowsHitTesting(false)
    }
}

private struct ScanPhaseRail: View {
    let current: ScanPhase
    private let phases: [ScanPhase] = [.capturing, .processing, .organizing, .sorted]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(phases) { phase in
                Capsule()
                    .fill(isActive(phase) ? .white.opacity(0.86) : .white.opacity(0.22))
                    .frame(width: current == phase ? 34 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: current)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func isActive(_ phase: ScanPhase) -> Bool {
        guard let currentIndex = phases.firstIndex(of: current),
              let phaseIndex = phases.firstIndex(of: phase) else {
            return false
        }
        return phaseIndex <= currentIndex
    }
}

private struct ScanAtmosphere: View {
    let phase: ScanPhase
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 170, y: center.y - 170, width: 340, height: 340)),
                with: .radialGradient(
                    Gradient(colors: [phaseColor.opacity(0.26), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: active ? 210 : 150
                )
            )
        }
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: active)
    }

    private var phaseColor: Color {
        switch phase {
        case .framing: .white
        case .capturing: Color(red: 0.92, green: 0.82, blue: 0.56)
        case .processing: Color(red: 0.62, green: 0.72, blue: 0.88)
        case .organizing: Color(red: 0.72, green: 0.64, blue: 0.84)
        case .sorted: Color(red: 0.62, green: 0.78, blue: 0.62)
        }
    }
}

private struct DetectedTableView: View {
    let table: DetectedTable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(table.title)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.62))

            VStack(spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NotebookTheme.ink.opacity(0.12), lineWidth: 0.8)
            )
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(.caption, design: .rounded, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(isHeader ? NotebookTheme.ink.opacity(0.055) : .white.opacity(0.12))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotebookTheme.ink.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct DetectedModelView: View {
    let model: DetectedModel
    @State private var selectedNode: String?
    @State private var awake = false

    private var nodes: [String] {
        let modelNodes = model.nodes ?? []
        return modelNodes.isEmpty ? model.terms : modelNodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.54))
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                    Text(model.summary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                }
            }

            if !nodes.isEmpty {
                InteractiveModelMap(nodes: nodes, selectedNode: $selectedNode, awake: awake)
                    .frame(height: 138)
                    .rotation3DEffect(.degrees(awake ? 0 : 18), axis: (x: 1, y: 0, z: 0), perspective: 0.8)

                Text(selectedNode.map { "\($0) is linked to this visual structure. tap another point to study the connection." } ?? "tap a point in the model to inspect it.")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.42), in: Capsule())
                    .animation(.spring(response: 0.35, dampingFraction: 0.84), value: selectedNode)
            }
        }
        .padding(14)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.spring(response: 0.74, dampingFraction: 0.78).delay(0.08)) {
                awake = true
            }
        }
    }
}

private struct InteractiveModelMap: View {
    let nodes: [String]
    @Binding var selectedNode: String?
    var awake: Bool
    @State private var orbit = false

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.34

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Ellipse()
                        .stroke(NotebookTheme.ink.opacity(0.08 + Double(index) * 0.025), lineWidth: 1)
                        .frame(
                            width: radius * CGFloat(2.1 + Double(index) * 0.32),
                            height: radius * CGFloat(0.82 + Double(index) * 0.14)
                        )
                        .rotationEffect(.degrees(Double(index) * 58 + (orbit ? 12 : -12)))
                        .position(center)
                }

                ForEach(Array(nodes.prefix(6).enumerated()), id: \.offset) { index, node in
                    let angle = (Double(index) / Double(max(1, min(nodes.count, 6)))) * .pi * 2 - .pi / 2 + (orbit ? 0.08 : -0.08)
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius * 0.54
                    )
                    Path { path in
                        path.move(to: center)
                        path.addQuadCurve(
                            to: point,
                            control: CGPoint(x: (center.x + point.x) / 2, y: (center.y + point.y) / 2 - 10)
                        )
                    }
                    .stroke(NotebookTheme.ink.opacity(selectedNode == node ? 0.34 : 0.12), lineWidth: selectedNode == node ? 2 : 1)
                    .opacity(awake ? 1 : 0)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.92), .white.opacity(0.42)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .scaleEffect(awake ? 1 : 0.82)
                    .position(center)

                ForEach(Array(nodes.prefix(6).enumerated()), id: \.offset) { index, node in
                    let angle = (Double(index) / Double(max(1, min(nodes.count, 6)))) * .pi * 2 - .pi / 2 + (orbit ? 0.08 : -0.08)
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius * 0.54
                    )
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            selectedNode = node
                        }
                    } label: {
                        Text(node)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: selectedNode == node ? 74 : 58, height: selectedNode == node ? 42 : 34)
                            .background(.white.opacity(selectedNode == node ? 0.82 : 0.54), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.68), lineWidth: 0.8)
                            }
                            .rotation3DEffect(.degrees(selectedNode == node ? -10 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
                            .shadow(color: .black.opacity(selectedNode == node ? 0.12 : 0.06), radius: selectedNode == node ? 9 : 4, y: selectedNode == node ? 7 : 3)
                    }
                    .buttonStyle(.plain)
                    .position(awake ? point : center)
                    .opacity(awake ? 1 : 0)
                }
            }
            .animation(.spring(response: 0.62, dampingFraction: 0.78), value: awake)
            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: orbit)
            .onAppear {
                orbit = true
            }
        }
    }
}
