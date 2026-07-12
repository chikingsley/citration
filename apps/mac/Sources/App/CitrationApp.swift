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
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            InspectorCommands()
            CommandGroup(after: .newItem) {
                Button("Open Selected Item", systemImage: "book.pages") {
                    if let identity = model.selectedItemIdentity {
                        model.openPrimaryDocument(for: identity)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.selectedItemIdentity == nil)
            }
            CommandMenu("Library") {
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task {
                        await model.zoteroSettings.synchronize()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.zoteroSettings.isConnected || model.zoteroSettings.isWorking)
            }
        }

        WindowGroup(for: DocumentWindowRoute.self) { $route in
            if let route {
                DetachedDocumentView(model: model, route: route)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            ApplicationSettingsView(model: model)
        }
    }

    // MARK: Private

    @NSApplicationDelegateAdaptor(CitrationAppDelegate.self) private var appDelegate
    @State private var model: AppModel = .bootstrap()
}
