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
        // Meni se puni lenjo u `menuNeedsUpdate` → uvek svež sadržaj (stanja, vreme, checkmark-ovi).
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        renderStatusItem()
    }

    // MARK: - Menu bar ikona (§3.2)

    /// Obojeni attributed-string prikaz: compact (`C● W● D✕`) ili icon-only (jedna agregatna tačka).
    private func renderStatusItem() {
        let settings = settingsStore.settings
        let effective: [(source: Source, state: SourceState)] = Source.allCases.map { source in
            let raw = statusStore.statuses[source]?.state ?? .inactive
            let enabled = settings.sourceSettings(for: source).enabled
            return (source, StatusRendering.effectiveState(state: raw, enabled: enabled))
        }

        switch settings.displayMode {
        case .compact:
            let letters = effective.map { (StatusRendering.letter(for: $0.source), $0.state) }
            statusItem.button?.attributedTitle = StatusRendering.compactTitle(letters: letters)
        case .iconOnly:
            let aggregate = StatusRendering.aggregate(effective.map { $0.state })
            statusItem.button?.attributedTitle = StatusRendering.iconOnlyTitle(state: aggregate)
        }
    }

    // MARK: - Meni (§3.3) — puni se u menuNeedsUpdate

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = settingsStore.settings
        let now = Date()

        // Red po izvoru (naziv + stanje + relativno vreme) sa submenijem.
        for source in Source.allCases {
            menu.addItem(sourceRow(for: source, settings: settings, now: now))
        }

        menu.addItem(.separator())
        addItem(to: menu, title: "Reset all to inactive", action: #selector(resetAll))
        menu.addItem(.separator())

        addToggle(to: menu, title: "Notifications", isOn: settings.notificationsEnabled, action: #selector(toggleNotifications))
        addToggle(to: menu, title: "Sounds", isOn: settings.soundsEnabled, action: #selector(toggleSounds))
        menu.addItem(.separator())

        menu.addItem(displayModeRow(current: settings.displayMode))
        addItem(to: menu, title: "Settings…", action: nil, enabled: false)      // Phase 3
        addItem(to: menu, title: "Setup Guide…", action: nil, enabled: false)    // Phase 3
        menu.addItem(.separator())

        addItem(to: menu, title: "Launch at Login", action: nil, enabled: false) // Phase 3 (SMAppService)
        addItem(to: menu, title: "Quit \(appDisplayName)", action: #selector(quit), keyEquivalent: "q")
    }

    /// Jedan red izvora: attributed naslov sa obojenom tačkom + submeni (Enabled / Reset / Test notification).
    private func sourceRow(for source: Source, settings: Settings, now: Date) -> NSMenuItem {
        let sourceSettings = settings.sourceSettings(for: source)
        let raw = statusStore.statuses[source]?.state ?? .inactive
        let state = StatusRendering.effectiveState(state: raw, enabled: sourceSettings.enabled)

        let item = NSMenuItem()
        item.attributedTitle = sourceRowTitle(source: source, state: state, settings: settings, now: now)

        let submenu = NSMenu()
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleSourceEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = sourceSettings.enabled ? .on : .off
        enabledItem.representedObject = source.rawValue
        submenu.addItem(enabledItem)

        let resetItem = NSMenuItem(title: "Reset", action: #selector(resetSource(_:)), keyEquivalent: "")
        resetItem.target = self
        resetItem.representedObject = source.rawValue
        submenu.addItem(resetItem)

        let testItem = NSMenuItem(title: "Test notification", action: nil, keyEquivalent: "") // Phase 3
        testItem.isEnabled = false
        submenu.addItem(testItem)

        item.submenu = submenu
        return item
    }

    private func sourceRowTitle(source: Source, state: SourceState, settings: Settings, now: Date) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()

        let prefix = "\(StatusRendering.letter(for: source))  \(StatusRendering.displayName(for: source))   "
        result.append(NSAttributedString(string: prefix, attributes: [.foregroundColor: NSColor.labelColor, .font: font]))
        result.append(NSAttributedString(string: StatusRendering.glyph(for: state),
                                         attributes: [.foregroundColor: StatusRendering.color(for: state), .font: font]))

        var trailing = " \(StatusRendering.label(for: state))"
        if settings.showRelativeTimestamps, state != .inactive,
           let last = statusStore.statuses[source]?.lastEventAt {
            trailing += " \(StatusRendering.relativeTime(from: last, now: now))"
        }
        result.append(NSAttributedString(string: trailing, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        return result
    }

    private func displayModeRow(current: DisplayMode) -> NSMenuItem {
        let item = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let compact = NSMenuItem(title: "Compact", action: #selector(setDisplayCompact), keyEquivalent: "")
        compact.target = self
        compact.state = current == .compact ? .on : .off
        submenu.addItem(compact)

        let iconOnly = NSMenuItem(title: "Icon-only", action: #selector(setDisplayIconOnly), keyEquivalent: "")
        iconOnly.target = self
        iconOnly.state = current == .iconOnly ? .on : .off
        submenu.addItem(iconOnly)

        item.submenu = submenu
        return item
    }

    // MARK: - Meni helperi

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector?, keyEquivalent: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled && action != nil
        menu.addItem(item)
        return item
    }

    private func addToggle(to menu: NSMenu, title: String, isOn: Bool, action: Selector) {
        let item = addItem(to: menu, title: title, action: action)
        item.state = isOn ? .on : .off
    }

    // MARK: - Akcije

    @objc private func toggleSourceEnabled(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = Source(rawValue: raw) else { return }
        settingsStore.update { $0.updateSource(source) { $0.enabled.toggle() } }
        renderStatusItem()
    }

    @objc private func resetSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = Source(rawValue: raw) else { return }
        statusStore.reset(source: source)
    }

    @objc private func resetAll() {
        statusStore.resetAll()
    }

    @objc private func toggleNotifications() {
        settingsStore.update { $0.notificationsEnabled.toggle() }
    }

    @objc private func toggleSounds() {
        settingsStore.update { $0.soundsEnabled.toggle() }
    }

    @objc private func setDisplayCompact() {
        settingsStore.update { $0.displayMode = .compact }
        renderStatusItem()
    }

    @objc private func setDisplayIconOnly() {
        settingsStore.update { $0.displayMode = .iconOnly }
        renderStatusItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuild pri svakom otvaranju → stanja, relativno vreme i checkmark-ovi su uvek sveži.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        populateMenu(menu)
    }
}
