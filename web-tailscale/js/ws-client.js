const OP_CONT = 0x0;
const OP_TEXT = 0x1;
const OP_BIN = 0x2;
const OP_CLOSE = 0x8;
const OP_PING = 0x9;
const OP_PONG = 0xa;
const MAX_CONTROL = 125;

export class WsProtocolError extends Error {
  constructor(msg) {
    super(msg);
    this.name = "WsProtocolError";
  }
}

export function maskInPlace(key, payload) {
  for (let i = 0; i < payload.length; i++) payload[i] ^= key[i & 3];
}

export function encodeFrame({ fin = true, opcode, payload, maskKey }) {
  const data = payload instanceof Uint8Array ? payload : new Uint8Array(payload || 0);
  if ((opcode === OP_CLOSE || opcode === OP_PING || opcode === OP_PONG) && (!fin || data.length > MAX_CONTROL)) {
    throw new WsProtocolError("control frame");
  }
  const n = data.length;
  let headerLen = 2;
  let lenByte = n;
  if (n > 0xffff) {
    headerLen += 8;
    lenByte = 127;
  } else if (n > 125) {
    headerLen += 2;
    lenByte = 126;
  }
  const masked = !!maskKey;
  if (masked) headerLen += 4;
  const out = new Uint8Array(headerLen + n);
  out[0] = (fin ? 0x80 : 0) | (opcode & 0x0f);
  out[1] = (masked ? 0x80 : 0) | lenByte;
  let off = 2;
  if (lenByte === 126) {
    out[2] = (n >> 8) & 0xff;
    out[3] = n & 0xff;
    off = 4;
  } else if (lenByte === 127) {
    const view = new DataView(out.buffer);
    view.setUint32(2, 0);
    view.setUint32(6, n);
    off = 10;
  }
  const copy = new Uint8Array(data);
  if (masked) {
    out.set(maskKey, off);
    off += 4;
    maskInPlace(maskKey, copy);
  }
  out.set(copy, off);
  return out;
}

export function decodeFrame(buf, expectMasked) {
  if (buf.length < 2) throw new WsProtocolError("short");
  const fin = (buf[0] & 0x80) !== 0;
  if (buf[0] & 0x70) throw new WsProtocolError("rsv");
  const opcode = buf[0] & 0x0f;
  const masked = (buf[1] & 0x80) !== 0;
  if (expectMasked && !masked) throw new WsProtocolError("unmasked client");
  if (!expectMasked && masked) throw new WsProtocolError("masked server");
  let n = buf[1] & 0x7f;
  let off = 2;
  if (n === 126) {
    if (buf.length < 4) throw new WsProtocolError("short");
    n = (buf[2] << 8) | buf[3];
    off = 4;
    if (n < 126) throw new WsProtocolError("non-minimal");
  } else if (n === 127) {
    if (buf.length < 10) throw new WsProtocolError("short");
    const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (view.getUint32(2) !== 0) throw new WsProtocolError("too big");
    n = view.getUint32(6);
    if (n < 65536) throw new WsProtocolError("non-minimal");
    off = 10;
  }
  if (n > 4 * 1024 * 1024) throw new WsProtocolError("too big");
  if (![OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG].includes(opcode)) throw new WsProtocolError("opcode");
  if (opcode >= OP_CLOSE && (!fin || n > MAX_CONTROL)) throw new WsProtocolError("control frame");
  if (buf.length < off + (masked ? 4 : 0) + n) throw new WsProtocolError("short");
  let key = null;
  if (masked) {
    key = buf.slice(off, off + 4);
    off += 4;
  }
  const payload = buf.slice(off, off + n);
  if (masked) maskInPlace(key, payload);
  return { fin, opcode, payload };
}

export function clientMaskKey() {
  const k = new Uint8Array(4);
  crypto.getRandomValues(k);
  return k;
}

export class WsAssembler {
  constructor(maxMessage = 4 * 1024 * 1024) {
    this.maxMessage = maxMessage;
    this.fragOp = 0;
    this.frag = [];
    this.fragLen = 0;
  }
  push(frame) {
    const { fin, opcode, payload } = frame;
    if (opcode === OP_PING || opcode === OP_PONG || opcode === OP_CLOSE) {
      return { control: opcode, payload };
    }
    if (opcode === OP_CONT) {
      if (!this.fragOp) throw new WsProtocolError("unexpected continuation");
      this._append(payload);
      if (fin) return this._finish();
      return null;
    }
    if (opcode !== OP_TEXT && opcode !== OP_BIN) throw new WsProtocolError("bad opcode");
    if (this.fragOp) throw new WsProtocolError("data during fragment");
    if (!fin) {
      this.fragOp = opcode;
      this._append(payload);
      return null;
    }
    return { opcode, payload };
  }
  _append(p) {
    if (this.fragLen + p.length > this.maxMessage) throw new WsProtocolError("too big");
    this.frag.push(p);
    this.fragLen += p.length;
  }
  _finish() {
    const opcode = this.fragOp;
    const payload = new Uint8Array(this.fragLen);
    let o = 0;
    for (const p of this.frag) {
      payload.set(p, o);
      o += p.length;
    }
    this.fragOp = 0;
    this.frag = [];
    this.fragLen = 0;
    return { opcode, payload };
  }
}
