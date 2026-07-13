// options.js — čita/piše selektore i port u chrome.storage.sync i prikazuje da li je app dostupan.

"use strict";

const DEFAULT_PORT = 4242;
const DEFAULT_SELECTORS = ['button[aria-label*="Stop"]'];

const $selectors = document.getElementById("selectors");
const $port = document.getElementById("port");
const $status = document.getElementById("status");
const $health = document.getElementById("health");

function load() {
    chrome.storage.sync.get(
        { selectors: DEFAULT_SELECTORS, port: DEFAULT_PORT },
        (cfg) => {
            $selectors.value = (cfg.selectors || DEFAULT_SELECTORS).join("\n");
            $port.value = cfg.port || DEFAULT_PORT;
            checkHealth();
        }
    );
}

function save() {
    const selectors = $selectors.value
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
    let port = parseInt($port.value, 10);
    if (!Number.isInteger(port) || port < 1 || port > 65535) port = DEFAULT_PORT;

    chrome.storage.sync.set(
        { selectors: selectors.length ? selectors : DEFAULT_SELECTORS, port },
        () => {
            $status.textContent = "Sačuvano ✓";
            setTimeout(() => ($status.textContent = ""), 2000);
            checkHealth();
        }
    );
}

function reset() {
    $selectors.value = DEFAULT_SELECTORS.join("\n");
    $port.value = DEFAULT_PORT;
    save();
}

async function checkHealth() {
    let port = parseInt($port.value, 10);
    if (!Number.isInteger(port)) port = DEFAULT_PORT;
    $health.textContent = "Provera veze…";
    try {
        const res = await fetch(`http://127.0.0.1:${port}/health`);
        const data = await res.json();
        $health.textContent = data && data.ok
            ? `App radi ✓ (v${data.version || "?"}) na portu ${port}`
            : "App odgovara ali nevalidno.";
    } catch (_) {
        $health.textContent = `App nije dostupan na portu ${port}. Proveri da li je ClaudePulse upaljen.`;
    }
}

document.getElementById("save").addEventListener("click", save);
document.getElementById("reset").addEventListener("click", reset);
load();
