import SwiftUI

struct ReviewSprintView: View {
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

struct SmartSearchView: View {
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
