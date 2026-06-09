import SwiftUI

struct RootShellView: View {
    @Environment(NotebookStore.self) private var store

    var body: some View {
        Group {
            if store.isAuthenticated {
                TabView {
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label("shelf", systemImage: "books.vertical.fill")
                    }

                    ScanView()
                        .tabItem {
                            Label("scan", systemImage: "viewfinder")
                        }

                    VoiceOnboardingView()
                        .tabItem {
                            Label("voice", systemImage: "waveform")
                        }
                }
                .tint(NotebookTheme.ink)
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(.light)
    }
}
