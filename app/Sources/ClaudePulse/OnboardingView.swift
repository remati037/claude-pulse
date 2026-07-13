import SwiftUI

/// Onboarding u 3 koraka (§3.6). Svaki korak skippable; poziva `onFinish` na kraju/skip-u,
/// što setuje `hasCompletedOnboarding` i zatvara prozor (AppDelegate).
///
/// VAŽNO: korak 2 (hooks) je **samo informativan** — app ne pokreće installer sam (CLAUDE.md
/// zabranjuje diranje `~/.claude/settings.json` bez korisnikove akcije). Nudimo komandu za
/// pokretanje `hooks/install-hooks.sh` (koji radi backup + jq merge) i copy-paste curl fallback.
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
            Text("Claude Code reports status through hooks. Run the bundled installer once — it backs up and merges into ~/.claude/settings.json (your custom hooks are preserved):")
                .foregroundStyle(.secondary)
            Text("bash hooks/install-hooks.sh")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Undo anytime with  bash hooks/install-hooks.sh --uninstall")
                .font(.caption)
                .foregroundStyle(.secondary)
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
