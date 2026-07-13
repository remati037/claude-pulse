import AppKit
import SwiftUI

/// Prozor onboarding-a (§3.6). Prikazuje se na prvom pokretanju i preko „Setup Guide…".
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let notificationManager: NotificationManager
    private let soundPlayer: SoundPlayer
    private let settingsStore: SettingsStore

    init(notificationManager: NotificationManager, soundPlayer: SoundPlayer, settingsStore: SettingsStore) {
        self.notificationManager = notificationManager
        self.soundPlayer = soundPlayer
        self.settingsStore = settingsStore
    }

    func show() {
        if window == nil {
            let view = OnboardingView(
                requestNotifications: { [weak self] in self?.notificationManager.requestAuthorization() },
                testSound: { [weak self] in
                    guard let self else { return }
                    self.soundPlayer.play(named: self.settingsStore.settings.doneSound,
                                          volume: self.settingsStore.settings.volume)
                },
                onFinish: { [weak self] in self?.finish() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to \(appDisplayName)"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        settingsStore.update { $0.hasCompletedOnboarding = true }
        window?.close()
    }
}
