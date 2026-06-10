import SwiftUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace
    @State private var sparkleSpin = false
    @State private var selectedNotebook: SubjectNotebook?
    @State private var entered = false
    @State private var showingCourseComposer = false
    @State private var showingAccountCenter = false
    @State private var courseDraft = ""
    @State private var selectedJournalIndex = 0
    @State private var doodleDrift = false
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
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCourseComposer) {
            addCourseSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAccountCenter) {
            AccountCenterView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                sparkleSpin = true
            }
            withAnimation(.spring(response: 0.78, dampingFraction: 0.84).delay(0.12)) {
                entered = true
            }
            withAnimation(.easeInOut(duration: 6.4).repeatForever(autoreverses: true)) {
                doodleDrift = true
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
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.68), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("add course")

                Spacer()

                Button {
                    Haptics.open()
                    showingAccountCenter = true
                } label: {
                    AccountOrb(name: store.user.name)
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
            let cardWidth = min(proxy.size.width * (store.notebooks.count == 1 ? 0.76 : 0.68), 318)

            ZStack(alignment: .top) {
                ShelfBackdrop(subjectCount: store.notebooks.count)
                    .padding(.horizontal, 30)
                    .padding(.top, 315)

                TabView(selection: $selectedJournalIndex) {
                    ForEach(Array(store.notebooks.enumerated()), id: \.element.id) { index, notebook in
                        ZStack {
                            if index == selectedJournalIndex {
                                JournalHalo(accent: NotebookTheme.accent(notebook.accent), animated: sparkleSpin)
                            }
                            CompositionNotebookCard(notebook: notebook, namespace: notebookNamespace) {
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                    selectedNotebook = store.notebook(with: notebook.id) ?? notebook
                                }
                            }
                            .frame(width: cardWidth)
                            .scaleEffect(index == selectedJournalIndex ? 1 : 0.9)
                            .opacity(abs(index - selectedJournalIndex) > 1 ? 0.72 : 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: entered ? 0 : 24)
                        .opacity(entered ? 1 : 0)
                        .animation(.spring(response: 0.74, dampingFraction: 0.82).delay(Double(index) * 0.06), value: entered)
                        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: selectedJournalIndex)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 430)

                journalIndexRail
                    .padding(.top, 430)
            }
        }
        .frame(height: 478)
    }

    private var journalIndexRail: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.notebooks.enumerated()), id: \.element.id) { index, notebook in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.8)) {
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
        HStack(spacing: 10) {
            MiniSignal(text: "\(store.notebooks.count) journals", systemName: "books.vertical.fill")
            MiniSignal(text: activeJournalText, systemName: "sparkle.magnifyingglass")
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

                    HStack(spacing: 10) {
                        TextField("", text: $courseDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(NotebookTheme.ink)
                            .tint(NotebookTheme.ink)
                            .padding(14)
                            .background(.white.opacity(0.66), in: Capsule())
                            .onSubmit(addCourse)

                        Button(action: addCourse) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 50, height: 50)
                        }
                        .buttonStyle(CircleButtonStyle())
                        .disabled(bestCourseMatch == nil)
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
    var name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
                }
            Text(initials)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(NotebookTheme.ink)
        }
        .frame(width: 48, height: 48)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 5)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let fallback = name.first.map(String.init) ?? "m"
        return letters.isEmpty ? fallback.lowercased() : letters.map { String($0).lowercased() }.joined()
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

private struct AccountCenterView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var legalDocument: LegalDocument?
    @State private var expanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassSurface(radius: 30, padding: 18, interactive: true) {
                        HStack(spacing: 14) {
                            AccountOrb(name: store.user.name)
                                .scaleEffect(1.08)
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

                    accountSection("settings") {
                        Toggle("personal voice", isOn: Bindable(store).voiceProfile.wantsPersonalVoice)
                            .tint(NotebookTheme.ink)
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
}

private struct HomeDoodleLayer: View {
    var animated: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
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
