import AppKit
import CitrationCore
import SwiftUI

// MARK: - CitrationAppDelegate

final class CitrationAppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Internal

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        focusPrimaryWindow()
    }

    func applicationDidBecomeActive(_: Notification) {
        focusPrimaryWindow()
    }

    // MARK: Private

    private func focusPrimaryWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) ?? NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - CitrationApp

@main
struct CitrationApp: App {
    // MARK: Lifecycle

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
    }

    // MARK: Private

    @NSApplicationDelegateAdaptor(CitrationAppDelegate.self) private var appDelegate
    @State private var model: AppModel = .bootstrap()
}
