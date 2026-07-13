// sw.js — service worker: agregira busy/done iz svih claude.ai tabova i javlja HTTP serveru app-a.
//
// Vlasnik SVEG mrežnog saobraćaja (content script ne sme — CORS/PNA, ADR-012). Sa host_permissions
// za http://127.0.0.1/* fetch iz SW-a nije podložan CORS-u.
//
// MV3 SW je efemeran (gasi se posle ~30 s neaktivnosti), pa:
//   - mapa tabId→busy živi u chrome.storage.session (preživi gašenje),
//   - health polling ide preko chrome.alarms (setInterval ne preživi spavanje).

"use strict";

const DEFAULT_PORT = 4242;
const HEALTH_ALARM = "health";
const HEALTH_OK_MIN = 0.5;   // interval kad je app dostupan (30 s)
const HEALTH_MAX_MIN = 5;    // gornja granica backoff-a kad app ne radi
const BADGE_DOWN_COLOR = "#8E8E93";
const FETCH_TIMEOUT_MS = 2000;

// MARK: - Konfiguracija (port) i session state (tab mapa, agregat, health fail count)

async function getPort() {
    const { port } = await chrome.storage.sync.get({ port: DEFAULT_PORT });
    const n = parseInt(port, 10);
    return Number.isInteger(n) && n > 0 && n < 65536 ? n : DEFAULT_PORT;
}

async function getSession() {
    const s = await chrome.storage.session.get({ tabBusy: {}, aggBusy: false, healthFails: 0 });
    return s;
}

// MARK: - HTTP ka app-u

async function post(state) {
    const port = await getPort();
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    try {
        await fetch(`http://127.0.0.1:${port}/status`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ source: "web", state }),
            signal: ctrl.signal,
        });
        return true;
    } catch (_) {
        // App verovatno nije upaljen — tiho (bez console spama), i osveži badge.
        markDown();
        return false;
    } finally {
        clearTimeout(t);
    }
}

// MARK: - Agregacija tabova

async function reconcile(tabBusy) {
    const anyBusy = Object.keys(tabBusy).length > 0;
    const { aggBusy } = await getSession();

    if (anyBusy) {
        // Uvek re-šalji busy (idempotentno na serveru; osvežava TTL preko heartbeat-a).
        await chrome.storage.session.set({ tabBusy, aggBusy: true });
        await post("busy");
    } else {
        await chrome.storage.session.set({ tabBusy, aggBusy: false });
        if (aggBusy) await post("done");   // poslednji busy tab završio → done
    }
}

chrome.runtime.onMessage.addListener((msg, sender) => {
    if (!msg || msg.type !== "status" || !sender.tab) return;
    const tabId = String(sender.tab.id);

    (async () => {
        const { tabBusy } = await getSession();
        if (msg.state === "busy") {
            tabBusy[tabId] = true;
        } else {
            delete tabBusy[tabId];   // "done" iz taba → skloni ga iz busy skupa
        }
        await reconcile(tabBusy);
    })();
    // Ne držimo kanal otvoren (nema sendResponse) → vrati undefined.
});

// Tab zatvoren usred generisanja → skloni ga da ne zaglavi agregat u busy.
chrome.tabs.onRemoved.addListener((tabId) => {
    (async () => {
        const { tabBusy } = await getSession();
        if (tabBusy[String(tabId)]) {
            delete tabBusy[String(tabId)];
            await reconcile(tabBusy);
        }
    })();
});

// MARK: - Health badge (app upaljen?) + backoff

function markUp() {
    chrome.action.setBadgeText({ text: "" });
    chrome.action.setTitle({ title: "ClaudePulse — povezan" });
}

function markDown() {
    chrome.action.setBadgeText({ text: "•" });
    chrome.action.setBadgeBackgroundColor({ color: BADGE_DOWN_COLOR });
    chrome.action.setTitle({ title: "ClaudePulse — app ne radi" });
}

async function checkHealth() {
    const port = await getPort();
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    let ok = false;
    try {
        const res = await fetch(`http://127.0.0.1:${port}/health`, { signal: ctrl.signal });
        ok = res.ok;
    } catch (_) {
        ok = false;
    } finally {
        clearTimeout(t);
    }

    if (ok) {
        markUp();
        await chrome.storage.session.set({ healthFails: 0 });
        scheduleHealth(HEALTH_OK_MIN);
    } else {
        markDown();
        const { healthFails } = await getSession();
        const fails = healthFails + 1;
        await chrome.storage.session.set({ healthFails: fails });
        // Eksponencijalni backoff: 0.5 → 1 → 2 → 4 → 5 (cap) min.
        const delay = Math.min(HEALTH_OK_MIN * Math.pow(2, fails), HEALTH_MAX_MIN);
        scheduleHealth(delay);
    }
    return ok;
}

function scheduleHealth(delayInMinutes) {
    chrome.alarms.create(HEALTH_ALARM, { delayInMinutes });
}

chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === HEALTH_ALARM) checkHealth();
});

// Pokreni odmah na (re)startu SW-a i pri instalaciji.
chrome.runtime.onInstalled.addListener(() => checkHealth());
chrome.runtime.onStartup.addListener(() => checkHealth());
checkHealth();
