import SwiftUI

@main
struct HeadphoneEQApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            EQPanelView(model: model)
        } label: {
            // A fader silhouette rather than a generic speaker — recognisable in a
            // crowded menu bar at a glance.
            Image(systemName: model.isEnabled ? "slider.vertical.3" : "slider.vertical.3")
                .symbolRenderingMode(.hierarchical)
                .opacity(model.isEnabled ? 1 : 0.55)
        }
        .menuBarExtraStyle(.window)

        // Development aid: the menu-bar popover cannot be opened programmatically, so
        // `HEADPHONE_EQ_PANEL_WINDOW=1` puts the same panel in an ordinary window for
        // screenshots and layout work.
        WindowGroup("Panel") {
            if ProcessInfo.processInfo.environment["HEADPHONE_EQ_PANEL_WINDOW"] == "1" {
                EQPanelView(model: model)
            }
        }
        .defaultSize(width: 430, height: 420)
        .windowResizability(.contentSize)
    }
}
