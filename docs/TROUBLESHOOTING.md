# TROUBLESHOOTING — ClaudePulse

Najčešći problemi po izvoru. Log je uvek dobra prva stanica:
`~/Library/Logs/ClaudePulse/claudepulse.log` (i „Open log file" u Settings ▸ Advanced).

## Gatekeeper: „Apple could not verify…" / „unidentified developer"

App nije notarizovan kod Apple-a (nema Apple Developer nalog), pa ga Gatekeeper karantinira
posle download-a. **One-line `curl … | bash` installer to rešava sam** (skida `xattr` karantin →
nema nijednog upozorenja) — to je najlakši put. Ako ipak koristiš `.dmg` ili ručni download:

**Najbrže (Terminal, radi na svakoj verziji macOS-a):** skini karantin sa preuzetog fajla,
pa ga otvori. Za DMG:
```bash
xattr -dr com.apple.quarantine ~/Downloads/ClaudePulse-v1.0.0.dmg
```
ili za već instaliran app: `xattr -dr com.apple.quarantine /Applications/ClaudePulse.app`

**Bez Terminala (macOS 13–14):** desni klik na app → **Open** → **Open** u dijalogu (jednom).

**Bez Terminala (macOS 15 Sequoia / 26 Tahoe):** stari „right-click → Open" više ne radi.
Umesto toga:
1. Kad iskoči „Apple could not verify…", klikni **Done**.
2. **System Settings → Privacy & Security** → skroluj do **Security**.
3. Kod „ClaudePulse… was blocked" klikni **Open Anyway** → potvrdi Touch ID/lozinkom.

## Ikona se ne vidi u menu baru / notifikacije ne rade

ClaudePulse **mora** da se pokreće kao `.app` bundle (ne goli binary iz `.build/`) —
`NSStatusItem` i `UNUserNotificationCenter` traže pravi, potpisan bundle (ADR-002). Ako si
build-ovao iz izvora, koristi `bash scripts/dev-run.sh`, ne pokreći executable direktno.

Notifikacije se prvo moraju odobriti (onboarding korak, ili System Settings ▸ Notifications ▸
ClaudePulse). DND prozor (Settings ▸ Notifications) suprimira notifikacije u zadatom intervalu.

## Port konflikt (server se ne diže)

Default port je `4242`. Ako je zauzet, promeni ga u **Settings ▸ Advanced** — server se
restartuje na novom portu. Onda uskladi ostale izvore na isti port:

- Claude Code: `bash hooks/install-hooks.sh --port <novi_port>`
- Ekstenzija: desni klik na ikonu → Options → polje **port**

Provera da server radi: `curl -s 127.0.0.1:<port>/health` → `{"ok":true,"version":"…"}`.

## „C" (Claude Code) ne reaguje

- Hookovi instalirani? `bash hooks/install-hooks.sh` (spaja u `~/.claude/settings.json` uz
  backup; **zahteva `jq`** — `brew install jq`).
- Port hookova mora da se poklapa sa Settings portom (vidi gore).
- Hookovi su fail-silent (ne obaraju Claude Code ako app ne radi) — pa proveri da je app upaljen.
- Uninstall (samo naši hookovi, custom ostaju): `bash hooks/install-hooks.sh --uninstall`.

## „W" (claude.ai u browseru) ne reaguje

- Ekstenzija učitana kao unpacked (Brave: `brave://extensions` → Developer mode → Load unpacked
  → folder `extension/`).
- **Siva tačka `•` na ikoni ekstenzije** = ne može do app-a (app ugašen ili pogrešan port).
- Ako claude.ai promeni UI pa detekcija stane: Options → **CSS selektori** za stop-dugme
  (default `button[aria-label*="Stop"]`). Ispravi selektor bez čekanja nove verzije.

## „D" (Claude Desktop) ne reaguje

- Treba **Accessibility permission**: menu hint „Grant Accessibility permission…" ili
  Settings ▸ Sources → Grant → System Settings ▸ Privacy & Security ▸ Accessibility (uključi
  ClaudePulse). Bez toga D ostaje sivo (graceful degrade).
- Detekcija traži dugme čiji tekst sadrži `desktopStopLabelPattern` (default `"stop"`,
  case-insensitive). Ako Anthropic promeni label, promeni pattern u Settings ▸ Sources.
- Dijagnostika: desktop submeni → **„Dump AX tree to log"** dok Claude **generiše** (idle dump
  ne sadrži stop-dugme) → pogledaj tačan tekst dugmeta u logu i uskladi pattern.

## Reset stanja

Meni → **Reset all** vraća sve slotove na inactive. Pojedinačno: submeni izvora → Reset.
Stanja se i sama gase po TTL-u / auto-reset-u (Settings ▸ Sources).
