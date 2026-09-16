import AppKit
import SwiftUI

/// SwiftUI restores window state, which for this app means it can come back from a
/// relaunch with its only window closed and nothing on screen but a menu-bar glyph.
/// The delegate makes the window deterministic: always present at launch, and back
/// again when the Dock icon is clicked.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { Self.presentPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.presentPanel() }
        return true
    }

    private static func presentPanel() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        window.isRestorable = false
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct HeadphoneEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // The main window. A menu-bar-only app is invisible to anyone who does not
        // already know it is there, so the panel gets a real window as well.
        Window("headphone-EQ", id: "panel") {
            EQPanelView(model: model)
                .fixedSize()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        // And the same panel from the menu bar, for once it is familiar.
        MenuBarExtra {
            EQPanelView(model: model)
        } label: {
            Image(systemName: "slider.vertical.3")
                .symbolRenderingMode(.hierarchical)
                .opacity(model.isEnabled ? 1 : 0.55)
        }
        .menuBarExtraStyle(.window)
    }
}
