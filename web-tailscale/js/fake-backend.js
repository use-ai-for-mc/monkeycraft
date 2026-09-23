import { makeRes, makeEvt, ERROR_CODES, redact } from "./rpc.js";

const STATES = {
  NoState: "NoState",
  NeedsLogin: "NeedsLogin",
  NeedsMachineAuth: "NeedsMachineAuth",
  Starting: "Starting",
  Running: "Running",
  Stopped: "Stopped",
};

export function createFakeBackend(post) {
  let state = STATES.NoState;
  let netMap = null;
  let eventId = 0;
  let authWindowOpen = false;
  const conns = new Map();
  let nextConn = 0;
  const echoBuf = new Map();
  let loggedOut = true;

  function emit(method, payload) {
    eventId += 1;
    post(makeEvt(eventId, method, payload));
  }

  function setState(next) {
    state = next;
    emit("state", { ipn: state });
  }

  return {
    async handle(msg, buffer) {
      const { id, method, payload } = msg;
      try {
        const result = await dispatch(method, payload || {}, buffer);
        return makeRes(id, true, result);
      } catch (err) {
        return makeRes(id, false, null, {
          code: err.code || ERROR_CODES.INTERNAL,
          message: redact(err.message || "error").slice(0, 200),
        });
      }
    },
    crash() {
      emit("panic", { message: "fake crash" });
    },
    reset() {
      conns.clear();
      echoBuf.clear();
      netMap = null;
      state = STATES.Stopped;
    },
  };

  async function dispatch(method, payload, buffer) {
    switch (method) {
      case "hello":
        return { protocolVersion: 1, backend: "fake" };
      case "init":
        loggedOut = false;
        setState(STATES.NeedsLogin);
        return { ok: true, storage: "sessionStorage" };
      case "login":
        if (payload && payload.popupBlocked) {
          emit("browseToURL", { fallback: true, hasUrl: true });
        } else {
          authWindowOpen = true;
          emit("browseToURL", { fallback: false, hasUrl: true });
        }
        if (payload && payload.cancel) {
          setState(STATES.NeedsLogin);
          return { cancelled: true };
        }
        if (payload && payload.needsApproval) {
          setState(STATES.NeedsMachineAuth);
          return { needsApproval: true };
        }
        setState(STATES.Starting);
        setState(STATES.Running);
        netMap = {
          self: {
            name: "wasm-anchor",
            addresses: ["100.64.0.2"],
            stableId: "nStableSelf",
            nodeId: "123",
          },
          peers: [
            {
              name: "desktop",
              addresses: ["100.64.0.1"],
              stableId: "nStableDesktop",
              nodeId: "456",
              online: true,
            },
          ],
          lockedOut: false,
        };
        emit("netMap", {
          peerCount: netMap.peers.length,
          selfStableId: netMap.self.stableId,
          peers: netMap.peers,
        });
        return { running: true };
      case "logout":
        conns.clear();
        netMap = null;
        loggedOut = true;
        setState(STATES.Stopped);
        emit("cleared", { storage: "sessionStorage" });
        return { ok: true };
      case "status":
        return { ipn: state, hasNetMap: !!netMap, connCount: conns.size, loggedOut };
      case "dialTcp":
        if (state !== STATES.Running) {
          const err = new Error("not running");
          err.code = ERROR_CODES.NOT_RUNNING;
          throw err;
        }
        if (conns.size >= 1) {
          const err = new Error("conn limit");
          err.code = ERROR_CODES.CONN_LIMIT;
          throw err;
        }
        if (!payload.host || payload.port < 1 || payload.port > 65535) {
          const err = new Error("invalid target");
          err.code = ERROR_CODES.INVALID_TARGET;
          throw err;
        }
        nextConn += 1;
        const connId = `c${nextConn}`;
        conns.set(connId, { host: payload.host, port: payload.port });
        echoBuf.set(connId, new Uint8Array(0));
        return { connId };
      case "connWrite": {
        const id = payload.connId;
        if (!conns.has(id)) {
          const err = new Error("closed");
          err.code = ERROR_CODES.CLOSED;
          throw err;
        }
        const chunk = buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : new Uint8Array(0);
        const prev = echoBuf.get(id);
        const next = new Uint8Array(prev.length + chunk.length);
        next.set(prev);
        next.set(chunk, prev.length);
        echoBuf.set(id, next);
        return { n: chunk.length };
      }
      case "connRead": {
        const id = payload.connId;
        if (!conns.has(id)) {
          const err = new Error("closed");
          err.code = ERROR_CODES.CLOSED;
          throw err;
        }
        const buf = echoBuf.get(id);
        echoBuf.set(id, new Uint8Array(0));
        return { n: buf.length, eof: false, data: buf };
      }
      case "connClose":
        conns.delete(payload.connId);
        echoBuf.delete(payload.connId);
        return { ok: true };
      case "shutdown":
        conns.clear();
        setState(STATES.Stopped);
        return { ok: true };
      default: {
        const err = new Error("unsupported");
        err.code = ERROR_CODES.UNSUPPORTED;
        throw err;
      }
    }
  }
}
