import AppKit

/// Prikazno ime app-a. Držati na jednom mestu radi lakog preimenovanja (ADR-002 napomena).
let appDisplayName = "ClaudePulse"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Jaka referenca — inače bi ARC oslobodio status item i ikona bi nestala iz menu bara.
    private var statusItem: NSStatusItem!

    // Jezgro (Phase 1). Jake reference — žive koliko i app.
    private var settingsStore: SettingsStore!
    private var statusStore: StatusStore!
    private var httpServer: HTTPServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        statusStore = StatusStore(settingsStore: settingsStore)
        statusStore.onChange = { [weak self] in self?.renderStatusItem() }
        // Phase 3 stubovi (za sad samo log; notif/zvuk dolaze kasnije).
        statusStore.onBusyToDone = { source in AppLog.info("TODO Phase 3: notify done for \(source.rawValue)") }
        statusStore.onWaiting = { source in AppLog.info("TODO Phase 3: notify waiting for \(source.rawValue)") }
        statusStore.start()

        let port = UInt16(settingsStore.settings.port)
        httpServer = HTTPServer(port: port, statusStore: statusStore)
        httpServer.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        renderStatusItem()
    }

    // MARK: - Menu bar prikaz

    /// Phase 1: plain-text placeholder koji odražava stanje (dokaz da menu bar reaguje na curl).
    /// Obojeni attributed string dolazi u Phase 2 (§3.2).
    private func renderStatusItem() {
        let title = Source.allCases.map { source -> String in
            let label = source.rawValue.prefix(1).uppercased()
            let state = statusStore.statuses[source]?.state ?? .inactive
            return "\(label)\(symbol(for: state))"
        }.joined(separator: " ")
        statusItem.button?.title = title
    }

    private func symbol(for state: SourceState) -> String {
        switch state {
        case .busy: return "●"
        case .waiting: return "◐"
        case .done: return "✓"
        case .inactive: return "✕"
        }
    }

    // MARK: - Meni (privremeni; pun meni je Phase 2, §3.3)

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Reset all to inactive", action: #selector(resetAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appDisplayName)", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func resetAll() {
        statusStore.resetAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
