import AppKit
import SwiftUI

/// Lazy `NSWindow` + `NSHostingController` za SwiftUI Settings (ADR-002: ručni AppKit lifecycle;
/// SwiftUI prozori kroz `NSHostingController`). Jedan prozor, ponovo se koristi na svako otvaranje.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let soundPlayer: SoundPlayer

    init(store: SettingsStore, soundPlayer: SoundPlayer) {
        self.store = store
        self.soundPlayer = soundPlayer
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store, soundPlayer: soundPlayer))
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(appDisplayName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Accessory app: bez activate prozor bi se otvorio iza drugih.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
