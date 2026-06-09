import SwiftUI

struct NotebookDetailView: View {
    @Environment(NotebookStore.self) private var store
    @State private var displayMode: PageDisplayMode = .cleaned
    @State private var textScale: Double = 1
    @State private var query = ""
    @State private var selectedPage: NotebookPage?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                openingNotebook
                controls
                pageStack
            }
            .padding(20)
        }
        .background(NotebookTheme.field.ignoresSafeArea())
        .navigationTitle(liveNotebook.subject)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("rename notebook") { store.rename(liveNotebook, to: "\(liveNotebook.subject) notes") }
                Button(liveNotebook.isPinned ? "unpin notebook" : "pin notebook") { store.pin(liveNotebook) }
                Button("move earlier") { store.move(liveNotebook, direction: .earlier) }
                Button("move later") { store.move(liveNotebook, direction: .later) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .navigationDestination(item: $selectedPage) { page in
            StudyFocusView(page: page)
        }
    }

    private var openingNotebook: some View {
        HStack(alignment: .center, spacing: 18) {
            CompositionNotebookCard(notebook: liveNotebook, namespace: nil)
                .frame(width: 124)
                .rotation3DEffect(.degrees(-13), axis: (x: 0, y: 1, z: 0), perspective: 0.7)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(liveNotebook.pages.count) pages")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
                Text(liveNotebook.subject)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Button {
                    if let page = liveNotebook.pages.first {
                        selectedPage = page
                    }
                } label: {
                    Label("only what matters", systemImage: "sparkle")
                }
                .buttonStyle(PillButtonStyle(tint: NotebookTheme.accent(liveNotebook.accent)))
            }
        }
    }

    private var controls: some View {
        GlassSurface(radius: 22, padding: 14, interactive: true) {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("search pages", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .font(.system(.body, design: .rounded))
                .foregroundStyle(NotebookTheme.ink)

                Picker("view", selection: $displayMode) {
                    ForEach(PageDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $textScale, in: 0.88...1.38)
                    Image(systemName: "textformat.size.larger")
                }
                .foregroundStyle(NotebookTheme.muted)
            }
        }
    }

    private var pageStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("pages")
                .font(.notebookSection)
                .foregroundStyle(NotebookTheme.ink)

            if pages.isEmpty {
                GlassSurface(radius: 18, padding: 18) {
                    Text("scan a page to fill this notebook.")
                        .font(.notebookBody)
                        .foregroundStyle(NotebookTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(pages) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        NotebookPaperView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(page.title)
                                        .font(.system(.headline, design: .rounded, weight: .semibold))
                                    Spacer()
                                    PageChip(text: page.studyState.dueLabel, systemName: "clock")
                                }
                                .foregroundStyle(NotebookTheme.ink)

                                Text(displayMode == .cleaned ? page.content.cleanedText : page.content.rawText)
                                    .font(.system(size: 16 * textScale, weight: .regular, design: .rounded))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .lineSpacing(5)
                                    .multilineTextAlignment(.leading)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(page.content.keywords, id: \.self) { word in
                                            PageChip(text: word, systemName: "tag")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
