import SwiftUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace
    @State private var sparkleSpin = false
    @State private var selectedNotebook: SubjectNotebook?
    @State private var entered = false
    @State private var showingCourseComposer = false
    @State private var courseDraft = ""
    private let allowedSubjects = [
        "math", "algebra", "geometry", "calculus", "statistics",
        "science", "biology", "chemistry", "physics", "earth science",
        "history", "world history", "us history", "government",
        "english", "literature", "writing", "spanish", "french",
        "computer science", "economics", "psychology", "art", "music"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 18) {
                header
                shelf
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(LivingPaperBackground().ignoresSafeArea())
        .navigationDestination(item: $selectedNotebook) { notebook in
            NotebookDetailView(notebook: notebook)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCourseComposer) {
            addCourseSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                sparkleSpin = true
            }
            withAnimation(.spring(response: 0.78, dampingFraction: 0.84).delay(0.12)) {
                entered = true
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .trailing) {
            Circle()
                .fill(.white.opacity(0.34))
                .frame(width: 92, height: 92)
                .blur(radius: 18)
                .scaleEffect(sparkleSpin ? 1.08 : 0.92)

            MinimalAppLogo()
                .frame(width: 68, height: 68)
                .rotation3DEffect(.degrees(sparkleSpin ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
                .scaleEffect(sparkleSpin ? 1.02 : 0.98)

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
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity)
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : -8)
    }

    private var shelf: some View {
        GeometryReader { proxy in
            let oneSubject = store.notebooks.count == 1
            let columns = oneSubject
                ? [GridItem(.flexible(), spacing: 18)]
                : [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
            let maxNotebookWidth = oneSubject ? min(proxy.size.width * 0.78, 330) : .infinity

            ZStack(alignment: .top) {
                ShelfBackdrop(subjectCount: store.notebooks.count)
                    .padding(.top, oneSubject ? 310 : 172)

                LazyVGrid(columns: columns, spacing: oneSubject ? 34 : 28) {
                    ForEach(Array(store.notebooks.enumerated()), id: \.element.id) { index, notebook in
                        CompositionNotebookCard(notebook: notebook, namespace: notebookNamespace) {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                selectedNotebook = store.notebook(with: notebook.id) ?? notebook
                            }
                        }
                        .frame(maxWidth: maxNotebookWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: entered ? 0 : 24)
                        .opacity(entered ? 1 : 0)
                        .animation(.spring(response: 0.74, dampingFraction: 0.82).delay(Double(index) * 0.06), value: entered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minHeight: store.notebooks.count == 1 ? 470 : 620)
    }

    private var addCourseSheet: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            GlassSurface(radius: 30, padding: 20, interactive: true) {
                VStack(spacing: 16) {
                    Text("add course")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)

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

                    HStack(spacing: 8) {
                        ForEach(courseSuggestions, id: \.self) { subject in
                            Button {
                                Haptics.selection()
                                courseDraft = subject
                            } label: {
                                Text(subject)
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(NotebookTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.58), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        guard !draft.isEmpty else { return Array(availableSubjects.prefix(4)) }
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
