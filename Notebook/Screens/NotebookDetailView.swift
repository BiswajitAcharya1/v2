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
            AmbientPageGlow()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                pageReader
                if !pages.isEmpty {
                    circularDock
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.softTap()
                        closeNotebook()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .rotationEffect(.degrees(closeRotation))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("close notebook")
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                Spacer()
            }

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
        .sheet(isPresented: $showingComposer) {
            typedPageComposer
                .presentationDetents([.medium, .large])
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
        }
    }

    private var pageReader: some View {
        ZStack {
            if currentPage != nil {
                ZStack {
                    PageStackBackdrop(pageCount: pages.count)
                        .padding(.horizontal, 14)
                        .padding(.top, 22)

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
        return VStack(alignment: .leading, spacing: 16) {
            if isEditing && currentPage?.id == page.id {
                TextEditor(text: $editedText)
                    .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(minHeight: 420)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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
                .frame(minHeight: 420)
            }
        }
    }

    private var emptyNotebook: some View {
        NotebookPaperView(cornerRadius: 28) {
            VStack(spacing: 22) {
                Spacer()

                Text("scan your notes")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.open()
                    showingCamera = true
                } label: {
                    Image(systemName: isScanning ? "sparkles" : "viewfinder")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 86, height: 86)
                }
                .buttonStyle(CircleButtonStyle(tint: NotebookTheme.accent(liveNotebook.accent), foreground: .white))
                .disabled(isScanning)
                .scaleEffect(isScanning ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isScanning)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 560)
        }
    }

    private var circularDock: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.open()
                showingCamera = true
            } label: {
                Image(systemName: isScanning ? "sparkles" : "viewfinder")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
            .disabled(isScanning)

            Button {
                Haptics.press()
                showingComposer = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))

            Button {
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
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
            .disabled(currentPage == nil)

            Button {
                Haptics.open()
                if let page = currentPage {
                    selectedPage = page
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.accent(liveNotebook.accent), foreground: .white))
            .disabled(currentPage == nil)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.11), radius: 18, y: 10)
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
}

private struct AmbientPageGlow: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let x = size.width * (0.5 + 0.22 * sin(t * 0.18))
                let y = size.height * (0.25 + 0.08 * cos(t * 0.23))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 120, y: y - 120, width: 240, height: 240)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.34), .clear]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: 140
                    )
                )
            }
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

            HStack(spacing: isWide ? 12 : 8) {
                NotebookPaperView(cornerRadius: 26) {
                    leftContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .overlay(alignment: .trailing) {
                    pageFoldShadow
                }
                .onTapGesture {
                    onSelect(left)
                }

                NotebookPaperView(cornerRadius: 26) {
                    rightContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .opacity(right == nil ? 0.52 : 1)
                .overlay(alignment: .leading) {
                    pageFoldShadow
                        .scaleEffect(x: -1)
                }
                .onTapGesture {
                    if let right {
                        onSelect(right)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .padding(.horizontal, isWide ? 6 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    private var pageFoldShadow: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.black.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 18)
            .padding(.vertical, 20)
            .allowsHitTesting(false)
    }
}

private struct ScanProcessingOverlay: View {
    let phase: ScanPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.58), lineWidth: 1.2)
                        .frame(width: 178, height: 238)
                    ScannerGlow()
                        .frame(width: 178, height: 238)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                Text(phase.rawValue)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(26)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 16)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct ScannerGlow: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let y = size.height * (0.15 + 0.7 * ((sin(t * 2.1) + 1) / 2))
                let rect = CGRect(x: 0, y: y - 9, width: size.width, height: 18)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 12),
                    with: .linearGradient(
                        Gradient(colors: [.clear, .white.opacity(0.82), .clear]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: size.width, y: y)
                    )
                )
            }
        }
    }
}

private struct DetectedTableView: View {
    let table: DetectedTable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(table.title)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.7))

            VStack(spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NotebookTheme.ink.opacity(0.1), lineWidth: 1)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(isHeader ? NotebookTheme.ink.opacity(0.08) : .white.opacity(0.28))
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
                InteractiveModelMap(nodes: nodes, selectedNode: $selectedNode)
                    .frame(height: 138)

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
    }
}

private struct InteractiveModelMap: View {
    let nodes: [String]
    @Binding var selectedNode: String?

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.34

            ZStack {
                ForEach(Array(nodes.prefix(6).enumerated()), id: \.offset) { index, node in
                    let angle = (Double(index) / Double(max(1, min(nodes.count, 6)))) * .pi * 2 - .pi / 2
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    Path { path in
                        path.move(to: center)
                        path.addQuadCurve(
                            to: point,
                            control: CGPoint(x: (center.x + point.x) / 2, y: (center.y + point.y) / 2 - 10)
                        )
                    }
                    .stroke(NotebookTheme.ink.opacity(selectedNode == node ? 0.34 : 0.12), lineWidth: selectedNode == node ? 2 : 1)
                }

                Circle()
                    .fill(.white.opacity(0.66))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .position(center)

                ForEach(Array(nodes.prefix(6).enumerated()), id: \.offset) { index, node in
                    let angle = (Double(index) / Double(max(1, min(nodes.count, 6)))) * .pi * 2 - .pi / 2
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
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
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }
            }
        }
    }
}
