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

**Status:** Prihvaćeno (2026-07-13) — implementacija u Phase 1

**Kontekst:** Treba lokalni HTTP endpoint za hooks (curl) i ekstenziju (fetch). Zero-deps princip.

**Odluka:** `NWListener` iz Network.framework, ručni minimalni HTTP parsing (samo
`POST /status` i `GET /health`). Bind **isključivo** `127.0.0.1`. Body cap 4 KB.

**Posledice:** Nema third-party HTTP paketa. Napadna površina svedena na lokalni host.

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
