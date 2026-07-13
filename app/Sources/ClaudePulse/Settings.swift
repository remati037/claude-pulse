import Foundation
import SwiftUI

/// Način prikaza u menu baru (§3.2).
enum DisplayMode: String, Codable {
    case compact    // `C● W● D✕`
    case iconOnly   // jedna tačka = agregatno stanje
}

/// Podešavanja po izvoru (§3.4 Sources). Isto za code/web/desktop.
struct SourceSettings: Codable, Equatable {
    var enabled: Bool = true
    /// TTL do `inactive` u minutima (default 30). `busy` ne ističe po TTL-u (vidi StatusStore).
    var ttlMinutes: Int = 30
    var doneAutoResetEnabled: Bool = true
    /// `done → inactive` posle N minuta (default 10) da bar ne ostane zelen zauvek.
    var doneAutoResetMinutes: Int = 10
    /// Notifikacije po izvoru (koristi se u Phase 3).
    var notifyOnDone: Bool = true
    var notifyOnWaiting: Bool = true
}

/// Kompletan §3.4 skup podešavanja. Definisano celo već sad da Phase 2/3 ne diraju model;
/// Phase 1 realno čita: `port`, per-source `enabled`/`ttl`/done-reset, `busyStuckThresholdMinutes`.
struct Settings: Codable, Equatable {
    // General
    var port: Int = 4242
    var displayMode: DisplayMode = .compact
    var showRelativeTimestamps: Bool = true

    // Sources
    var code: SourceSettings = SourceSettings()
    var web: SourceSettings = SourceSettings()
    var desktop: SourceSettings = SourceSettings()

    // Notifications (master + DND; per-source je u SourceSettings)
    var notificationsEnabled: Bool = true
    var dndEnabled: Bool = false
    /// DND prozor, sat u 24h formatu (npr. 22 → 8 znači 22:00–08:00).
    var dndStartHour: Int = 22
    var dndEndHour: Int = 8

    // Sounds
    var soundsEnabled: Bool = true
    var doneSound: String = "Glass"
    var waitingSound: String = "Ping"
    var volume: Double = 1.0

    // Advanced
    /// `busy` koji visi duže od ovoga → `inactive` (hook/ekstenzija verovatno umrli, §2.3).
    var busyStuckThresholdMinutes: Int = 45

    // Onboarding
    /// Prvo pokretanje pokazuje onboarding (§3.6); posle se dostavlja preko „Setup Guide…".
    var hasCompletedOnboarding: Bool = false
}

/// Perzistencija `Settings`-a: JSON pod jednim ključem u `UserDefaults`.
///
/// `ObservableObject` (ne `@Observable` macro — traži macOS 14, min je 13; vidi ADR-006) da
/// SwiftUI Settings prozor menja vrednosti uživo. `@MainActor` jer mu pristupaju i menu bar UI
/// i StatusStore (oba na main-u). `onSettingsChanged` javlja AppDelegate-u da re-renderuje menu
/// bar i, ako se promenio port, restartuje HTTP server.
@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "settings"

    private let defaults: UserDefaults
    @Published private(set) var settings: Settings

    /// Poziva se posle svake `update`/`replace` — AppDelegate se kači ovde.
    var onSettingsChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = Settings()
        }
    }

    func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        save()
        onSettingsChanged?()
    }

    /// Zameni ceo `Settings` (import iz JSON-a, §3.4 Advanced).
    func replace(with newSettings: Settings) {
        settings = newSettings
        save()
        onSettingsChanged?()
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
