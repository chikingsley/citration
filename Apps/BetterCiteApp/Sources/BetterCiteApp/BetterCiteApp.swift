import SwiftUI
import AppKit

final class BetterCiteAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        focusPrimaryWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        focusPrimaryWindow()
    }

    private func focusPrimaryWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) ?? NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct BetterCiteAppMain: App {
    @NSApplicationDelegateAdaptor(BetterCiteAppDelegate.self) private var appDelegate
    @State private var model = AppModel.bootstrap()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
    }
}
