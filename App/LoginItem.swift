import Foundation
import ServiceManagement

/// Registers the app to start with the Mac.
///
/// `SMAppService.mainApp` is the modern route — no helper bundle, no login-item
/// plumbing. The one wrinkle is that macOS may hold the request as "requires approval"
/// until the user allows it in Login Items, so the status is read back rather than
/// assumed.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
