import SwiftUI

struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @Namespace private var notebookNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                activityStrip
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("good afternoon, \(store.user.name)")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
            Text("a living shelf for the notes you actually study.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(NotebookTheme.muted)
        }
    }

    private var activityStrip: some View {
        HStack(spacing: 12) {
            GlassSurface(radius: 18, padding: 14, interactive: true) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("today")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                    Text("18 reviews")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassSurface(radius: 18, padding: 14, interactive: true) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("next")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                    Text("math quiz")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("subject shelf")
                    .font(.notebookSection)
                    .foregroundStyle(NotebookTheme.ink)
                Spacer()
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(NotebookTheme.muted)
            }

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
