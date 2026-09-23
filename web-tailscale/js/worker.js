import { parseMessage, makeRes, makeEvt, ERROR_CODES, redact, PROTOCOL_VERSION } from "./rpc.js";
import { createFakeBackend } from "./fake-backend.js";

const MAX_QUEUE = 32;
const MAX_CONNS = 1;
let eventId = 0;
let backendMode = "fake";
let wasmReady = false;
let ipn = null;
let queue = 0;
let lastIpnState = "NoState";
const liveConns = new Set();
const persist = new Map();

function post(msg, transfer) {
  if (transfer && transfer.length) {
    self.postMessage(msg, transfer);
  } else {
    self.postMessage(msg);
  }
}

function emit(method, payload) {
  eventId += 1;
  post(makeEvt(eventId, method, payload));
}

const fake = createFakeBackend((m) => post(m));

function waitUntil(fn, timeoutMs, stepMs = 25) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      try {
        if (fn()) {
          resolve();
          return;
        }
      } catch {
        /* ignore */
      }
      if (Date.now() - start > timeoutMs) {
        reject(new Error("timeout waiting for wasm runtime"));
        return;
      }
      setTimeout(tick, stepMs);
    };
    tick();
  });
}

function sanitizePeer(p) {
  return {
    name: p && p.name ? String(p.name) : "",
    addresses: Array.isArray(p && p.addresses) ? p.addresses.map(String) : [],
    stableId: p && (p.stableId || p.stableID) ? String(p.stableId || p.stableID) : "",
    nodeId: p && (p.nodeId || p.nodeID) ? String(p.nodeId || p.nodeID) : "",
    online: !!(p && p.online),
  };
}

self.onmessage = async (ev) => {
  const data = ev.data;
  if (!data) return;
  if (queue >= MAX_QUEUE) {
    if (data.id) {
      post(
        makeRes(data.id, false, null, {
          code: ERROR_CODES.QUEUE_FULL,
          message: "queue full",
        }),
      );
    }
    return;
  }
  queue += 1;
  try {
    const msg = parseMessage(data);
    if (msg.kind !== "req") return;

    if (msg.method === "hello") {
      post(makeRes(msg.id, true, { protocolVersion: PROTOCOL_VERSION, backend: backendMode, wasmReady }));
      return;
    }

    if (msg.method === "init") {
      const want = (msg.payload && msg.payload.backend) || "fake";
      if (want === "wasm") {
        try {
          emit("wasmProgress", { message: "loading wasm (~35MB)" });
          await ensureWasm(msg.payload || {});
          backendMode = "wasm";
          post(makeRes(msg.id, true, { ok: true, backend: "wasm" }));
        } catch (err) {
          backendMode = "fake";
          wasmReady = false;
          ipn = null;
          post(
            makeRes(msg.id, false, null, {
              code: ERROR_CODES.WASM_LOAD,
              message: redact(err.message || "wasm load").slice(0, 200),
            }),
          );
        }
        return;
      }
      backendMode = "fake";
      const res = await fake.handle(msg, data.buffer);
      post(res);
      return;
    }

    if (backendMode !== "wasm" || !wasmReady) {
      const res = await fake.handle(msg, data.buffer);
      if (res.payload && res.payload.data instanceof Uint8Array) {
        const buf = res.payload.data.buffer.slice(0);
        const copy = {
          ...res,
          payload: { ...res.payload, data: undefined, bytes: res.payload.data.byteLength },
        };
        post(copy, [buf]);
        return;
      }
      post(res);
      return;
    }

    await handleWasm(msg, data.buffer);
  } catch (err) {
    if (data.id) {
      post(
        makeRes(data.id, false, null, {
          code: err.code || ERROR_CODES.PROTOCOL,
          message: redact(err.message || "error").slice(0, 200),
        }),
      );
    }
  } finally {
    queue -= 1;
  }
};

self.addEventListener("error", () => {
  emit("panic", { message: "worker crash" });
});

async function ensureWasm(payload) {
  if (wasmReady && ipn) return;
  const wasmUrl = payload.wasmUrl;
  const execUrl = payload.wasmExecUrl;
  if (!wasmUrl || !execUrl) {
    throw Object.assign(new Error("missing wasm urls"), { code: ERROR_CODES.WASM_LOAD });
  }
  let parsed;
  try {
    parsed = new URL(wasmUrl, self.location.href);
  } catch {
    throw Object.assign(new Error("bad wasm url"), { code: ERROR_CODES.WASM_LOAD });
  }
  if (parsed.origin !== self.location.origin) {
    throw Object.assign(new Error("refusing unpinned remote wasm"), { code: ERROR_CODES.WASM_LOAD });
  }

  emit("wasmProgress", { message: "fetching wasm_exec.js" });
  const execSrc = await fetch(execUrl).then((r) => {
    if (!r.ok) throw new Error("wasm_exec fetch failed");
    return r.text();
  });
  (0, eval)(execSrc);
  if (typeof self.Go !== "function") {
    throw new Error("Go runtime missing after wasm_exec");
  }

  emit("wasmProgress", { message: "fetching main.wasm" });
  const go = new self.Go();
  const resp = await fetch(wasmUrl);
  if (!resp.ok) throw new Error("wasm fetch failed " + resp.status);
  const bytes = await resp.arrayBuffer();
  emit("wasmProgress", { message: "instantiating wasm" });
  const result = await WebAssembly.instantiate(bytes, go.importObject);
  go.run(result.instance);
  await waitUntil(() => typeof self.newIPN === "function", 15000);
  emit("wasmProgress", { message: "starting ipn" });

  ipn = self.newIPN({
    hostname: payload.hostname || "monkeycraft-web",
    stateStorage: {
      setState(id, value) {
        persist.set(String(id), String(value));
      },
      getState(id) {
        return persist.get(String(id)) || "";
      },
    },
  });
  ipn.run({
    notifyState(state) {
      lastIpnState = String(state || "");
      emit("state", { ipn: lastIpnState });
    },
    notifyNetMap(netMapStr) {
      let peerCount = 0;
      let selfStableId = "";
      let peers = [];
      try {
        const nm = JSON.parse(netMapStr);
        const selfNode = sanitizePeer(nm.self || {});
        selfStableId = selfNode.stableId || selfNode.nodeId;
        peers = Array.isArray(nm.peers) ? nm.peers.map(sanitizePeer) : [];
        peerCount = peers.length;
        self._lastNetMap = { self: selfNode, peers, lockedOut: !!nm.lockedOut };
      } catch {
        peerCount = -1;
      }
      emit("netMap", { peerCount, selfStableId, peers });
    },
    notifyBrowseToURL(url) {
      emit("browseToURL", { hasUrl: typeof url === "string" && url.length > 0, fallback: false, url });
    },
    notifyPanicRecover() {
      emit("panic", { message: "recovered" });
    },
  });
  wasmReady = true;
  emit("wasmProgress", { message: "wasm ipn running" });
}

async function handleWasm(msg, buffer) {
  const { id, method, payload } = msg;
  try {
    switch (method) {
      case "login":
        ipn.login();
        post(makeRes(id, true, { ok: true }));
        return;
      case "logout":
        for (const c of [...liveConns]) {
          try {
            await ipn.connClose(c);
          } catch {
            /* ignore */
          }
        }
        liveConns.clear();
        persist.clear();
        ipn.logout();
        lastIpnState = "Stopped";
        emit("cleared", { storage: "memory" });
        post(makeRes(id, true, { ok: true }));
        return;
      case "status":
        post(
          makeRes(id, true, {
            wasmReady,
            connCount: liveConns.size,
            ipn: lastIpnState,
            hasNetMap: !!self._lastNetMap,
          }),
        );
        return;
      case "dialTcp": {
        if (lastIpnState !== "Running") {
          post(makeRes(id, false, null, { code: ERROR_CODES.NOT_RUNNING, message: "not running" }));
          return;
        }
        if (liveConns.size >= MAX_CONNS) {
          post(makeRes(id, false, null, { code: ERROR_CODES.CONN_LIMIT, message: "conn limit" }));
          return;
        }
        if (!ipn.dialTcp) {
          post(makeRes(id, false, null, { code: ERROR_CODES.UNSUPPORTED, message: "dialTcp missing" }));
          return;
        }
        const r = await ipn.dialTcp(payload.host, payload.port, payload.timeoutMs || 15000);
        liveConns.add(r.connId);
        post(makeRes(id, true, { connId: r.connId }));
        return;
      }
      case "connWrite": {
        const n = await ipn.connWrite(payload.connId, buffer ? new Uint8Array(buffer) : new Uint8Array());
        post(makeRes(id, true, n));
        return;
      }
      case "connRead": {
        const r = await ipn.connRead(payload.connId, payload.max || 65536);
        if (r && r.data && r.data.buffer) {
          const buf = r.data.buffer;
          const msg = makeRes(id, true, { n: r.n, eof: !!r.eof });
          msg.buffer = buf;
          post(msg, [buf]);
          return;
        }
        post(makeRes(id, true, r || { n: 0, eof: true }));
        return;
      }
      case "connClose":
        liveConns.delete(payload.connId);
        await ipn.connClose(payload.connId);
        post(makeRes(id, true, { ok: true }));
        return;
      case "shutdown":
        persist.clear();
        post(makeRes(id, true, { ok: true }));
        return;
      default:
        post(makeRes(id, false, null, { code: ERROR_CODES.UNSUPPORTED, message: method }));
    }
  } catch (err) {
    post(
      makeRes(id, false, null, {
        code: ERROR_CODES.INTERNAL,
        message: redact(err.message || "error").slice(0, 200),
      }),
    );
  }
}
