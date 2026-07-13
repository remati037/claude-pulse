# ClaudePulse — Izvršni plan implementacije

> Pojednostavljeni izvršni plan; [CLAUDE-NOTIFIER-PLAN.md](CLAUDE-NOTIFIER-PLAN.md) ostaje
> izvor istine za detalje (sekcije se referenciraju kao §2.3 itd.). Radi se faza po faza,
> sa checkpoint-om za korisnika (Marko) posle svake.

## Context

macOS menu bar app koji pokazuje da li je Claude zauzet/gotov kroz tri izvora — Claude Code
(hooks), claude.ai u browseru (MV3 ekstenzija) i Claude Desktop app (Accessibility API).

**Dogovoreno sa korisnikom (2026-07-13):**
- **ADR-001: SwiftPM executable + bundle skripta** (nema Xcode-a na mašini, samo CLT + Swift 6.1.2). Skripta pakuje binary u `ClaudePulse.app`.
- **Checkpoint posle svake faze** — implementirati, verifikovati šta se može autonomno, pa javiti korisniku šta ručno da proveri pre nastavka.

## Činjenice o okruženju (proverene 2026-07-13)

- macOS 26.5, Swift 6.1.2, **nema Xcode-a** (`xcodebuild` ne radi) → sve preko `swift build`.
- `jq` postoji (`/usr/bin/jq`) — hooks installer ga može koristiti.
- `/Applications/Claude.app` postoji → Phase 4 testabilna.
- **Nema Chrome-a; ima Brave** → ekstenziju testiramo u Brave-u (MV3 kompatibilan). README piše "Chrome/Chromium (Brave, Edge…)".
- Direktorijum nije git repo → `git init` u Phase 0.

## Ključne tehničke odluke (upisati kao ADR-ove u DECISIONS.md)

1. **ADR-001**: SwiftPM executable target, min macOS 13. Build: `scripts/build-app.sh` → `swift build -c release`, sklapa `ClaudePulse.app` (Info.plist sa `LSUIElement=true` — bez dock ikone, `CFBundleIdentifier=com.marko.claudepulse`), pa **ad-hoc codesign** (`codesign --force --sign -`) — bez toga `UNUserNotificationCenter` ne radi.
2. **ADR-002**: Ručni AppKit lifecycle (`NSApplication` + `AppDelegate`, bez SwiftUI `@main App`) jer `UNUserNotificationCenter` i `NSStatusItem` traže pravi bundle, a `MenuBarExtra` ne podržava attributed-string rendering iz §3.2 → `NSStatusItem` za menu bar, `NSWindow` + `NSHostingController` za SwiftUI Settings/onboarding prozore.
3. **ADR-003**: `Network.framework` `NWListener` za HTTP, ručni minimalni HTTP parsing (samo POST /status i GET /health), bind isključivo `127.0.0.1`.
4. **ADR-004**: App nije sandboxovan (treba mu AX API + pokretanje installer skripte).
5. **ADR-005**: Bez auth-a na localhost serveru (v1, cosmetic-only impact).

VAŽNO: `UNUserNotificationCenter` **pada** ako se binary pokrene van .app bundle-a → app se uvek pokreće kao `.app`; notifikacioni kod defanzivno proverava `Bundle.main.bundleIdentifier`.

## Faze

Svaka faza: implementiraj → verifikuj sam → **checkpoint poruka korisniku** (šta je urađeno + šta on ručno proverava) → tek onda sledeća faza. Odluke logovati u DECISIONS.md. Kraj svake faze: git commit.

### Phase 0 — Scaffold
- `git init`; struktura iz §1.3 (`app/`, `extension/`, `hooks/`, `scripts/`, `docs/`).
- `CLAUDE.md` (build/test komande, pravila: never bind non-localhost, ADR obaveza), `DECISIONS.md` (ADR-001..005), `README.md` skelet.
- `app/Package.swift` (executable, platform .macOS(13)), minimalni `AppDelegate` + `NSStatusItem` sa statičnim `C✕ W✕ D✕`.
- `scripts/build-app.sh` (build + bundle + codesign) i `scripts/dev-run.sh` (build + pokreni .app).
- **Done:** `swift build` čist; `build-app.sh` proizvodi .app koji pokazuje `C✕ W✕ D✕` u menu baru. **Checkpoint:** korisnik vidi ikonu u menu baru.

### Phase 1 — StatusStore + HTTP server
- `Settings` (Codable, UserDefaults) sa svim vrednostima iz §3.4 (port 4242, TTL-ovi, toggles…).
- `StatusStore` (@MainActor, published state; per-source: state + lastEventAt) + state machine §2.3: TTL sweep 30 s, `busyStuckThreshold` 45 min, done auto-reset 10 min, busy→done event hook.
- `HTTPServer` (NWListener): `POST /status` (validacija source/state, 400 na nevalidno, body cap 4 KB), `GET /health` (`{"ok":true,"version":…}`).
- Logging u `~/Library/Logs/ClaudePulse/` (jednostavan file logger + os.Logger).
- **Done:** curl tranzicije vidljive u menu baru <500 ms; loop od 1000 requestova preživljava; TTL/auto-reset verifikovan sa kratkim test vrednostima. Kompletno testabilno autonomno curl-om.

### Phase 2 — Menu bar UI + meni
- Attributed string rendering: compact `C● W● D✕` (boje po stanju) + icon-only mod (agregat: busy > waiting > done > inactive); light/dark provera.
- Pun meni iz §3.3: red po izvoru (ime + stanje + "2m ago") sa submenijem (Enable/Disable, Reset, Test notification), Reset all, Notifications/Sounds toggles, Settings…, Setup Guide…, Launch at Login, Quit.
- **Done:** sve stavke rade, live re-render, promena display moda bez restarta. **Checkpoint:** korisnik proveri izgled u light/dark.

### Phase 3 — Notifikacije, zvuci, Settings prozor, onboarding
- `UNUserNotificationCenter`: permission flow, busy→done i waiting notifikacije po per-source pravilima, DND prozor (npr. 22–08), klik na notifikaciju aktivira relevantnu app (best effort, `NSWorkspace`).
- Zvuci: `NSSound(named:)` lista, preview, volume.
- SwiftUI Settings prozor sa tabovima General/Sources/Notifications/Sounds/Advanced/About (§3.4), export/import settings JSON.
- Onboarding (3 koraka, §3.6), `SMAppService` login item.
- **Done:** tačno 1 notifikacija + 1 zvuk po busy→done; sve persistira preko relaunch-a; DND suprimira. **Checkpoint:** korisnik odobri notification permission i čuje test zvuk.

### Phase 4 — Desktop watcher (AX) — treba korisnik
- `NSWorkspace` detekcija Claude procesa (bundle id `com.anthropic.claudefordesktop` — potvrditi iz `/Applications/Claude.app/Contents/Info.plist`); poll 2 s samo dok app radi.
- AX walk frontmost prozora → traži stop dugme; **label pattern u Settings, ne hardkodiran**; empirijski naći label (korisnik pošalje dug prompt dok pomoćna skripta čita AX tree) → nalaz u DECISIONS.md.
- Debounce: 2 uzastopna poll-a bez dugmeta → done. AX permission UX: menu hint + deep-link u System Settings.
- **Done/Checkpoint:** korisnik da AX permission, pošalje dug prompt → D crveno ≤4 s, zeleno ≤4 s po završetku + notifikacija; quit → ✕. Dokumentovati ponašanje minimizovanog prozora.

### Phase 5 — Claude Code hooks installer — treba korisnik
- `hooks/install-hooks.sh`: jq merge (nikad overwrite) u `~/.claude/settings.json`, timestamped backup, `--uninstall`, `--port`; hookovi iz §2.6 (UserPromptSubmit/PreToolUse→busy, Stop→done, Notification→waiting), curl fail-silent forma.
- **Done/Checkpoint:** postojeći custom hooks očuvani; realna sesija ciklira crveno→narandžasto (permission prompt)→crveno→zeleno; uninstall vraća prethodno stanje. NAPOMENA: installer se NE pokreće bez najave korisniku — dira `~/.claude/settings.json` (backup obavezan pre svega).

### Phase 6 — Browser ekstenzija (MV3) — treba korisnik
- `extension/`: content script na `https://claude.ai/*` (MutationObserver, konfigurabilna selector lista u `chrome.storage.sync`, default `button[aria-label*="Stop"]`, 2 s debounce pre "done"), service worker agregacija više tabova (ANY busy → busy), options page (selektori + port), health-check badge sa backoff-om, host permission `http://127.0.0.1:4242/*`.
- **Done/Checkpoint:** korisnik učita unpacked u **Brave** (`brave://extensions`), realna sesija: W crveno tokom streaminga, zeleno ≤3 s, bez lažnog "done" kod multi-tool odgovora; two-tab test; gray badge kad app ne radi.

### Phase 7 — Distribucija
- `scripts/release.sh` (release build, zip, SHA-256, version stamp), `scripts/install.sh` (download latest release, `xattr -dr com.apple.quarantine`, → /Applications, launch).
- README polish (setup za sva tri izvora, Gatekeeper right-click→Open), `docs/TROUBLESHOOTING.md` (port konflikt, AX label override, selector override).
- GitHub repo/Release — pitati korisnika za repo ime/kreiranje kad se dođe dovde.
- **Done:** čist korisnik prati README → sva tri izvora rade za <10 min.

## Verifikacija (sumarno)

- Faze 0–3: autonomno — `swift build`, `build-app.sh`, curl testovi tranzicija/TTL/400/1000-loop, relaunch persistence.
- Faze 4–6: interaktivno sa korisnikom po checkpoint listama gore.

## Praćenje progresa

Kad se faza završi, štiklirati ovde:

- [ ] Phase 0 — Scaffold
- [ ] Phase 1 — StatusStore + HTTP server
- [ ] Phase 2 — Menu bar UI + meni
- [ ] Phase 3 — Notifikacije, zvuci, Settings, onboarding
- [ ] Phase 4 — Desktop watcher (AX)
- [ ] Phase 5 — Hooks installer
- [ ] Phase 6 — Browser ekstenzija
- [ ] Phase 7 — Distribucija
