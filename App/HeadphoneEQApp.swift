import SwiftUI

@main
struct HeadphoneEQApp: App {
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
