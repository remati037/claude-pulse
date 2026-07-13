# ClaudePulse

Menu bar app za macOS koji na prvi pogled pokazuje da li Claude radi ili je gotov —
kroz **Claude Code** (terminal / VS Code), **claude.ai u browseru** i **Claude Desktop app**.

```
◉ C   ◉ W   ◉ D          C = Code   W = Web/browser   D = Desktop app
```

Po slotu: gray `✕` inactive · red `●` busy · orange `●` waiting · green `●` done.
Na `busy → done` stiže macOS notifikacija (+ opcioni zvuk).

> **Status:** u izradi. Phase 0 (scaffold) — minimalni menu bar app koji pokazuje
> statično `C✕ W✕ D✕`. Detaljna arhitektura: [CLAUDE-NOTIFIER-PLAN.md](CLAUDE-NOTIFIER-PLAN.md),
> fazni plan: [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md).

## Build (dev)

Zahteva macOS 13+ i Swift toolchain (Command Line Tools su dovoljni — Xcode nije potreban).

```bash
git clone <repo> && cd claude-pulse
bash scripts/dev-run.sh      # build-uje ClaudePulse.app i pokreće ga
```

Ikona se pojavi u menu baru gore desno. Za samo build bez pokretanja: `bash scripts/build-app.sh`.

## Struktura

```
app/         Swift menu bar app (SwiftUI + AppKit, SwiftPM executable)
extension/   Chrome/Chromium MV3 ekstenzija za claude.ai  (Phase 6)
hooks/       Claude Code hook installer (install-hooks.sh)  (Phase 5)
scripts/     build-app.sh, dev-run.sh (kasnije release.sh, install.sh)
docs/        TROUBLESHOOTING.md                             (Phase 7)
```

## Claude Code (hooks)

Da C slot reaguje na Claude Code sesije, instaliraj hookove (spajaju se u
`~/.claude/settings.json`, nikad ne pregaze — pravi se timestamped backup pre izmene):

```bash
bash hooks/install-hooks.sh              # default port 4242
bash hooks/install-hooks.sh --port 9999  # ako si promenio port u Settings-u
bash hooks/install-hooks.sh --uninstall  # ukloni samo ClaudePulse hookove
```

Dodaje 4 hooka: `UserPromptSubmit`/`PreToolUse` → busy, `Notification` → waiting,
`Stop` → done. Svaki je fail-silent (ne obori Claude Code ako app nije upaljen) i nosi
marker `# claudepulse` po kome ih uninstall/re-install prepoznaje. Tvoji custom hookovi
ostaju netaknuti. Re-run je idempotentan (bez duplikata). Zahteva `jq` (`brew install jq`).

Backup se pravi kao `~/.claude/settings.json.backup-<timestamp>`; ručno vraćanje:
`cp ~/.claude/settings.json.backup-<timestamp> ~/.claude/settings.json`.

## Browser ekstenzija (claude.ai)

Da `W` slot reaguje na claude.ai u browseru, učitaj MV3 ekstenziju iz `extension/`.
Radi u bilo kom Chromium browseru (**Brave**, Chrome, Edge…).

**Brave:** otvori `brave://extensions` → uključi **Developer mode** (gore desno) →
**Load unpacked** → izaberi folder `extension/`. (Chrome: isto na `chrome://extensions`.)

Kad je app upaljen i otvoriš claude.ai: `W` postaje crveno dok Claude generiše i zeleno
≤3 s po završetku. Više tabova se agregira — `W` je crveno dok bar jedan tab radi.

**Badge na ikoni:** siva tačka `•` znači da ekstenzija ne može da dođe do app-a
(ClaudePulse nije upaljen ili je port pogrešan). Bez badge-a = povezano.

**Podešavanja** (desni klik na ikonu → Options): promeni **port** (mora se poklapati sa
ClaudePulse → Settings) i **CSS selektore** za „stop generation" dugme — ako claude.ai
promeni UI pa detekcija stane, ispravi selektor ovde bez čekanja nove verzije ekstenzije.
Default selektor: `button[aria-label*="Stop"]`.

Ikone se generišu skriptom: `python3 scripts/gen-extension-icons.py`.

## Instalacija za korisnike

Dolazi u Phase 7 (GitHub Release + one-line installer). Zasad samo dev build gore.
