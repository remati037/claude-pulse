# CLAUDE.md — ClaudePulse

Pravila za Claude Code koji radi u ovom repou. Čitaj pre svake izmene.

## Šta je ovo

macOS menu bar app koji pokazuje da li je Claude zauzet/gotov kroz tri izvora:
Claude Code (hooks), claude.ai u browseru (MV3 ekstenzija), Claude Desktop app (AX API).

**Izvor istine za detalje:** [CLAUDE-NOTIFIER-PLAN.md](CLAUDE-NOTIFIER-PLAN.md) (referencira se
kao §2.3 itd.). Fazni izvršni plan: [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md).

## Build & run

Nema Xcode-a na mašini (samo Command Line Tools) — **sve preko `swift build`**, nikad `xcodebuild`.

```bash
cd app && swift build -c release      # kompajlira executable
bash scripts/build-app.sh             # build + sklopi ClaudePulse.app + ad-hoc codesign
bash scripts/dev-run.sh               # build-app.sh + (re)pokreni .app
```

**App se UVEK pokreće kao `.app` bundle**, nikad goli binary iz `.build/` —
`NSStatusItem` i `UNUserNotificationCenter` traže pravi bundle (+ ad-hoc potpis).

## Nepregovarljiva pravila

- **HTTP server se binduje ISKLJUČIVO na `127.0.0.1`, nikad `0.0.0.0`.** Nema izuzetaka.
- **Svaka netrivijalna odluka ide u [DECISIONS.md](DECISIONS.md) kao ADR** (ADR-NNN format).
- **Zero third-party zavisnosti u v1** — samo Apple frameworks (AppKit, SwiftUI, Network,
  UserNotifications). Uvođenje paketa zahteva ADR.
- Ne diraj `~/.claude/settings.json` bez najave korisniku (Phase 5, uz obavezan backup).

## Swift stil

- 4-space indent, bez tabova.
- Bundle display name u jednoj konstanti (lako preimenovanje).
- Ručni AppKit lifecycle (`NSApplication` + `AppDelegate`), bez SwiftUI `@main App` (ADR-002).

## Rad po fazama

Faza po faza (§4 u glavnom planu). Redosled: implementiraj → verifikuj autonomno →
checkpoint poruka korisniku → git commit → sledeća faza. Progres se štiklira u
[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) („Praćenje progresa").
