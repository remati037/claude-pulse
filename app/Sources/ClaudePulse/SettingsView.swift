import SwiftUI
import UniformTypeIdentifiers

/// Kompletan tabovani Settings prozor (§3.4). SwiftUI kontrole vežu na `Settings` preko
/// `binding(_:)` helpera koji zove `store.update { }` → auto-persist + `onSettingsChanged`
/// (menu re-render / server restart u AppDelegate-u).
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let soundPlayer: SoundPlayer
    let desktopWatcher: DesktopWatcher

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            sourcesTab.tabItem { Label("Sources", systemImage: "dot.radiowaves.left.and.right") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell") }
            soundsTab.tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            advancedTab.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
    }

    // MARK: - Binding helper (jedno mesto → sve kontrole persistiraju)

    private func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func sourceKeyPath(_ source: Source) -> WritableKeyPath<Settings, SourceSettings> {
        switch source {
        case .code: return \.code
        case .web: return \.web
        case .desktop: return \.desktop
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.setEnabled($0) }
            ))

            Picker("Display mode", selection: binding(\.displayMode)) {
                Text("Compact (C● W● D●)").tag(DisplayMode.compact)
                Text("Icon only (one dot)").tag(DisplayMode.iconOnly)
            }

            Toggle("Show relative timestamps in menu", isOn: binding(\.showRelativeTimestamps))

            Section {
                TextField("Server port", value: binding(\.port), format: .number.grouping(.never))
                    .frame(width: 120)
                Text("Server restarts live on change. Hooks and the browser extension must use the same port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Sources

    private var sourcesTab: some View {
        Form {
            ForEach(Source.allCases, id: \.self) { source in
                let kp = sourceKeyPath(source)
                Section(StatusRendering.displayName(for: source)) {
                    Toggle("Enabled", isOn: binding(kp.appending(path: \.enabled)))
                    Stepper("TTL to inactive: \(store.settings[keyPath: kp].ttlMinutes) min",
                            value: binding(kp.appending(path: \.ttlMinutes)), in: 1...480)
                    Toggle("Auto-reset when done", isOn: binding(kp.appending(path: \.doneAutoResetEnabled)))
                    Stepper("Done auto-reset: \(store.settings[keyPath: kp].doneAutoResetMinutes) min",
                            value: binding(kp.appending(path: \.doneAutoResetMinutes)), in: 1...120)
                        .disabled(!store.settings[keyPath: kp].doneAutoResetEnabled)
                    Toggle("Notify on done", isOn: binding(kp.appending(path: \.notifyOnDone)))
                    Toggle("Notify on waiting", isOn: binding(kp.appending(path: \.notifyOnWaiting)))
                    if source == .desktop {
                        desktopAXControls
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Desktop-only AX kontrole (§2.4 / §3.4 Sources): permission status + grant, poll, label override.
    @ViewBuilder
    private var desktopAXControls: some View {
        HStack {
            Text("Accessibility permission")
            Spacer()
            if desktopWatcher.axPermissionGranted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Not granted", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        if !desktopWatcher.axPermissionGranted {
            Button("Grant Accessibility permission…") { desktopWatcher.requestPermission() }
        }
        Stepper("Poll interval: \(store.settings.desktopPollSeconds) s",
                value: binding(\.desktopPollSeconds), in: 1...10)
        TextField("Stop-button label pattern", text: binding(\.desktopStopLabelPattern))
        Text("Case-insensitive match on the Claude Desktop stop-generation button. Edit this if detection breaks after a Claude update — no app update needed.")
            .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: - Notifications

    private var notificationsTab: some View {
        Form {
            Toggle("Enable notifications", isOn: binding(\.notificationsEnabled))

            Section("Do Not Disturb") {
                Toggle("Suppress during a time window", isOn: binding(\.dndEnabled))
                Stepper("Start: \(hourLabel(store.settings.dndStartHour))",
                        value: binding(\.dndStartHour), in: 0...23)
                    .disabled(!store.settings.dndEnabled)
                Stepper("End: \(hourLabel(store.settings.dndEndHour))",
                        value: binding(\.dndEndHour), in: 0...23)
                    .disabled(!store.settings.dndEnabled)
            }

            Button("Open System Settings ▸ Notifications…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    // MARK: - Sounds

    private var soundsTab: some View {
        let sounds = SoundPlayer.availableSounds()
        return Form {
            Toggle("Enable sounds", isOn: binding(\.soundsEnabled))

            Picker("Done sound", selection: binding(\.doneSound)) {
                ForEach(sounds, id: \.self) { Text($0).tag($0) }
            }
            Picker("Waiting sound", selection: binding(\.waitingSound)) {
                ForEach(sounds, id: \.self) { Text($0).tag($0) }
            }

            HStack {
                Button("Preview done") { soundPlayer.play(named: store.settings.doneSound, volume: store.settings.volume) }
                Button("Preview waiting") { soundPlayer.play(named: store.settings.waitingSound, volume: store.settings.volume) }
            }

            Section("Volume") {
                Slider(value: binding(\.volume), in: 0...1)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        Form {
            Button("Open log file…") {
                NSWorkspace.shared.open(AppLog.fileURL)
            }
            Stepper("Stuck-busy threshold: \(store.settings.busyStuckThresholdMinutes) min",
                    value: binding(\.busyStuckThresholdMinutes), in: 5...240)

            Section("Settings file") {
                HStack {
                    Button("Export…") { exportSettings() }
                    Button("Import…") { importSettings() }
                }
                Text("Share your config with friends as a JSON file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "claudepulse-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(store.settings) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(Settings.self, from: data) else { return }
        store.replace(with: imported)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Text(appDisplayName).font(.title).bold()
            Text("Version \(appVersion)").foregroundStyle(.secondary)
            Link("GitHub", destination: URL(string: "https://github.com/")!)
            Button("Check for updates…") {
                if let url = URL(string: "https://github.com/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
