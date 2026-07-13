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

## ADR-010 — Desktop watcher preko Accessibility API-ja (Phase 4)

**Status:** Prihvaćeno (2026-07-13, Phase 4)

**Kontekst:** Claude Desktop je Electron app — nema hooks ni DOM pristup kao code/web izvori.
Jedini in-process način da se detektuje „generiše / gotovo" je Accessibility (AX) API (§2.4).
Bundle id potvrđen iz `/Applications/Claude.app/Contents/Info.plist`: `com.anthropic.claudefordesktop`.

**Odluka:**
- `DesktopWatcher` (@MainActor) poll-uje AX tree **samo dok Claude app radi** (prati
  `NSWorkspace` launch/terminate notifikacije) → zero idle cost; feed ide kroz
  `StatusStore.apply(source: .desktop, ...)`, sva state-machine logika ostaje u StatusStore-u.
- **AXManualAccessibility=true** na app elementu (`AXUIElementCreateApplication(pid)`) — budi
  Chromium da izgradi a11y tree; bez toga web sadržaj (uklj. stop dugme) često nije u AX-u.
- Detekcija = bounded DFS kroz sve prozore app-a tražeći `AXButton` čiji spojeni tekst
  (title/description/help/value) case-insensitive sadrži **label pattern iz Settings-a**
  (`desktopStopLabelPattern`, default `"stop"`) — NIJE hardkodiran, da preživi promenu Anthropic
  UI-ja bez update-a app-a. Node-budget cap (4000) protiv runaway obilaska ogromnog Electron tree-a.
- Debounce: dugme odsutno **2 uzastopna poll-a** dok je bilo `busy` → `done`. Quit app-a → reset
  na `inactive` (D ✕).
- Bez AX dozvole (`AXIsProcessTrusted() == false`) → graceful degrade (D ostaje inactive) + menu
  hint „Grant Accessibility permission…" (deep-link u System Settings) i grant dugme u Settings ▸ Sources.
- **Diagnostic „Dump AX tree to log"** (desktop submeni) ispisuje sve `AXButton`-e u log — za
  empirijsko otkrivanje pravog labela na živoj app.

**Empirijski nalaz labela (live test 2026-07-13):** Detekcija **potvrđena** default pattern-om
`"stop"` — dug prompt: `desktop: inactive → busy` u ~2 s, održavano svakih poll-a, pa `busy → done`
kad dugme nestane (debounce 2 poll-a), + notifikacija; quit → `inactive`. AXManualAccessibility je
neophodan (bez njega prozor nema web dugmad). Napomena: „Dump AX tree to log" hvata samo trenutno
stanje — da bi se video tačan tekst stop dugmeta, dump mora da se pokrene **dok Claude generiše**
(idle dump ga ne sadrži). Default `"stop"` je dovoljan; tačan string dokumentovati oportunistički
ako zatreba fino podešavanje.

**Posledice:** Radi i kad Claude nije frontmost (prozori dostupni preko pid-a) — pokriva glavni
use-case (korisnik odlutao u drugu app). Poznato ograničenje (§2.4): minimizovan prozor —
ponašanje dokumentovati posle live testa. Zavisi od AX dozvole (ADR-004: app nije sandboxovan).

---

## ADR-011 — Claude Code hooks installer: marker-based idempotentan merge (Phase 5)

**Status:** Prihvaćeno (2026-07-13, Phase 5)

**Kontekst:** Claude Code (§2.6) javlja status preko hookova u `~/.claude/settings.json`. Taj
fajl je korisnikov lični config (model, theme, eventualni custom hookovi) — CLAUDE.md zabranjuje
overwrite i traži backup. Treba installer koji **spaja** 4 hooka (UserPromptSubmit/PreToolUse→busy,
Notification→waiting, Stop→done), podržava `--uninstall` i `--port`, i preživljava ponovno
pokretanje bez duplikata.

**Odluka:**
- **Marker `# claudepulse`** na kraju svake naše curl komande. Uninstall i re-install prepoznaju
  naše hookove isključivo po markeru → custom hookovi korisnika ostaju netaknuti čak i kad promeni
  port ili UI. Install = „ukloni sve `claudepulse` grupe (deljen REMOVE jq filter) → dodaj sveže"
  (ADD jq filter) → **idempotentno** (verifikovano: 2× install = po jedna naša grupa po eventu).
- **jq merge, nikad overwrite.** Zero-dep na Apple strani, ali installer je shell i `jq` je već
  preduslov (§2.6, provera + `brew install jq` hint). REMOVE filter uklanja i prazne event nizove
  i prazan `.hooks` objekat da ne ostavi smeće.
- **Backup + atomičan upis:** `settings.json.backup-YYYYMMDD-HHMMSS` pre ijedne izmene; rezultat
  se piše u `mktemp`, `jq empty` validira, pa tek `mv` preko originala. Nevalidan postojeći JSON →
  odbij (exit 1) bez diranja fajla. Original se nikad ne vidi polupisan.
- **`PreToolUse` sa `matcher: ""`** (svi tools); ostala tri eventa nemaju matcher (nisu tool-scoped).
- **`source:"code"` + `busy/waiting/done`** — tačno ono što `HTTPServer.handleStatus` prihvata
  (400 inače). Komanda je fail-silent (`>/dev/null 2>&1 || true`, `-m 2`) da hook nikad ne obori
  Claude Code ako app nije upaljen. Port se ubrizgava u jq kroz `--arg` (bez string-lepljenja).
- App **ne** pokreće installer sam (CLAUDE.md); onboarding korak 2 nudi kopiraj-nalepi komandu.

**Posledice:** Bezbedan re-run i port-migracija; custom hookovi zagarantovano preživljavaju.
Cena: marker mora ostati stabilan string (menjanje bi „osirotelo" stare hookove — tada ih uklanja
ručni uninstall stare verzije). Verifikacija busy→waiting→done ciklusa je interaktivna (realna
Claude Code sesija), ostalo (merge/idempotencija/uninstall/port) autonomno na izolovanoj kopiji.

## ADR-012 — Browser ekstenzija: service worker vlasnik HTTP-a, efemeran MV3 SW (Phase 6)

**Status:** Prihvaćeno (2026-07-13, Phase 6)

**Kontekst:** `W` slot treba da reaguje na claude.ai u browseru (§2.5). MV3 ekstenzija detektuje
prisustvo „stop generation" dugmeta u DOM-u i javlja app-u preko `POST /status` (`source:"web"`).
Problem: `HTTPServer` (ADR-003) **ne šalje CORS header-e niti odgovara na OPTIONS**. Fetch iz
content script-a (origin `https://claude.ai`) ka `127.0.0.1` bi pokrenuo CORS preflight (server
vrati 404) + Private Network Access blokadu → pada. Uz to, port je konfigurabilan (Settings), a
`host_permissions` u manifestu su statični.

**Odluka:**
- **Content script SAMO posmatra DOM; sav HTTP ide iz service worker-a.** Content script šalje
  `chrome.runtime.sendMessage({type:"status", state})`, SW radi `fetch`. Extension-inicirani
  zahtev sa `host_permissions` **nije podložan CORS-u** ni PNA — nula izmena na Swift strani.
  Bonus: SW je prirodno mesto za agregaciju više tabova (§2.5).
- **Efemeran MV3 SW** (gasi se ~30 s neaktivnosti) → mapa `tabId→busy` živi u
  `chrome.storage.session` (preživi gašenje), a health polling ide preko `chrome.alarms`
  (setInterval ne preživi spavanje). Health backoff: 0.5→1→2→4→5 (cap) min kad app ne radi.
- **`host_permissions: ["http://127.0.0.1/*"]`** — wildcard **bez porta** (match pattern ignoriše
  port) pokriva bilo koji konfigurisan port bez republish-a. Rešava §3.4 „custom port".
- **Konfigurabilni selektori + port u `chrome.storage.sync`** (Options stranica), default
  `button[aria-label*="Stop"]`. Isto obrazloženje kao AX label override (ADR-010): preživeti UI
  promene claude.ai bez nove verzije ekstenzije. Live update preko `storage.onChanged`.
- **Samo `busy`/`done` iz browsera u v1** — nema pouzdanog DOM signala za `waiting`
  (permission-prompt je Claude Code specifičan). Debounce 2 s pre `done` (dugme nestane između
  tool-poziva/artifakata → lažni done bez debounce-a). Busy heartbeat ~30 s osvežava TTL.

**Posledice:** Zero-touch na serveru; ekstenzija je browser-agnostična (plain `fetch`, testira se
kao unpacked u Brave-u — nema Chrome-a na mašini). Cena: SW state je async (storage.session)
umesto in-memory, pa svaki handler čita/piše storage. Detekcija app-down ima do ~30 s latencije
(health interval), ali `post()` na grešci odmah sivi badge. Verifikacija busy/done ciklusa,
multi-tab i lažni-done su interaktivni (realna claude.ai sesija); kontrakt (`web/busy`, `web/done`)
i manifest lint autonomni curl-om.
