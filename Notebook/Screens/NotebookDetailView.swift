import SwiftUI

struct NotebookDetailView: View {
    @Environment(NotebookStore.self) private var store
    @State private var displayMode: PageDisplayMode = .cleaned
    @State private var textScale: Double = 1
    @State private var query = ""
    @State private var selectedPage: NotebookPage?
    @State private var pageIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var isEditing = false
    @State private var editedText = ""

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
        return pages[min(pageIndex, pages.count - 1)]
    }

    var body: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()
            AmbientPageGlow()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                coverHeader
                controls
                pageReader
                circularDock
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .navigationTitle(liveNotebook.subject)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("rename notebook") { store.rename(liveNotebook, to: "\(liveNotebook.subject) notes") }
                    Button(liveNotebook.isPinned ? "unpin notebook" : "pin notebook") { store.pin(liveNotebook) }
                    Button("move earlier") { store.move(liveNotebook, direction: .earlier) }
                    Button("move later") { store.move(liveNotebook, direction: .later) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .navigationDestination(item: $selectedPage) { page in
            StudyFocusView(page: page)
        }
        .onChange(of: currentPage?.id) {
            editedText = currentPage?.content.cleanedText ?? ""
            isEditing = false
        }
        .onAppear {
            editedText = currentPage?.content.cleanedText ?? ""
        }
    }

    private var coverHeader: some View {
        HStack(spacing: 14) {
            CompositionNotebookCard(notebook: liveNotebook, namespace: nil)
                .frame(width: 74)
                .rotation3DEffect(.degrees(-12), axis: (x: 0, y: 1, z: 0), perspective: 0.7)

            VStack(alignment: .leading, spacing: 6) {
                Text(liveNotebook.subject)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text("\(liveNotebook.pages.count) pages")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
            }
            Spacer()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NotebookTheme.muted)
            TextField("search pages", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .rounded))

            Picker("view", selection: $displayMode) {
                ForEach(PageDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 142)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(NotebookTheme.ink)
    }

    private var pageReader: some View {
        ZStack {
            if let page = currentPage {
                NotebookPaperView(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(page.title)
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                            Spacer()
                            PageChip(text: "\(pageIndex + 1)/\(max(pages.count, 1))", systemName: "book.pages")
                        }
                        .foregroundStyle(NotebookTheme.ink)

                        if isEditing {
                            TextEditor(text: $editedText)
                                .font(.system(size: 16 * textScale, weight: .regular, design: .rounded))
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(minHeight: 260)
                        } else {
                            ScrollView {
                                Text(displayMode == .cleaned ? page.content.cleanedText : page.content.rawText)
                                    .font(.system(size: 16 * textScale, weight: .regular, design: .rounded))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 260)
                        }

                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $textScale, in: 0.88...1.38)
                            Image(systemName: "textformat.size.larger")
                        }
                        .foregroundStyle(NotebookTheme.muted)
                    }
                }
                .frame(maxHeight: 470)
                .rotation3DEffect(.degrees(Double(dragX / 14)), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .offset(x: dragX * 0.18)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragX = max(min(value.translation.width, 120), -120)
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                                if value.translation.width < -60 {
                                    turnPage(1)
                                } else if value.translation.width > 60 {
                                    turnPage(-1)
                                }
                                dragX = 0
                            }
                        }
                )
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: pageIndex)
            } else {
                emptyNotebook
            }
        }
    }

    private var emptyNotebook: some View {
        NotebookPaperView(cornerRadius: 20) {
            VStack(spacing: 18) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
                Text("scan a page to fill this notebook.")
                    .font(.notebookBody)
                    .foregroundStyle(NotebookTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 340)
        }
    }

    private var circularDock: some View {
        HStack(spacing: 18) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { turnPage(-1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))

            Button {
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
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))

            Button {
                if let page = currentPage {
                    selectedPage = page
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.accent(liveNotebook.accent), foreground: .white))

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { turnPage(1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
        }
    }

    private func turnPage(_ delta: Int) {
        guard !pages.isEmpty else { return }
        pageIndex = min(max(pageIndex + delta, 0), pages.count - 1)
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
