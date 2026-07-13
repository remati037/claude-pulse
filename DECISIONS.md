# DECISIONS.md — Architecture Decision Records

ADR log za ClaudePulse. Format: kontekst → odluka → posledice. Ne brisati stare ADR-ove;
ako se odluka menja, dodati novi ADR koji supersede-uje stari.

---

## ADR-001 — SwiftPM executable umesto Xcode projekta

**Status:** Prihvaćeno (2026-07-13)

**Kontekst:** Na mašini nema Xcode-a, samo Command Line Tools (`xcodebuild` ne radi).
Dostupan je Swift 6.1.2 preko `swift build`.

**Odluka:** App je SwiftPM `executableTarget` (`app/Package.swift`), min deployment macOS 13.
`scripts/build-app.sh` pakuje release binary u `ClaudePulse.app` sa ručno pisanim
`Info.plist`-om.

**Posledice:** Nema Xcode GUI-ja, storyboarda ni asset kataloga; sve programski (AppKit).
Bundle se sklapa skriptom. Prednost: radi bez Xcode-a, lako CI-jabilno.

---

## ADR-002 — Ručni AppKit lifecycle (bez SwiftUI `@main App`)

**Status:** Prihvaćeno (2026-07-13)

**Kontekst:** `NSStatusItem` i `UNUserNotificationCenter` traže pravi `.app` bundle.
SwiftUI `MenuBarExtra` ne podržava attributed-string rendering menu bar naslova iz §3.2
(obojene tačke `C● W● D✕`).

**Odluka:** `NSApplication.shared` + `AppDelegate` u `main.swift` (activation policy
`.accessory`). Menu bar preko `NSStatusItem`. Kasniji SwiftUI prozori (Settings, onboarding)
preko `NSWindow` + `NSHostingController`.

**Posledice:** Puna kontrola nad lifecycle-om i renderingom; nešto više boilerplate-a nego
SwiftUI `@main`.

---

## ADR-003 — HTTP server: Network.framework `NWListener`, samo `127.0.0.1`

**Status:** Prihvaćeno (2026-07-13), **implementirano u Phase 1** (2026-07-13)

**Kontekst:** Treba lokalni HTTP endpoint za hooks (curl) i ekstenziju (fetch). Zero-deps princip.

**Odluka:** `NWListener` iz Network.framework, ručni minimalni HTTP parsing (samo
`POST /status` i `GET /health`). Bind **isključivo** `127.0.0.1`. Body cap 4 KB.

**Posledice:** Nema third-party HTTP paketa. Napadna površina svedena na lokalni host.

**Implementacija (Phase 1):** loopback bind preko `NWParameters.requiredLocalEndpoint =
.hostPort(host: "127.0.0.1", port:)`. Svaka konekcija: čita do `\r\n\r\n`, telo po
`Content-Length`, `Connection: close` (bez keep-alive). Validacija: `source ∈ {code, web}`
(desktop je in-process, Phase 4), `state ∈ {busy, waiting, done}` (`inactive` je interno).
Body > 4 KB i ceo request > 16 KB → `400`. Verifikovano: 1000-request loop bez pada.

---

## ADR-004 — App nije sandboxovan

**Status:** Prihvaćeno (2026-07-13)

**Kontekst:** Treba mu Accessibility API (Phase 4, čitanje AX tree-ja Claude Desktop app-a)
i pokretanje installer skripte (Phase 3/5) — nespojivo sa App Sandbox-om.

**Odluka:** Bez App Sandbox entitlement-a. Distribucija van Mac App Store-a (GitHub Releases).

**Posledice:** Nema MAS distribucije u v1. Gatekeeper friction se rešava dokumentacijom
(right-click → Open) i `xattr` unquarantine u install skripti (Phase 7).

---

## ADR-005 — Bez autentikacije na localhost serveru

**Status:** Prihvaćeno (2026-07-13)

**Kontekst:** Server sluša samo na `127.0.0.1`. Bilo koji lokalni proces može poslati status.

**Odluka:** Bez auth-a u v1. Uticaj eventualnog spoofinga je čisto kozmetički (pogrešna
tačka u menu baru), nema pristupa podacima ni izvršavanja koda.

**Posledice:** Jednostavniji hooks/ekstenzija (nema tokena). Revidirati ako se doda osetljiviji
payload u budućnosti.

---

## ADR-006 — Concurrency model jezgra + test-override preko env varijabli

**Status:** Prihvaćeno (2026-07-13, Phase 1)

**Kontekst:** `StatusStore` je jedini izvor istine i mora biti thread-safe: dira ga HTTP
handler (pozadinski `NWListener` queue) i sweep timer, a menu bar re-render mora na main
thread. Takođe, TTL/stuck/auto-reset se u §2.3 mere minutima (30/45/10) — nepraktično za
autonomnu verifikaciju.

**Odluka:**
1. `StatusStore` je `@MainActor`; sav pristup ide preko main actora → thread-safe bez
   ručnog zaključavanja. HTTP handler hop-uje na main preko `Task { @MainActor in … }` pre
   `apply(...)`. `AppDelegate` je takođe `@MainActor`; `main.swift` ulazi u izolaciju preko
   `MainActor.assumeIsolated { … app.run() }` (top-level kod nije main-actor izolovan).
   Bez Combine — `onChange` closure za re-render (zero-dep duh ADR-003).
2. Test-override: env varijable `CLAUDEPULSE_TTL_SECONDS` / `CLAUDEPULSE_DONE_RESET_SECONDS`
   / `CLAUDEPULSE_STUCK_SECONDS` gaze minute iz Settings-a (u sekundama); kad je ijedan set,
   sweep interval pada sa 30 s na 1 s. Debug-only, ne persistira se.

**Posledice:** Nema data race-a (Swift 6 strict concurrency prolazi čisto). Env override
ostaje trajni dev/QA mehanizam za verifikaciju state machine-a bez čekanja minutima.
Napomena: za env override app se pokreće direktno preko `ClaudePulse.app/Contents/MacOS/…`
(a ne `open`, koji ne prosleđuje env) — `Bundle.main` i dalje pokazuje na `.app` bundle.

---

## ADR-007 — Menu bar rendering i meni (Phase 2)

**Status:** Prihvaćeno (2026-07-13, Phase 2)

**Kontekst:** §3.1 nalaže da se u Phase 2 potvrdi da li `MenuBarExtra` može da renderuje
attributed-string naslov iz §3.2 (obojene tačke `C● W● D✕`), inače ostaje `NSStatusItem`
(ADR-002). Takođe treba pun meni iz §3.3 sa live osvežavanjem stanja i relativnog vremena.

**Odluka:**
1. **`NSStatusItem` + `button.attributedTitle`** — potvrđeno da renderuje obojene tačke
   (system boje `.systemRed/.systemOrange/.systemGreen`, slova u `.labelColor`) i da
   auto-adaptira na light/dark menu bar. Ostajemo pri `NSStatusItem` (ADR-002 potvrđen);
   `MenuBarExtra` se ne uvodi.
2. **Meni se puni lenjo u `NSMenuDelegate.menuNeedsUpdate`** umesto jednom pri startu →
   stanja, relativno vreme i checkmark-ovi su sveži pri svakom otvaranju bez ručne
   invalidacije. Ikona se odvojeno re-renderuje live preko `statusStore.onChange`.
   Source se prenosi do handlera preko `NSMenuItem.representedObject` (`source.rawValue`).
3. **"Display Mode" submeni u meniju** (Compact / Icon-only) kao odstupanje od §3.3 —
   dogovoreno sa korisnikom (2026-07-13) jer Settings prozor (§3.4) stiže tek u Phase 3.
   Deli isti `settings.displayMode`, pa Settings prozor kasnije samo dodaje drugi ulaz.
4. **Stavke zavisne od Phase 3** (Settings…, Setup Guide…, Launch at Login, Test
   notification) prikazane **disabled** → finalni §3.3 layout odmah, žice po fazama.

**Posledice:** Prezentacioni sloj bez novih zavisnosti. Disabled izvor se renderuje kao
`inactive` (§1.2) preko `StatusRendering.effectiveState`. Čist mapping stanje→boja/glyph/tekst
je centralizovan u `StatusRendering` i dele ga ikona i redovi menija.

---

## ADR-008 — SettingsStore reaktivnost: `ObservableObject`, ne `@Observable` (Phase 3)

**Status:** Prihvaćeno (2026-07-13, Phase 3)

**Kontekst:** SwiftUI Settings prozor (§3.4) mora da menja `Settings` uživo i da UI prati te
promene. Moderni `@Observable` macro (Observation framework) traži macOS 14, a deployment
target je macOS 13 (ADR-001).

**Odluka:** `SettingsStore` je `@MainActor final class ... ObservableObject` sa
`@Published private(set) var settings`. Postojeći `update { }` API ostaje (menu i StatusStore
ga i dalje koriste), plus `replace(with:)` za import. `onSettingsChanged` callback javlja
`AppDelegate`-u da re-renderuje menu bar i, na promeni porta, `httpServer.restart(port:)`.
SwiftUI kontrole vežu preko jednog `binding(_:)` helpera koji zove `update { }` → auto-persist.

**Posledice:** Radi na macOS 13. `@Published` dolazi iz Combine/Foundation bez third-party
zavisnosti (zero-dep, ADR-003 duh). Migracija na `@Observable` je trivijalna kad target
poraste na macOS 14 (v2).

---

## ADR-009 — Login item: `SMAppService.mainApp` (Phase 3)

**Status:** Prihvaćeno (2026-07-13, Phase 3)

**Kontekst:** „Launch at Login" (§3.4 General). Legacy `SMLoginItemSetEnabled` je deprecated i
traži poseban helper bundle; app je min macOS 13.

**Odluka:** `ServiceManagement.SMAppService.mainApp` — `register()` / `unregister()` / `status`
registruju sam `.app` kao login item, bez helper bundle-a (macOS 13+ API).

**Posledice:** Bez dodatnog helper target-a. Napomena: `register()` radi pouzdano tek kad je
`.app` na stabilnoj lokaciji (npr. `/Applications`); iz repo foldera status može ostati
`.requiresApproval` — ishod se loguje, korisnik odobrava u System Settings ▸ General ▸ Login Items.
