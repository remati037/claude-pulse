import AppKit

/// Prikazno ime app-a. Držati na jednom mestu radi lakog preimenovanja (ADR-002 napomena).
let appDisplayName = "ClaudePulse"

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Jaka referenca — inače bi ARC oslobodio status item i ikona bi nestala iz menu bara.
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Phase 0: statični plain-text naslov. Obojeni attributed string dolazi u Phase 2 (§3.2).
        statusItem.button?.title = "C✕ W✕ D✕"

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit \(appDisplayName)",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        // target eksplicitno na self da selector radi bez responder-chain zavisnosti.
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
