import SwiftUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace
    @State private var sparkleSpin = false

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

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
        .navigationDestination(for: SubjectNotebook.ID.self) { id in
            if let notebook = store.notebook(with: id) {
                NotebookDetailView(notebook: notebook)
            }
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
            NotebookLogo()
                .frame(width: 54, height: 70)
                .rotation3DEffect(.degrees(sparkleSpin ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: sparkleSpin)

            VStack(alignment: .leading, spacing: 8) {
                Text("hello, \(store.user.name)")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                HStack(spacing: 7) {
                    ForEach(store.notebooks.prefix(3)) { notebook in
                        Text(notebook.subject)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            Spacer()
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(store.notebooks) { notebook in
                    NavigationLink(value: notebook.id) {
                        CompositionNotebookCard(notebook: notebook, namespace: notebookNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
