export const PROTOCOL_VERSION = 1;

export const METHODS = Object.freeze([
  "hello",
  "init",
  "login",
  "logout",
  "status",
  "dialTcp",
  "connRead",
  "connWrite",
  "connClose",
  "wsOpen",
  "wsSend",
  "wsClose",
  "shutdown",
]);

export const ERROR_CODES = Object.freeze({
  PROTOCOL: "PROTOCOL",
  UNSUPPORTED: "UNSUPPORTED",
  NOT_RUNNING: "NOT_RUNNING",
  NEEDS_LOGIN: "NEEDS_LOGIN",
  NEEDS_APPROVAL: "NEEDS_APPROVAL",
  CANCELLED: "CANCELLED",
  TIMEOUT: "TIMEOUT",
  QUEUE_FULL: "QUEUE_FULL",
  CONN_LIMIT: "CONN_LIMIT",
  INVALID_TARGET: "INVALID_TARGET",
  CLOSED: "CLOSED",
  WORKER_CRASH: "WORKER_CRASH",
  WASM_LOAD: "WASM_LOAD",
  WSS_BLOCKED: "WSS_BLOCKED",
  INTERNAL: "INTERNAL",
});

const MAX_JSON = 64 * 1024;

export function makeReq(id, method, payload) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    kind: "req",
    id,
    method,
    payload: payload || {},
  };
}

export function makeRes(id, ok, payload, error) {
  const msg = {
    protocolVersion: PROTOCOL_VERSION,
    kind: "res",
    id,
    ok,
  };
  if (payload) msg.payload = payload;
  if (error) msg.error = error;
  return msg;
}

export function makeEvt(eventId, method, payload) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    kind: "evt",
    eventId,
    method,
    payload: payload || {},
  };
}

export function parseMessage(raw) {
  if (typeof raw !== "string" && !(raw instanceof ArrayBuffer) && typeof raw !== "object") {
    throw Object.assign(new Error("bad rpc"), { code: ERROR_CODES.PROTOCOL });
  }
  const obj = typeof raw === "string" ? JSON.parse(raw) : raw;
  const encoded = JSON.stringify(obj);
  if (encoded.length > MAX_JSON) {
    throw Object.assign(new Error("too large"), { code: ERROR_CODES.PROTOCOL });
  }
  if (obj.protocolVersion !== PROTOCOL_VERSION) {
    throw Object.assign(new Error("bad version"), { code: ERROR_CODES.PROTOCOL });
  }
  if (!["req", "res", "evt", "bin"].includes(obj.kind)) {
    throw Object.assign(new Error("bad kind"), { code: ERROR_CODES.PROTOCOL });
  }
  if ((obj.kind === "req" || obj.kind === "res") && !obj.id) {
    throw Object.assign(new Error("missing id"), { code: ERROR_CODES.PROTOCOL });
  }
  if (obj.kind === "req" && !METHODS.includes(obj.method)) {
    throw Object.assign(new Error("unknown method"), { code: ERROR_CODES.UNSUPPORTED });
  }
  return obj;
}

export function redact(value) {
  if (value == null) return value;
  if (typeof value !== "string") return value;
  return value
    .replace(/https?:\/\/[^\s]+/g, (u) => {
      try {
        const url = new URL(u);
        return `${url.protocol}//${url.host}/[redacted]`;
      } catch {
        return "[redacted-url]";
      }
    })
    .replace(/tskey-[a-z0-9_-]+/gi, "tskey-[redacted]")
    .replace(/\bnodekey:[0-9a-f]+/gi, "nodekey:[redacted]")
    .replace(/\bmachinekey:[0-9a-f]+/gi, "machinekey:[redacted]");
}

export class RpcClient {
  constructor(port, opts = {}) {
    this.port = port;
    this.pending = new Map();
    this.eventIdSeen = 0;
    this.onEvent = opts.onEvent || (() => {});
    this.queueLimit = opts.queueLimit || 32;
    this.port.onmessage = (ev) => this._onMessage(ev);
    this.port.onmessageerror = () => this._failAll("WORKER_CRASH", "message error");
  }

  _onMessage(ev) {
    const data = ev.data;
    if (!data || typeof data !== "object") return;
    if (data.kind === "evt") {
      this.onEvent(data);
      return;
    }
    if (data.kind !== "res") return;
    const p = this.pending.get(data.id);
    if (!p) return;
    this.pending.delete(data.id);
    if (data.ok === false) {
      const err = new Error(redact((data.error && data.error.message) || "error"));
      err.code = (data.error && data.error.code) || ERROR_CODES.INTERNAL;
      p.reject(err);
      return;
    }
    p.resolve({ payload: data.payload || {}, buffer: ev.data.buffer || null });
  }

  request(method, payload, transfer) {
    if (this.pending.size >= this.queueLimit) {
      const err = new Error("queue full");
      err.code = ERROR_CODES.QUEUE_FULL;
      return Promise.reject(err);
    }
    const id = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const msg = makeReq(id, method, payload);
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      if (transfer && transfer.length) {
        this.port.postMessage({ ...msg, buffer: transfer[0] }, transfer);
      } else {
        this.port.postMessage(msg);
      }
    });
  }

  _failAll(code, message) {
    for (const [, p] of this.pending) {
      const err = new Error(message);
      err.code = code;
      p.reject(err);
    }
    this.pending.clear();
  }

  cancelAll(code = ERROR_CODES.CANCELLED) {
    this._failAll(code, "cancelled");
  }
}
