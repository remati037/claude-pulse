import Foundation

/// Tri nezavisna izvora statusa (§1.2). `code`/`web` stižu preko HTTP-a; `desktop` in-process (Phase 4).
enum Source: String, CaseIterable {
    case code, web, desktop
}

/// Stanje po slotu (§1.2). `inactive` je interno (TTL/reset); ne prima se preko API-ja.
enum SourceState: String {
    case inactive, busy, waiting, done
}

/// Trenutno stanje jednog izvora + kad je stigao poslednji event (za TTL/stuck/auto-reset).
struct SourceStatus {
    var state: SourceState = .inactive
    var lastEventAt: Date?
}

extension Settings {
    /// Per-source podešavanja po `Source` enumu.
    func sourceSettings(for source: Source) -> SourceSettings {
        switch source {
        case .code: return code
        case .web: return web
        case .desktop: return desktop
        }
    }
}

/// Jedinstveni izvor istine za stanje sva tri slota + state machine iz §2.3.
///
/// `@MainActor`: sav pristup ide preko main actora → thread-safe bez zaključavanja.
/// HTTP handler (na pozadinskom queue-u) hop-uje na main pre `apply(...)`.
@MainActor
final class StatusStore {
    private(set) var statuses: [Source: SourceStatus] = [
        .code: SourceStatus(),
        .web: SourceStatus(),
        .desktop: SourceStatus(),
    ]

    /// Menu bar re-render (AppDelegate ga postavlja). Bez Combine — zero-dep (ADR-003 duh).
    var onChange: (() -> Void)?
    /// Phase 3 stubovi: notifikacija + zvuk na tranzicijama. U Phase 1 se samo loguju.
    var onBusyToDone: ((Source) -> Void)?
    var onWaiting: ((Source) -> Void)?

    private let settingsStore: SettingsStore

    /// Test override-i u sekundama (env varijable) — za autonomnu verifikaciju bez čekanja minutima.
    private let ttlOverride: TimeInterval?
    private let doneResetOverride: TimeInterval?
    private let stuckOverride: TimeInterval?

    private var sweepTimer: Timer?
    private let sweepInterval: TimeInterval

    init(settingsStore: SettingsStore, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.settingsStore = settingsStore
        self.ttlOverride = Self.seconds(environment["CLAUDEPULSE_TTL_SECONDS"])
        self.doneResetOverride = Self.seconds(environment["CLAUDEPULSE_DONE_RESET_SECONDS"])
        self.stuckOverride = Self.seconds(environment["CLAUDEPULSE_STUCK_SECONDS"])

        // Kad su test override-i aktivni, kratke vrednosti (npr. 2 s) treba osmatrati češće od 30 s.
        let hasOverride = ttlOverride != nil || doneResetOverride != nil || stuckOverride != nil
        self.sweepInterval = hasOverride ? 1 : 30
    }

    private static func seconds(_ raw: String?) -> TimeInterval? {
        guard let raw, let value = TimeInterval(raw) else { return nil }
        return value
    }

    // MARK: - Efektivne vrednosti (env override → sekunde, inače Settings → minuti*60)

    private func ttl(for s: SourceSettings) -> TimeInterval {
        ttlOverride ?? TimeInterval(s.ttlMinutes * 60)
    }

    private func doneReset(for s: SourceSettings) -> TimeInterval {
        doneResetOverride ?? TimeInterval(s.doneAutoResetMinutes * 60)
    }

    private var stuckThreshold: TimeInterval {
        stuckOverride ?? TimeInterval(settingsStore.settings.busyStuckThresholdMinutes * 60)
    }

    // MARK: - Životni ciklus

    func start() {
        let timer = Timer(timeInterval: sweepInterval, repeats: true) { [weak self] _ in
            // Timer callback je na main runloop-u; hop na main actor radi izolacije.
            Task { @MainActor in self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
        AppLog.info("StatusStore started (sweep=\(sweepInterval)s, stuck=\(stuckThreshold)s)")
    }

    // MARK: - Primena eventa

    /// Primeni event izvora (poziva HTTP handler nakon hop-a na main actor).
    func apply(source: Source, state: SourceState) {
        let sourceSettings = settingsStore.settings.sourceSettings(for: source)
        guard sourceSettings.enabled else {
            AppLog.info("ignoring \(source.rawValue)=\(state.rawValue): source disabled")
            return
        }

        let previous = statuses[source]?.state ?? .inactive

        var status = statuses[source] ?? SourceStatus()
        status.state = state
        status.lastEventAt = Date()
        statuses[source] = status

        AppLog.info("\(source.rawValue): \(previous.rawValue) → \(state.rawValue)")

        // Tranzicije (Phase 3 stubovi).
        if previous == .busy, state == .done {
            AppLog.info("event: \(source.rawValue) busy→done")
            onBusyToDone?(source)
        }
        if state == .waiting, previous != .waiting {
            AppLog.info("event: \(source.rawValue) waiting")
            onWaiting?(source)
        }

        onChange?()
    }

    /// Ručni reset jednog slota na `inactive` (meni „Reset").
    func reset(source: Source) {
        statuses[source] = SourceStatus()
        AppLog.info("\(source.rawValue): manual reset → inactive")
        onChange?()
    }

    /// Reset svih slotova na `inactive`.
    func resetAll() {
        for source in Source.allCases {
            statuses[source] = SourceStatus()
        }
        AppLog.info("manual reset all → inactive")
        onChange?()
    }

    // MARK: - TTL / stuck-busy / done auto-reset sweep (§2.3)

    private func sweep() {
        let now = Date()
        var changed = false

        for source in Source.allCases {
            guard let status = statuses[source], let last = status.lastEventAt else { continue }
            let age = now.timeIntervalSince(last)
            let s = settingsStore.settings.sourceSettings(for: source)

            switch status.state {
            case .busy:
                // `busy` NE ističe po TTL-u; samo ako visi predugo → verovatno mrtav hook (§2.3).
                if age > stuckThreshold {
                    statuses[source] = SourceStatus()
                    AppLog.info("\(source.rawValue): busy stuck > \(Int(stuckThreshold))s → inactive")
                    changed = true
                }
            case .done:
                // Auto-reset (kraći) ili TTL — oba vode u inactive; loguje se razlog.
                if s.doneAutoResetEnabled, age > doneReset(for: s) {
                    statuses[source] = SourceStatus()
                    AppLog.info("\(source.rawValue): done auto-reset > \(Int(doneReset(for: s)))s → inactive")
                    changed = true
                } else if age > ttl(for: s) {
                    statuses[source] = SourceStatus()
                    AppLog.info("\(source.rawValue): done TTL > \(Int(ttl(for: s)))s → inactive")
                    changed = true
                }
            case .waiting:
                if age > ttl(for: s) {
                    statuses[source] = SourceStatus()
                    AppLog.info("\(source.rawValue): waiting TTL > \(Int(ttl(for: s)))s → inactive")
                    changed = true
                }
            case .inactive:
                break
            }
        }

        if changed { onChange?() }
    }
}
