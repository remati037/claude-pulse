# CLAUDE-NOTIFIER-PLAN.md — "ClaudePulse" Build Plan

> Menu bar app for macOS that shows, at a glance, whether Claude is busy or done —
> across **Claude Code** (terminal / VS Code), **claude.ai in the browser**, and the
> **Claude Desktop app**. Built for personal use first, distributable to friends via
> GitHub Releases from day one.

This document is written for autonomous execution by Claude Code. Work through the
phases in order. Do not start a phase until the previous phase's acceptance criteria
all pass. Log every non-obvious decision in `DECISIONS.md` (ADR style).

---

## 1. Product Overview

### 1.1 The problem
When Claude works on a long task, the user switches away and has no way to know the
moment it finishes. The result: constant tab-checking or forgotten sessions.

### 1.2 The solution
A single menu bar item showing three independent status slots:

```
◉ C  ◉ W  ◉ D        (C = Code, W = Web/browser, D = Desktop app)
```

Per-slot states:

| State     | Visual        | Meaning                                            |
|-----------|---------------|----------------------------------------------------|
| `inactive`| gray `✕`      | Source not in use (no events within TTL, or source disabled in settings) |
| `busy`    | red `●`       | Claude is generating / working                     |
| `waiting` | orange `●`    | Claude is waiting for user input (permission prompt etc. — Claude Code only in v1) |
| `done`    | green `●`     | Claude finished; result is waiting for the user    |

On `busy → done` transition: macOS push notification (UNUserNotificationCenter) +
optional sound. Clicking the notification focuses the relevant app (best effort).

### 1.3 Components (monorepo layout)

```
claudepulse/
├── CLAUDE.md                    # rules for Claude Code working in this repo
├── DECISIONS.md                 # ADR log
├── README.md                    # user-facing: install, setup, screenshots
├── app/                         # Swift menu bar app (SwiftUI + AppKit)
│   └── ClaudePulse.xcodeproj (or Package.swift — see ADR-001)
├── extension/                   # Chrome MV3 extension for claude.ai
├── hooks/                       # Claude Code hook payloads + installer
│   └── install-hooks.sh
├── scripts/
│   ├── install.sh               # one-line installer for friends
│   └── release.sh               # build + zip + checksum for GitHub Release
└── docs/
    └── TROUBLESHOOTING.md
```

### 1.4 Non-goals for v1
- Windows/Linux support
- iOS companion / remote notifications
- Menu bar app auto-updating (v1: manual download; note Sparkle as v2 candidate)
- Signed/notarized builds (unsigned + documented Gatekeeper bypass)

---

## 2. Architecture

### 2.1 Event flow

```
 Claude Code hooks ──curl──►┐
 Chrome extension ──fetch──►│  HTTP server (localhost:4242, configurable)
                            │  inside the menu bar app
 Desktop AX watcher ────────►  (in-process, no HTTP needed)
                            │
                            ▼
                      StatusStore (single source of truth)
                            │
              ┌─────────────┼──────────────┐
              ▼             ▼              ▼
        Menu bar icon   Notifications   Sounds
```

### 2.2 HTTP API (localhost only)

`POST /status` — body:
```json
{ "source": "code" | "web", "state": "busy" | "waiting" | "done", "meta": { "title": "optional context string" } }
```
Responses: `200 {"ok":true}`, `400` on invalid payload.

`GET /health` — returns `{"ok":true,"version":"1.0.0"}`. Used by the extension to
detect that the app is running and by install scripts for verification.

Rules:
- Bind to `127.0.0.1` ONLY. Never `0.0.0.0`.
- Reject bodies > 4 KB.
- No auth in v1 (localhost-only attack surface is acceptable; log as ADR).

### 2.3 State machine (per source)

- Any event sets the slot to the received state and refreshes `lastEventAt`.
- `busy → done` fires notification + sound (respecting per-source settings).
- `waiting` fires a distinct (more urgent) notification if enabled.
- TTL sweep every 30 s: if `lastEventAt` older than TTL (default 30 min, configurable)
  → slot becomes `inactive`. Exception: `busy` state never expires via TTL alone —
  instead, after `busyStuckThreshold` (default 45 min) mark it `inactive` and log,
  since a hook/extension may have died mid-task.
- `done` auto-reset (optional, default ON): `done → inactive` after N minutes
  (default 10) so the bar doesn't stay green forever.
- Manual per-slot reset from the menu.

### 2.4 Desktop app detection (Accessibility API)

No hooks or DOM access exist for the Claude Desktop app (Electron). Strategy:

1. Poll every 2 s (only while the "Claude" app is running — check via
   `NSWorkspace.shared.runningApplications`; skip polling entirely when not running
   → zero idle cost, slot shows `inactive`).
2. Use `AXUIElement` to walk the frontmost window of the Claude process and search
   for the **stop-generation button** (Electron exposes web contents through the
   AX tree; buttons have `AXRole = AXButton` with an accessibility
   label/description containing "stop" — determine the exact
   label empirically in Phase 4 and store it in a user-editable config value,
   NOT hardcoded, so users can fix it after Anthropic UI changes without an app update).
3. Stop button present → `busy`. Was `busy` and button gone for 2 consecutive polls
   (debounce) → `done`.
4. If AX permission is missing → slot shows `inactive` with a menu hint
   "Grant Accessibility permission…" that deep-links to System Settings.

Known limitation (document in README): only detects the frontmost window's state
reliably; minimized-window behavior must be tested in Phase 4 and documented.

### 2.5 Browser detection (Chrome MV3 extension)

- Content script on `https://claude.ai/*`.
- Detect "busy" via presence of the stop-streaming button. Use a **configurable
  selector list** stored in `chrome.storage.sync` with sane defaults (e.g.
  `button[aria-label*="Stop"]`), editable from the extension options page —
  same rationale as 2.4: survive UI changes without republishing.
- MutationObserver + 2 s debounce before reporting `done` (avoids false "done"
  between tool calls / artifact renders).
- Multiple tabs: background service worker aggregates — if ANY claude.ai tab is
  busy → `web=busy`; when the last busy tab finishes → `web=done`.
- Extension pings `GET /health` on startup; if the app isn't running, badge the
  extension icon gray and retry with backoff (no console spam).
- Host permission: `http://127.0.0.1:4242/*` (+ handle custom port via options page).

### 2.6 Claude Code integration (hooks)

`hooks/install-hooks.sh` merges (never overwrites) into `~/.claude/settings.json`:

| Hook               | Payload state |
|--------------------|---------------|
| `UserPromptSubmit` | `busy`        |
| `PreToolUse`       | `busy` (refreshes TTL during long sessions) |
| `Stop`             | `done`        |
| `Notification`     | `waiting`     |

Command form (single line, fail-silent so hooks never break Claude Code):
```bash
curl -s -m 2 -X POST http://127.0.0.1:4242/status \
  -H 'Content-Type: application/json' \
  -d '{"source":"code","state":"done"}' >/dev/null 2>&1 || true
```
The installer must use `jq` (bundled check + friendly error) to merge JSON, create a
timestamped backup of settings.json first, and support `--uninstall`.

---

## 3. Menu Bar App Spec (Swift)

### 3.1 Tech decisions (log each as ADR)
- **Language/UI**: Swift 5.9+, SwiftUI for Settings window, AppKit `NSStatusItem`
  for the menu bar (SwiftUI MenuBarExtra is acceptable if it supports the
  attributed-string status rendering below; verify in Phase 2 and record ADR).
- **HTTP server**: `Network.framework` (`NWListener`) — zero dependencies.
  No third-party packages in v1 unless something proves unworkable (ADR required).
- **Min macOS**: 13.0 (Ventura) — needed for `SMAppService` login item API.
- **Persistence**: `UserDefaults` via a `Settings` struct (Codable).
- **App name**: ClaudePulse (working name; trivially renamable — keep the bundle
  display name in one config constant).

### 3.2 Menu bar rendering
- Compact mode (default): `C● W● D✕` as an attributed string with colored dots.
- Icon-only mode: single dot showing the "most urgent" aggregate state
  (any busy → red; else any waiting → orange; else any done → green; else gray).
- Respect Reduce Transparency / dark & light menu bar automatically (use template-
  friendly colors; test both appearances).

### 3.3 Menu (left click) — full contents
```
C  Claude Code      ● Busy        (row per source: name + state + relative time "2m ago")
W  Browser          ● Done 2m ago
D  Desktop          ✕ Inactive
──────────────────────────────
Reset all to inactive
──────────────────────────────
Notifications            ✓        (toggle)
Sounds                   ✓        (toggle)
──────────────────────────────
Settings…                         (opens Settings window)
Setup Guide…                      (opens README anchor / local HTML)
──────────────────────────────
Launch at Login          ✓
Quit ClaudePulse
```
Each source row is itself a submenu: `Enable/Disable source`, `Reset`,
`Test notification`.

### 3.4 Settings window (SwiftUI, tabbed) — "bukvalno sve"
**General**
- Launch at login (SMAppService)
- Display mode: compact / icon-only
- Show relative timestamps in menu (on/off)
- Server port (default 4242) + "restart server" applied live + warning that
  hooks/extension must match

**Sources** (per source: Code / Web / Desktop)
- Enable/disable
- TTL to inactive (minutes)
- Done auto-reset (on/off + minutes)
- Desktop only: AX permission status + grant button, poll interval, stop-button
  label override field

**Notifications**
- Master toggle
- Per source: notify on done (on/off), notify on waiting (on/off)
- Notification style hint (banner vs alert is a system setting — show a button
  that opens System Settings > Notifications)
- Do-not-disturb window (e.g. suppress 22:00–08:00, off by default)

**Sounds**
- Master toggle
- Per event (done / waiting): choose from bundled system sounds
  (`NSSound(named:)` list: Glass, Ping, Hero, …) + preview button
- Volume slider

**Advanced**
- Open log file (app logs to `~/Library/Logs/ClaudePulse/`)
- `busyStuckThreshold` minutes
- Export/import settings as JSON (nice for sharing configs with friends)

**About**
- Version, GitHub link, "Check for updates" (v1: opens the Releases page)

### 3.5 Notifications
- `UNUserNotificationCenter`; request permission on first launch with a short
  explanation screen (one-time onboarding window, see 3.6).
- Done: "Claude Code finished" / "Claude (browser) finished" (+ `meta.title` if
  provided as subtitle).
- Clicking the notification: for `web` → activate the default browser; for `code`
  → activate Terminal/VS Code if identifiable, else no-op; for `desktop` →
  activate the Claude app. Best effort via `NSWorkspace`.

### 3.6 First-run onboarding (single window, 3 steps)
1. Notification permission request + sound test.
2. "Install Claude Code hooks" button → runs the bundled installer script
   (or shows the copy-paste command if the script can't be executed from the
   sandbox — v1 app is NOT sandboxed, record as ADR, so direct execution is fine).
3. Browser extension: button opens `chrome://extensions` instructions page;
   Desktop: Accessibility permission prompt + explanation.
   Every step skippable; onboarding reachable later via "Setup Guide…".

---

## 4. Phases & Acceptance Criteria

### Phase 0 — Repo scaffold
Tasks: repo layout from 1.3, CLAUDE.md (build/test commands, Swift style rules,
"never bind non-localhost", ADR requirement), DECISIONS.md with ADR-001
(Xcode project vs SwiftPM executable — pick one, justify), README skeleton.
**Done when:** repo builds an empty menu bar app showing a static `C✕ W✕ D✕`;
`swift build`/`xcodebuild` passes clean.

### Phase 1 — Core: StatusStore + HTTP server
Tasks: `Settings` model, `StatusStore` (thread-safe, main-actor published state),
state machine from 2.3 incl. TTL sweep + stuck-busy handling, `NWListener` server
with `POST /status` + `GET /health`, structured logging.
**Done when:** `curl` transitions are reflected in the menu bar within 500 ms;
invalid payloads return 400 and don't crash; TTL and auto-reset verified with
short test values; server survives 1000-request loop (`for i in $(seq 1000)…`).

### Phase 2 — Menu bar UI + menu
Tasks: attributed-string rendering (compact + icon-only), full menu from 3.3,
per-source submenus, dark/light appearance check.
**Done when:** every menu item functions; state changes re-render live; display
mode switch applies without restart.

### Phase 3 — Notifications, sounds, Settings window, onboarding
Tasks: UNUserNotificationCenter flow, per-source rules, DND window, sound engine +
preview, complete tabbed Settings (3.4), onboarding (3.6), SMAppService login item,
settings export/import.
**Done when:** busy→done produces exactly one notification + one sound per event;
all toggles persist across relaunch; DND window suppresses correctly; login item
verified after reboot (or `SMAppService` status check).

### Phase 4 — Desktop app watcher (AX)
Tasks: process detection, AX polling per 2.4, empirical discovery of the stop
button label (document findings in DECISIONS.md), user-editable label override,
permission UX, debounce.
**Done when:** with the real Claude Desktop app: sending a long prompt turns D red
within 4 s, completion turns it green within 4 s + notification; quitting the app
turns D to ✕; missing AX permission degrades gracefully with menu hint.

### Phase 5 — Claude Code hooks installer
Tasks: `install-hooks.sh` per 2.6 (jq merge, backup, --uninstall, port parameter),
manual test with a real Claude Code session incl. permission prompt → `waiting`.
**Done when:** fresh install on a machine with existing custom hooks preserves
them; C slot correctly cycles red → orange (on permission prompt) → red → green
during a real session; uninstall restores prior settings.json semantics.

### Phase 6 — Chrome extension
Tasks: MV3 extension per 2.5 (content script, service worker aggregation, options
page with selector list + port, health-check badge), README section with unpacked-
install instructions.
**Done when:** real claude.ai session: W turns red while streaming, green ≤ 3 s
after completion, no false "done" during multi-tool responses; two-tab test passes
(one busy tab keeps W red); app-not-running shows gray badge without errors.

### Phase 7 — Distribution
Tasks: `release.sh` (Release build, `.app` zip, SHA-256, version stamp),
`scripts/install.sh` one-liner (download latest release, unquarantine via
`xattr -dr com.apple.quarantine`, move to /Applications, launch), README polish
(screenshots, friend-proof setup for all three sources, Gatekeeper explanation:
right-click → Open on first launch), TROUBLESHOOTING.md (port conflict, AX broke
after Claude update → edit label override, selector broke → edit in extension
options), GitHub Release v1.0.0 checklist.
**Done when:** a clean macOS user account can go from README → fully working
three-source setup in under 10 minutes using only documented steps.

---

## 5. Risks & Accepted Tradeoffs

| Risk | Mitigation | Status |
|---|---|---|
| Anthropic changes Desktop UI → AX detection breaks | User-editable label override; TROUBLESHOOTING entry | Accepted |
| claude.ai DOM changes → extension breaks | User-editable selector list in options page | Accepted |
| Unsigned app → Gatekeeper friction for friends | install.sh unquarantine + README right-click-Open guide; revisit signing if adoption grows | Accepted |
| No auth on localhost server | localhost-only bind, 4 KB body cap; any local process could spoof status (cosmetic impact only) | Accepted |
| Chrome-only extension in v1 | Architecture is browser-agnostic (plain fetch); Firefox/Safari ports are v2 | Accepted |

## 6. v2 Candidates (do not build now)
Sparkle auto-update · signed/notarized build · Safari & Firefox extensions ·
per-project labels from Claude Code hooks (`meta.title` from `$CLAUDE_PROJECT_DIR`) ·
menu bar history ("last 10 completions") · webhook out (notify phone via ntfy.sh).
