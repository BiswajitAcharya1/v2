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
    @State private var showingComposer = false
    @State private var typedText = ""
    @State private var isScanning = false
    @State private var composerCloseRotation = 0.0

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

            VStack(spacing: 12) {
                pageReader
                if !pages.isEmpty {
                    circularDock
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    StudyAgentBubble(mode: .notebook)
                        .padding(.trailing, 16)
                        .padding(.bottom, 88)
                }
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
            if let page = currentPage {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        NotebookPaperView(cornerRadius: 26) {
                            pageContent(page, index: index)
                        }
                        .padding(.horizontal, 2)
                        .tag(index)
                        .onTapGesture {
                            guard !isEditing else { return }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                turnPage(1)
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: pageIndex)
            } else {
                emptyNotebook
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func pageContent(_ page: NotebookPage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isEditing && currentPage?.id == page.id {
                TextEditor(text: $editedText)
                    .font(.system(size: 16 * textScale, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(minHeight: 420)
            } else {
                ScrollView {
                    Text(page.content.cleanedText)
                        .font(.system(size: 16 * textScale, weight: .regular, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineSpacing(6)
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
                    Task {
                        isScanning = true
                        await store.scanPage(into: liveNotebook.id)
                        pageIndex = 0
                        isScanning = false
                    }
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
        HStack(spacing: 8) {
            Button {
                Task {
                    isScanning = true
                    await store.scanPage(into: liveNotebook.id)
                    pageIndex = 0
                    isScanning = false
                }
            } label: {
                Image(systemName: isScanning ? "sparkles" : "viewfinder")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
            .disabled(isScanning)

            Button {
                showingComposer = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { turnPage(-1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
            .disabled(pages.isEmpty)

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
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
            .disabled(currentPage == nil)

            Button {
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

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { turnPage(1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
            .disabled(pages.isEmpty)
        }
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
        pageIndex = min(max(pageIndex + delta, 0), pages.count - 1)
    }

    private func closeComposer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            composerCloseRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            showingComposer = false
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
