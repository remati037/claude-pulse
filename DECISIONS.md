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
