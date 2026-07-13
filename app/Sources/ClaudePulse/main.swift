import AppKit

// Ručni AppKit lifecycle (ADR-002): bez SwiftUI @main App.
// NSStatusItem/UNUserNotificationCenter traže pravi .app bundle → app se pokreće kao .app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// .accessory = menu bar app bez dock ikone (ekvivalent LSUIElement=true iz Info.plist-a).
app.setActivationPolicy(.accessory)
app.run()
