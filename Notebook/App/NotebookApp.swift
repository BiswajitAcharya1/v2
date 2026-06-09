import SwiftUI

@main
struct NotebookApp: App {
    @State private var store = NotebookStore()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environment(store)
        }
    }
}
