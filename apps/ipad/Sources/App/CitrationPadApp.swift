import SwiftUI

// MARK: - CitrationPadApp

@main
struct CitrationPadApp: App {
    var body: some Scene {
        WindowGroup {
            IPadSceneView()
        }
    }
}

// MARK: - IPadSceneView

/// Owns one presentation model per iPad scene while every model opens the same
/// app-owned SQLite library through CitrationCore.
private struct IPadSceneView: View {
    // MARK: Internal

    var body: some View {
        IPadRootView(model: model)
    }

    // MARK: Private

    @State private var model: IPadLibraryModel = .bootstrap()
}
