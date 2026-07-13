import AppKit

// Ručni AppKit lifecycle (ADR-002): bez SwiftUI @main App.
// NSStatusItem/UNUserNotificationCenter traže pravi .app bundle → app se pokreće kao .app.
//
// Top-level kod nije main-actor izolovan; AppDelegate jeste (@MainActor jer dira StatusStore),
// pa se sve radi unutar MainActor.assumeIsolated. `app.run()` blokira do terminacije, tako da
// `delegate` (koga NSApplication.delegate drži `weak`) ostaje živ celo vreme.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // .accessory = menu bar app bez dock ikone (ekvivalent LSUIElement=true iz Info.plist-a).
    app.setActivationPolicy(.accessory)
    app.run()
}
