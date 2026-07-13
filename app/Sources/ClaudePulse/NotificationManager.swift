import AppKit
import UserNotifications

/// macOS notifikacije (§3.5) preko `UNUserNotificationCenter`.
///
/// VAŽNO: `UNUserNotificationCenter.current()` **pada** ako se binary pokrene van `.app`
/// bundle-a (nema bundle identifier-a). Zato sve prolazi kroz `guard isBundled` — goli binary
/// iz `.build/` samo loguje i tiho ništa ne radi.
///
/// Zvuk NE ide preko `UNNotificationSound` — pušta ga `SoundPlayer` (kontrola volume-a + isti
/// engine kao preview u Settings-u), pa `content.sound` ostaje `nil` da nema duplog zvuka.
@MainActor
final class NotificationManager: NSObject {
    private let settingsStore: SettingsStore

    /// Postoji pravi bundle identifier → notifikacije su bezbedne (vidi klasni komentar).
    private let isBundled: Bool

    private var center: UNUserNotificationCenter? {
        isBundled ? .current() : nil
    }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.isBundled = Bundle.main.bundleIdentifier != nil
        super.init()
        center?.delegate = self
    }

    // MARK: - Permission (§3.5, onboarding korak 1)

    /// Zatraži dozvolu za banner + badge. Zvuk tražimo zbog forme, iako ga puštamo sami.
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard let center else {
            AppLog.info("notifications skipped: not running from .app bundle")
            completion?(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AppLog.error("notification authorization error: \(error.localizedDescription)")
            }
            AppLog.info("notification authorization granted=\(granted)")
            if let completion {
                Task { @MainActor in completion(granted) }
            }
        }
    }

    /// Trenutni status dozvole (za Settings/onboarding prikaz).
    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard let center else { completion(.denied); return }
        center.getNotificationSettings { settings in
            Task { @MainActor in completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Slanje (kukice iz StatusStore-a)

    /// `busy → done`: „Claude … finished". Poštuje master toggle, per-source `notifyOnDone`, DND.
    func notifyDone(source: Source, title: String?) {
        let s = settingsStore.settings
        guard s.notificationsEnabled, s.sourceSettings(for: source).notifyOnDone else { return }
        guard !isSuppressedByDND(settings: s) else {
            AppLog.info("notification suppressed by DND: \(source.rawValue) done")
            return
        }
        deliver(
            id: "done-\(source.rawValue)",
            title: doneTitle(for: source),
            subtitle: title,
            source: source,
            timeSensitive: false
        )
    }

    /// `waiting`: urgentnija notifikacija (permission prompt itd. — §2.3, Claude Code v1).
    func notifyWaiting(source: Source, title: String?) {
        let s = settingsStore.settings
        guard s.notificationsEnabled, s.sourceSettings(for: source).notifyOnWaiting else { return }
        guard !isSuppressedByDND(settings: s) else {
            AppLog.info("notification suppressed by DND: \(source.rawValue) waiting")
            return
        }
        deliver(
            id: "waiting-\(source.rawValue)",
            title: waitingTitle(for: source),
            subtitle: title,
            source: source,
            timeSensitive: true
        )
    }

    /// „Test notification" iz per-source submenija (§3.3).
    func sendTest(source: Source) {
        deliver(
            id: "test-\(source.rawValue)",
            title: "\(StatusRendering.displayName(for: source)) — test notification",
            subtitle: "ClaudePulse radi.",
            source: source,
            timeSensitive: false
        )
    }

    private func deliver(id: String, title: String, subtitle: String?, source: Source, timeSensitive: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty { content.subtitle = subtitle }
        content.sound = nil  // zvuk ide preko SoundPlayer-a
        content.userInfo = ["source": source.rawValue]
        if timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        // Novi request sa istim id-om zamenjuje prethodni → nema gomilanja per (event, source).
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                AppLog.error("notification add error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - DND prozor (§3.4 Notifications)

    private func isSuppressedByDND(settings: Settings) -> Bool {
        guard settings.dndEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return Self.isWithinDND(hour: hour, start: settings.dndStartHour, end: settings.dndEndHour)
    }

    /// Da li je `hour` unutar [start, end). Wrap-around preko ponoći: start=22, end=8 → 22..23,0..7.
    /// Prazan prozor (start == end) tretiramo kao „nikad" (bez suppress-a).
    static func isWithinDND(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end {
            return hour >= start && hour < end
        }
        // Wrap-around: sve od start-a do ponoći ili od ponoći do end-a.
        return hour >= start || hour < end
    }

    // MARK: - Tekst (§3.5)

    private func doneTitle(for source: Source) -> String {
        switch source {
        case .code: return "Claude Code finished"
        case .web: return "Claude (browser) finished"
        case .desktop: return "Claude (desktop) finished"
        }
    }

    private func waitingTitle(for source: Source) -> String {
        switch source {
        case .code: return "Claude Code needs your input"
        case .web: return "Claude (browser) needs your input"
        case .desktop: return "Claude (desktop) needs your input"
        }
    }
}

// MARK: - Klik na notifikaciju → aktiviraj relevantnu app (§3.5, best effort)

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Prikaži i dok je app u prednjem planu (accessory app, ali može imati otvoren prozor).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["source"] as? String
        Task { @MainActor in
            if let raw, let source = Source(rawValue: raw) {
                Self.activateApp(for: source)
            }
            completionHandler()
        }
    }

    /// Aktiviraj app vezanu za izvor. `web` → default browser, `desktop`/`code` → poznati bundle id-ovi.
    private static func activateApp(for source: Source) {
        let workspace = NSWorkspace.shared
        switch source {
        case .web:
            // Otvori claude.ai u default browseru (fokusira ga best-effort).
            if let url = URL(string: "https://claude.ai") {
                workspace.open(url)
            }
        case .desktop:
            activateBundleID("com.anthropic.claudefordesktop", workspace: workspace)
        case .code:
            // Best effort: VS Code, pa Terminal. Ako nijedan → no-op.
            for bundleID in ["com.microsoft.VSCode", "com.apple.Terminal"] {
                if activateBundleID(bundleID, workspace: workspace) { return }
            }
        }
    }

    @discardableResult
    private static func activateBundleID(_ bundleID: String, workspace: NSWorkspace) -> Bool {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                AppLog.error("activate \(bundleID) failed: \(error.localizedDescription)")
            }
        }
        return true
    }
}
