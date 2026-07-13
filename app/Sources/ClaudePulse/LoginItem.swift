import Foundation
import ServiceManagement

/// „Launch at Login" (§3.4 General) preko `SMAppService.mainApp` (macOS 13+, ADR-007).
/// Bez legacy `SMLoginItemSetEnabled`/helper bundle-a — registruje sam `.app` kao login item.
///
/// Napomena: `register()` radi pouzdano tek kad je `.app` na stabilnoj lokaciji (npr.
/// `/Applications`); iz repo foldera status može ostati `.requiresApproval`. Logujemo ishod.
enum LoginItem {
    /// Da li je app trenutno registrovana za pokretanje na login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Uključi/isključi. Vraća `true` na uspeh (bez bačenog error-a).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppLog.info("login item \(enabled ? "registered" : "unregistered"); status=\(status.rawValue)")
            return true
        } catch {
            AppLog.error("login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
