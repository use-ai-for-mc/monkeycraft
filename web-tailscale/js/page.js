import { RpcClient, ERROR_CODES } from "./rpc.js";

const logEl = document.getElementById("log");
const stateEl = document.getElementById("state");
const peersEl = document.getElementById("peers");
const authEl = document.getElementById("auth");
const authOpen = document.getElementById("auth-open");
const authCopy = document.getElementById("auth-copy");
const hostInput = document.getElementById("echo-host");
const portInput = document.getElementById("echo-port");
const backendEl = document.getElementById("backend");

let pendingPopup = null;
let authUrl = null;
let lastPeers = [];

function log(line) {
  const t = new Date().toISOString().slice(11, 19);
  logEl.textContent += `[${t}] ${line}\n`;
  logEl.scrollTop = logEl.scrollHeight;
}

function openAuthWindowSync() {
  const w = window.open("about:blank", "ts-auth", "width=480,height=720");
  if (!w) {
    log("popup blocked; waiting for login URL to show fallback (URL not logged)");
    return { blocked: true, win: null };
  }
  try {
    w.document.title = "Tailscale login";
    w.document.body.textContent = "Waiting for Tailscale login URL…";
  } catch {
    /* ignore */
  }
  return { blocked: false, win: w };
}

function applyAuthUrl(url) {
  if (typeof url !== "string" || url.length < 8) return;
  authUrl = url;
  if (pendingPopup && !pendingPopup.closed) {
    try {
      pendingPopup.location.href = url;
      log("navigated auth popup (URL not logged)");
    } catch {
      log("could not navigate popup; use fallback");
      showAuthFallback();
    }
  } else {
    showAuthFallback();
  }
}

function showAuthFallback() {
  authEl.hidden = false;
}

function hideAuthFallback() {
  authEl.hidden = true;
  authUrl = null;
  pendingPopup = null;
}

function renderPeers(list) {
  lastPeers = Array.isArray(list) ? list : [];
  const rows = lastPeers.map((p) => ({
    stableId: p.stableId || "",
    name: p.name || "",
    online: !!p.online,
    addresses: p.addresses || [],
  }));
  peersEl.textContent = JSON.stringify({ count: rows.length, peers: rows }, null, 2);
  if (!hostInput.value) {
    const first = rows.find((p) => (p.addresses || []).some((a) => a.includes(".")));
    const addr = first && (first.addresses || []).find((a) => /^\d+\.\d+\.\d+\.\d+$/.test(a));
    if (addr) hostInput.value = addr;
  }
}

const worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
const rpc = new RpcClient(worker, {
  queueLimit: 32,
  onEvent(evt) {
    if (evt.method === "state") {
      stateEl.textContent = evt.payload.ipn || "";
      log(`state ${evt.payload.ipn}`);
      if (evt.payload.ipn === "Running") hideAuthFallback();
      if (evt.payload.ipn === "NeedsMachineAuth") log("needs machine approval in Tailscale admin");
    } else if (evt.method === "browseToURL") {
      log(`browseToURL hasUrl=${!!evt.payload.hasUrl} fallback=${!!evt.payload.fallback}`);
      applyAuthUrl(evt.payload.url);
    } else if (evt.method === "netMap") {
      renderPeers(evt.payload.peers);
      log(`netMap peers=${evt.payload.peerCount} selfStableId=${evt.payload.selfStableId || ""}`);
    } else if (evt.method === "panic") {
      log("worker panic (details redacted)");
    } else if (evt.method === "cleared") {
      log("session state cleared");
      peersEl.textContent = "";
      lastPeers = [];
    } else if (evt.method === "wasmProgress") {
      log(evt.payload.message || "wasm");
    }
  },
});

worker.addEventListener("error", (e) => log(`worker crash: ${e.message || "error"}`));

async function initWasm() {
  backendEl.textContent = "wasm loading…";
  const r = await rpc.request("init", {
    backend: "wasm",
    hostname: "monkeycraft-web",
    wasmUrl: new URL("../dist/main.wasm", import.meta.url).href,
    wasmExecUrl: new URL("../dist/wasm_exec.js", import.meta.url).href,
  });
  backendEl.textContent = r.payload.backend || "wasm";
  log(`init ${JSON.stringify(r.payload)}`);
}

document.getElementById("btn-init").onclick = () => {
  initWasm().catch((err) => log(`init failed: ${err.code || ""} ${err.message}`));
};

document.getElementById("btn-init-fake").onclick = async () => {
  try {
    const r = await rpc.request("init", { backend: "fake" });
    backendEl.textContent = "fake";
    log(`init ${JSON.stringify(r.payload)}`);
  } catch (err) {
    log(`init failed: ${err.message}`);
  }
};

document.getElementById("btn-login").onclick = async () => {
  const popup = openAuthWindowSync();
  pendingPopup = popup.win;
  try {
    const r = await rpc.request("login", { popupBlocked: popup.blocked });
    log(`login ${JSON.stringify(r.payload)}`);
  } catch (err) {
    log(`login failed: ${err.code || ""} ${err.message}`);
  }
};

document.getElementById("btn-login-cancel").onclick = async () => {
  try {
    const r = await rpc.request("logout", {});
    hideAuthFallback();
    log(`cancel/logout ${JSON.stringify(r.payload)}`);
  } catch (err) {
    log(`cancel failed: ${err.message}`);
  }
};

document.getElementById("btn-logout").onclick = async () => {
  try {
    const r = await rpc.request("logout", {});
    peersEl.textContent = "";
    hideAuthFallback();
    log(`logout ${JSON.stringify(r.payload)}`);
  } catch (err) {
    log(`logout failed: ${err.message}`);
  }
};

document.getElementById("btn-echo").onclick = async () => {
  const host = (hostInput.value || "").trim();
  const port = Number(portInput.value || "9600");
  if (!host) {
    log("set echo host first (from peers after Running)");
    return;
  }
  try {
    const d = await rpc.request("dialTcp", { host, port, timeoutMs: 15000 });
    const connId = d.payload.connId;
    log(`dialed conn=${connId}`);
    const payload = new TextEncoder().encode("hello-echo");
    await rpc.request("connWrite", { connId }, [payload.buffer]);
    const read = await rpc.request("connRead", { connId });
    log(`echo n=${read.payload.n} eof=${!!read.payload.eof}`);
    await rpc.request("connClose", { connId });
  } catch (err) {
    log(`echo failed: ${err.code || ""} ${err.message}`);
  }
};

document.getElementById("btn-refresh").onclick = () => {
  location.reload();
};

authOpen.onclick = () => {
  if (!authUrl) return;
  const w = window.open(authUrl, "ts-auth", "width=480,height=720");
  if (!w) log("popup still blocked; use Copy login link");
  else log("opened login window from fallback button");
};

authCopy.onclick = async () => {
  if (!authUrl) return;
  try {
    await navigator.clipboard.writeText(authUrl);
    log("login URL copied (not printed here)");
  } catch {
    log("clipboard failed");
  }
};

window.addEventListener("error", (e) => log(`page error: ${e.message || ""}`));
window.__rpc = rpc;
window.__ERROR_CODES = ERROR_CODES;
log("poc ready — click Init WASM (loads ~35MB), then Login. Allow popups for 127.0.0.1.");
