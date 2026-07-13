import SwiftUI

/// Onboarding u 3 koraka (§3.6). Svaki korak skippable; poziva `onFinish` na kraju/skip-u,
/// što setuje `hasCompletedOnboarding` i zatvara prozor (AppDelegate).
///
/// VAŽNO: korak 2 (hooks) je **samo informativan** — pravi installer je Phase 5, i CLAUDE.md
/// zabranjuje diranje `~/.claude/settings.json` bez najave. Ovde nudimo copy-paste komandu.
struct OnboardingView: View {
    let requestNotifications: () -> Void
    let testSound: () -> Void
    let onFinish: () -> Void

    @State private var step = 0
    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)

            Divider()

            HStack {
                Button("Skip") { onFinish() }
                Spacer()
                Text("Step \(step + 1) of \(lastStep + 1)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if step < lastStep {
                    Button("Next") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { onFinish() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 380)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: notificationsStep
        case 1: hooksStep
        default: sourcesStep
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notifications & sound").font(.title2).bold()
            Text("ClaudePulse notifies you the moment Claude finishes. Allow notifications so it can reach you when you've switched away.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Allow notifications") { requestNotifications() }
                Button("Test sound") { testSound() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hooksStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Code (terminal)").font(.title2).bold()
            Text("Claude Code reports status through hooks. The one-click installer arrives in a later version; for now you can add it manually.")
                .foregroundStyle(.secondary)
            Text("curl -s -m 2 -X POST http://127.0.0.1:4242/status -H 'Content-Type: application/json' -d '{\"source\":\"code\",\"state\":\"done\"}'")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourcesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browser & Desktop").font(.title2).bold()
            Text("• Browser (claude.ai): load the extension — coming in a later phase.")
                .foregroundStyle(.secondary)
            Text("• Desktop app: ClaudePulse needs Accessibility permission to detect when the Claude app is working — you'll be prompted when that source is enabled.")
                .foregroundStyle(.secondary)
            Text("You're all set. You can reopen this guide anytime from the menu ▸ Setup Guide…")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
