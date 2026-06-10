import SwiftUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace
    @State private var sparkleSpin = false
    @State private var selectedNotebook: SubjectNotebook?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                shelf
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(NotebookTheme.field.ignoresSafeArea())
        .navigationDestination(item: $selectedNotebook) { notebook in
            NotebookDetailView(notebook: notebook)
        }
        .navigationTitle("notebook")
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                sparkleSpin = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            MinimalAppLogo()
                .frame(width: 54, height: 54)
                .rotation3DEffect(.degrees(sparkleSpin ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: sparkleSpin)

            VStack(alignment: .leading, spacing: 4) {
                Text("hello, \(displayName)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
            }
            Spacer()
            StudyAgentBubble(mode: .shelf)
        }
    }

    private var shelf: some View {
        GeometryReader { proxy in
            let oneSubject = store.notebooks.count == 1
            let columns = oneSubject
                ? [GridItem(.flexible(), spacing: 18)]
                : [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
            let maxNotebookWidth = oneSubject ? min(proxy.size.width * 0.78, 330) : .infinity

            LazyVGrid(columns: columns, spacing: oneSubject ? 28 : 22) {
                ForEach(store.notebooks) { notebook in
                    CompositionNotebookCard(notebook: notebook, namespace: notebookNamespace) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                            selectedNotebook = store.notebook(with: notebook.id) ?? notebook
                        }
                    }
                    .frame(maxWidth: maxNotebookWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(minHeight: store.notebooks.count == 1 ? 470 : 620)
    }

    private var displayName: String {
        store.user.name == "student" ? "you" : store.user.name
    }
}
