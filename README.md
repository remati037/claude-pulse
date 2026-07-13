# ClaudePulse

**Menu bar app za macOS koji ti na prvi pogled kaže da li Claude još radi ili je gotov** —
kroz **Claude Code** (terminal / VS Code), **claude.ai** (browser) i **Claude Desktop** app.

```
◉ C   ◉ W   ◉ D          C = Code   W = Web/browser   D = Desktop app
```

Boje po slotu: sivo `✕` neaktivno · crveno `●` radi · narandžasto `●` čeka tebe · zeleno `●` gotovo.
Kad Claude završi (`radi → gotovo`) dobiješ macOS notifikaciju (+ opcioni zvuk).

---

## Instalacija — korak po korak

> Potrebno: macOS 13 (Ventura) ili noviji. Ne treba ti Xcode ni bilo šta developersko.

### Korak 1 — Instaliraj app (30 sekundi)

Otvori **Terminal** (Cmd+Space → ukucaj „Terminal" → Enter) i nalepi ovu jednu liniju:

```bash
curl -fsSL https://raw.githubusercontent.com/remati037/claude-pulse/master/scripts/install.sh | bash
```

To skine app, ubaci ga u **Applications** i pokrene. **Ikona `C✕ W✕ D✕` se pojavi gore desno
u menu baru.** Gotovo — app radi. Sad ga samo poveži sa izvorima koje koristiš (koraci ispod;
uzmi samo one koje ti trebaju).

> **Ne ide kroz Terminal?** Vidi [„Instalacija bez Terminala"](#instalacija-bez-terminala) dole.

### Korak 2 — Poveži Claude Code (slot **C**)

Da `C` reaguje na Claude Code sesije u terminalu / VS Code-u, nalepi u Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/remati037/claude-pulse/master/hooks/install-hooks.sh | bash
```

Ovo dodaje 4 „hooka" u tvoj Claude Code config (`~/.claude/settings.json`) — **bezbedno se
spaja, ne briše tvoja postojeća podešavanja, i pravi backup pre izmene.** Zahteva `jq`
(ako ga nemaš: `brew install jq`, pa ponovo pokreni komandu).

Otvori Claude Code i pošalji poruku → **`C` postane crveno dok Claude radi, zeleno kad završi.**

_Da ukloniš hookove kasnije:_ `curl -fsSL …/hooks/install-hooks.sh | bash -s -- --uninstall`

### Korak 3 — Poveži claude.ai u browseru (slot **W**)

Ovo je jedina stvar koja traži par klikova (browser ekstenzija se učitava ručno):

1. Otvori **https://github.com/remati037/claude-pulse** → zeleno dugme **`Code`** → **Download ZIP**.
2. Raspakuj skinuti `.zip` (dupli klik). Dobiješ folder `claude-pulse-master`.
3. U browseru (Brave / Chrome / Edge) otvori stranicu sa ekstenzijama:
   - Brave: `brave://extensions`  ·  Chrome: `chrome://extensions`  ·  Edge: `edge://extensions`
4. Uključi **Developer mode** (prekidač gore desno).
5. Klikni **Load unpacked** → izaberi folder **`extension`** unutar `claude-pulse-master`.

Otvori **claude.ai** → **`W` postane crveno dok Claude generiše, zeleno kad završi.** Više
otvorenih tabova se sabira (crveno dok bar jedan radi).

> Siva tačka na ikoni ekstenzije = ne može da nađe app (ClaudePulse ugašen ili drugi port).

### Korak 4 — Poveži Claude Desktop app (slot **D**)

1. U menu baru klikni na ClaudePulse → red **Desktop** → **Grant Accessibility permission…**
2. Otvoriće se **System Settings ▸ Privacy & Security ▸ Accessibility** — **uključi ClaudePulse**.

Otvori Claude Desktop i pošalji poruku → **`D` postane crveno dok Claude radi, zeleno kad završi.**
(Accessibility dozvola je neophodna jer Desktop app nema drugi način da javi status.)

---

## To je to 🎉

Sve što ti treba sada radi. Ikona u menu baru pokazuje stanje svih izvora, a kad Claude završi
dobiješ notifikaciju. Klik na ikonu → meni sa podešavanjima (zvuci, „ne uznemiravaj" period,
custom port, reset, Launch at Login…).

**App se ne pokrene sam kad upališ Mac?** Meni → **Launch at Login**.

---

## Instalacija bez Terminala

Ako ne želiš da koristiš Terminal za app:

1. Otvori **https://github.com/remati037/claude-pulse/releases/latest**.
2. Skini **`ClaudePulse-v1.0.0.dmg`** i dupli klik.
3. U prozoru koji se otvori **prevuci ClaudePulse u Applications**.
4. Otvori app iz Applications. Prvi put macOS pokaže upozorenje jer app nije „notarizovan"
   kod Apple-a (besplatan/open-source, potpuno bezbedan) — to se preskače jednom:
   - **macOS 15 Sequoia / 26 Tahoe:** klikni **Done** → **System Settings → Privacy &
     Security** → dole kod „ClaudePulse was blocked" klikni **Open Anyway**.
   - **macOS 13–14:** desni klik na app → **Open** → **Open**.
   - _Ili preko Terminala (radi svuda):_ `xattr -dr com.apple.quarantine /Applications/ClaudePulse.app`

> 💡 **Ako izbegavaš ove korake:** instaliraj preko **Koraka 1** (`curl … | bash`) — taj
> installer skida karantin automatski, pa nema nikakvog upozorenja.

Zatim uradi korake 2–4 gore za izvore koje koristiš.

---

## Problemi?

Vidi **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — Gatekeeper upozorenja, promena
porta, „C/W/D ne reaguje", i ostalo.

---

## Za developere / održavaoce

<details>
<summary>Build iz izvora, release, struktura repoa</summary>

### Build (dev)
Command Line Tools su dovoljni (Xcode nije potreban):
```bash
git clone https://github.com/remati037/claude-pulse && cd claude-pulse
bash scripts/dev-run.sh      # build-uje ClaudePulse.app i pokreće ga
```

### Napravi release
```bash
bash scripts/release.sh 1.0.0                 # → dist/ClaudePulse-v1.0.0.zip + .sha256
gh release create v1.0.0 dist/ClaudePulse-v1.0.0.zip dist/ClaudePulse-v1.0.0.zip.sha256 \
  --repo remati037/claude-pulse --title "ClaudePulse v1.0.0"
```
Distribucija je ad-hoc potpisana, van Mac App Store-a (vidi [ADR-013](DECISIONS.md)).

### Struktura
```
app/         Swift menu bar app (AppKit + SwiftUI, SwiftPM executable)
extension/   Chrome/Chromium MV3 ekstenzija za claude.ai
hooks/       Claude Code hook installer (install-hooks.sh)
scripts/     build-app.sh, dev-run.sh, release.sh, install.sh
docs/        TROUBLESHOOTING.md
```

Arhitektura: [CLAUDE-NOTIFIER-PLAN.md](CLAUDE-NOTIFIER-PLAN.md) · odluke: [DECISIONS.md](DECISIONS.md).

</details>
