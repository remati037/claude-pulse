// content.js — posmatra claude.ai DOM i javlja per-tab busy/done service worker-u (§2.5).
//
// NE priča direktno sa HTTP serverom app-a: fetch iz origin-a https://claude.ai ka 127.0.0.1
// pokreće CORS preflight (server nema CORS header-e) + Private Network Access blokadu → pada.
// Zato ovaj skript SAMO detektuje stanje i šalje chrome.runtime.sendMessage; SW vlasnik HTTP-a
// (host_permissions zaobilazi CORS/PNA). Detalji: ADR-012.

(() => {
    "use strict";

    // Default selektori za "stop generation" dugme. Konfigurabilni iz Options (storage.sync) da
    // prežive UI promene claude.ai bez republish-a — isto obrazloženje kao AX label override (ADR-010).
    const DEFAULT_SELECTORS = ['button[aria-label*="Stop"]'];

    // Debounce pre "done": dugme nestaje između tool-poziva / artifakata pa se vrati. Bez ovoga
    // bismo javili lažni "done" usred multi-tool odgovora (§2.5).
    const DONE_DEBOUNCE_MS = 2000;
    // Dok smo busy, periodično re-šaljemo busy da osvežimo TTL na serveru kod dugih sesija.
    const BUSY_HEARTBEAT_MS = 30000;

    let selectors = DEFAULT_SELECTORS;
    let currentBusy = false;       // poslednje javljeno stanje (busy=true / done=false)
    let doneTimer = null;          // tajmer za debounce done
    let heartbeatTimer = null;     // interval koji re-šalje busy

    // Učitaj selektore iz storage.sync; live update kad se promene u Options.
    chrome.storage.sync.get({ selectors: DEFAULT_SELECTORS }, (cfg) => {
        if (Array.isArray(cfg.selectors) && cfg.selectors.length) {
            selectors = cfg.selectors;
        }
        evaluate();
    });
    chrome.storage.onChanged.addListener((changes, area) => {
        if (area === "sync" && changes.selectors) {
            const next = changes.selectors.newValue;
            selectors = Array.isArray(next) && next.length ? next : DEFAULT_SELECTORS;
            evaluate();
        }
    });

    // Postoji li bilo koji element koji matchuje bilo koji selektor → Claude generiše.
    function detectBusy() {
        for (const sel of selectors) {
            try {
                if (document.querySelector(sel)) return true;
            } catch (_) {
                // Nevalidan selektor iz Options — preskoči, ne ruši observer.
            }
        }
        return false;
    }

    function send(state) {
        // Fail-silent: ako je SW uspavan/nedostupan, samo progutaj grešku.
        try {
            chrome.runtime.sendMessage({ type: "status", state }, () => void chrome.runtime.lastError);
        } catch (_) { /* extension context invalidated (reload) */ }
    }

    function startHeartbeat() {
        if (heartbeatTimer) return;
        heartbeatTimer = setInterval(() => { if (currentBusy) send("busy"); }, BUSY_HEARTBEAT_MS);
    }

    function stopHeartbeat() {
        if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
    }

    // Poredi trenutni DOM sa poslednjim javljenim stanjem i emituje tranzicije.
    function evaluate() {
        const busy = detectBusy();

        if (busy) {
            // Dugme se (ponovo) pojavilo → otkaži pending done, uđi/ostani u busy.
            if (doneTimer) { clearTimeout(doneTimer); doneTimer = null; }
            if (!currentBusy) {
                currentBusy = true;
                send("busy");
                startHeartbeat();
            }
            return;
        }

        // Dugme nestalo. Ako smo bili busy, sačekaj debounce pre nego javiš done.
        if (currentBusy && !doneTimer) {
            doneTimer = setTimeout(() => {
                doneTimer = null;
                if (!detectBusy()) {
                    currentBusy = false;
                    stopHeartbeat();
                    send("done");
                }
            }, DONE_DEBOUNCE_MS);
        }
    }

    // claude.ai je SPA — MutationObserver na body hvata i navigaciju i streaming izmene.
    const observer = new MutationObserver(() => evaluate());
    observer.observe(document.documentElement, { childList: true, subtree: true });

    evaluate();
})();
