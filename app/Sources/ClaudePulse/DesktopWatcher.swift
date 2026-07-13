import AppKit
import ApplicationServices

/// Bundle id Claude Desktop app-a (potvrđeno iz `/Applications/Claude.app/Contents/Info.plist`).
/// Na jednom mestu radi lakog menjanja ako Anthropic promeni bundle id.
let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

/// In-process watcher za Claude Desktop app (Electron) preko Accessibility API-ja (§2.4).
///
/// Nema hooks/DOM za desktop → poll-ujemo AX tree dok Claude radi i tražimo stop-generation dugme:
/// prisutno = `busy`, nestalo (uz debounce 2 poll-a) = `done`. Feed ide isključivo kroz
/// `StatusStore.apply(source: .desktop, ...)` — sva state-machine logika ostaje tamo.
///
/// `@MainActor`: sav pristup ide preko main actora (kao StatusStore), bez zaključavanja.
@MainActor
final class DesktopWatcher {
    private let settingsStore: SettingsStore
    private let statusStore: StatusStore

    /// Test override poll intervala u sekundama (env), za bržu autonomnu verifikaciju.
    private let pollOverride: Int?

    private var pollTimer: Timer?

    /// Keširan AX element Claude app-a + pid za koji važi (invalidira se na relaunch).
    private var cachedAppElement: AXUIElement?
    private var cachedPID: pid_t?

    /// Debounce: bili smo `busy` i dugme je nestalo → koliko uzastopnih poll-a bez dugmeta.
    private var wasBusy = false
    private var missingPolls = 0

    /// Gornja granica obilaska AX tree-a (Electron tree ume da bude ogroman) — anti-runaway.
    private let nodeBudget = 4000

    init(settingsStore: SettingsStore,
         statusStore: StatusStore,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.pollOverride = environment["CLAUDEPULSE_POLL_SECONDS"].flatMap(Int.init)
    }

    // MARK: - AX permission (§2.4 tačka 4)

    /// Da li app ima Accessibility dozvolu. AppDelegate ovo čita za menu hint.
    var axPermissionGranted: Bool { AXIsProcessTrusted() }

    /// Zatraži dozvolu (sistemski prompt) i otvori System Settings ▸ Privacy ▸ Accessibility.
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Životni ciklus

    func start() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(appLaunched(_:)),
                             name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(appTerminated(_:)),
                             name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Ako Claude već radi u trenutku pokretanja — kreni odmah da poll-uješ.
        if claudeApp() != nil {
            startPolling()
        }
        AppLog.info("DesktopWatcher started (claudeRunning=\(claudeApp() != nil), axTrusted=\(axPermissionGranted))")
    }

    /// Restart poll timera (npr. kad se promeni `desktopPollSeconds` u Settings-u).
    func restart() {
        guard pollTimer != nil else { return }  // ne pokreći ako Claude ne radi
        startPolling()
    }

    private var pollSeconds: TimeInterval {
        TimeInterval(pollOverride ?? max(1, settingsStore.settings.desktopPollSeconds))
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        AppLog.info("DesktopWatcher polling every \(pollSeconds)s")
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        cachedAppElement = nil
        cachedPID = nil
    }

    // MARK: - Workspace notifikacije (poll samo dok Claude radi → zero idle cost)

    @objc private func appLaunched(_ note: Notification) {
        guard isClaude(note) else { return }
        AppLog.info("Claude Desktop launched → start polling")
        startPolling()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard isClaude(note) else { return }
        AppLog.info("Claude Desktop terminated → stop polling, desktop → inactive")
        stopPolling()
        wasBusy = false
        missingPolls = 0
        statusStore.reset(source: .desktop)  // quit → D ✕
    }

    private func isClaude(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == claudeDesktopBundleID
    }

    private func claudeApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == claudeDesktopBundleID }
    }

    // MARK: - Poll + state mapping (§2.4 tačke 2–3)

    private func poll() {
        guard settingsStore.settings.desktop.enabled else { return }
        guard axPermissionGranted else { return }        // bez dozvole → graceful degrade (D ostaje inactive)
        guard let app = appElement() else { return }

        let pattern = settingsStore.settings.desktopStopLabelPattern
        let present = findStopButton(app: app, pattern: pattern)

        if present {
            statusStore.apply(source: .desktop, state: .busy)  // refresh svakih poll-a (kao PreToolUse)
            wasBusy = true
            missingPolls = 0
        } else if wasBusy {
            missingPolls += 1
            if missingPolls >= 2 {   // debounce: 2 uzastopna poll-a bez dugmeta → done
                statusStore.apply(source: .desktop, state: .done)
                wasBusy = false
                missingPolls = 0
            }
        }
    }

    /// Keširan AX element Claude app-a; pri prvom nalaženju budi Chromium a11y tree
    /// (`AXManualAccessibility=true`) — bez toga web sadržaj često nije u AX tree-u.
    private func appElement() -> AXUIElement? {
        guard let running = claudeApp() else { return nil }
        let pid = running.processIdentifier
        if let cached = cachedAppElement, cachedPID == pid { return cached }

        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        cachedAppElement = element
        cachedPID = pid
        AppLog.info("DesktopWatcher AX app element ready (pid=\(pid), AXManualAccessibility set)")
        return element
    }

    // MARK: - AX walk

    /// DFS kroz sve prozore app-a; traži `AXButton` čiji tekst sadrži `pattern` (case-insensitive).
    private func findStopButton(app: AXUIElement, pattern: String) -> Bool {
        let needle = pattern.lowercased()
        guard !needle.isEmpty else { return false }
        var budget = nodeBudget
        for window in childElements(of: app, attribute: kAXWindowsAttribute) {
            if search(element: window, needle: needle, budget: &budget) { return true }
        }
        if budget <= 0 { AppLog.info("DesktopWatcher AX walk hit node budget \(nodeBudget)") }
        return false
    }

    private func search(element: AXUIElement, needle: String, budget: inout Int) -> Bool {
        if budget <= 0 { return false }
        budget -= 1

        if role(of: element) == (kAXButtonRole as String), buttonText(element).contains(needle) {
            return true
        }
        for child in childElements(of: element, attribute: kAXChildrenAttribute) {
            if search(element: child, needle: needle, budget: &budget) { return true }
        }
        return false
    }

    // MARK: - Diagnostic dump (empirijsko otkrivanje labela)

    /// Ispiše svaki `AXButton` (role/title/description/help/value) u log — za nalaženje pravog labela.
    func dumpAXTree() {
        guard axPermissionGranted else {
            AppLog.info("AX dump: no Accessibility permission")
            return
        }
        guard let app = appElement() else {
            AppLog.info("AX dump: Claude Desktop not running")
            return
        }
        AppLog.info("=== AX dump: buttons in Claude Desktop windows ===")
        var budget = nodeBudget
        var count = 0
        for window in childElements(of: app, attribute: kAXWindowsAttribute) {
            dumpButtons(element: window, budget: &budget, count: &count)
        }
        AppLog.info("=== AX dump: \(count) button(s), budgetLeft=\(budget) ===")
    }

    private func dumpButtons(element: AXUIElement, budget: inout Int, count: inout Int) {
        if budget <= 0 { return }
        budget -= 1
        if role(of: element) == (kAXButtonRole as String) {
            count += 1
            let title = stringAttr(element, kAXTitleAttribute) ?? ""
            let desc = stringAttr(element, kAXDescriptionAttribute) ?? ""
            let help = stringAttr(element, kAXHelpAttribute) ?? ""
            let value = stringAttr(element, kAXValueAttribute) ?? ""
            AppLog.info("AXButton title=\"\(title)\" desc=\"\(desc)\" help=\"\(help)\" value=\"\(value)\"")
        }
        for child in childElements(of: element, attribute: kAXChildrenAttribute) {
            dumpButtons(element: child, budget: &budget, count: &count)
        }
    }

    // MARK: - AX helperi

    private func role(of element: AXUIElement) -> String? {
        stringAttr(element, kAXRoleAttribute)
    }

    /// Spojeni tekst dugmeta (title/description/help/value), lowercased — za substring match.
    private func buttonText(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
            .compactMap { stringAttr(element, $0) }
            .joined(separator: " ")
            .lowercased()
    }

    private func stringAttr(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func childElements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
