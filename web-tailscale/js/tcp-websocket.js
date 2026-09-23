import { encodeFrame, decodeFrame, WsAssembler, clientMaskKey } from "./ws-client.js";

const encode = new TextEncoder();
const decode = new TextDecoder("utf-8", { fatal: true });
const base64 = bytes => btoa(String.fromCharCode(...bytes));

export class TcpWebSocket {
  constructor(rpc) {
    this.rpc = rpc;
    this.connId = null;
    this.buffer = new Uint8Array();
    this.assembler = new WsAssembler();
    this.writeQueue = Promise.resolve();
  }

  async open(host, port) {
    if (!/^[a-zA-Z0-9.:_-]+$/.test(host)) throw new Error("invalid host");
    const reply = await this.rpc.request("dialTcp", { host, port, timeoutMs: 15000 });
    this.connId = reply.payload.connId;
    try {
      const key = base64(crypto.getRandomValues(new Uint8Array(16)));
      await this.write(encode.encode(`GET / HTTP/1.1\r\nHost: ${host}:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`));
      let end = -1;
      while (end < 0) {
        await this.readMore();
        for (let i = 0; i + 3 < this.buffer.length; i++) {
          if (this.buffer[i] === 13 && this.buffer[i+1] === 10 && this.buffer[i+2] === 13 && this.buffer[i+3] === 10) { end = i; break; }
        }
        if (end < 0 && this.buffer.length > 16384) throw new Error("oversized upgrade response");
      }
      const lines = decode.decode(this.buffer.slice(0, end)).split("\r\n");
      const headers = new Map(lines.slice(1).map(line => {
        const colon = line.indexOf(":");
        return [line.slice(0, colon).toLowerCase(), line.slice(colon + 1).trim()];
      }));
      const expected = base64(new Uint8Array(await crypto.subtle.digest("SHA-1", encode.encode(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))));
      if (!/^HTTP\/1\.[01] 101(?: |$)/.test(lines[0]) || headers.get("sec-websocket-accept") !== expected || headers.get("upgrade")?.toLowerCase() !== "websocket" || !headers.get("connection")?.toLowerCase().split(/\s*,\s*/).includes("upgrade")) throw new Error("invalid websocket upgrade");
      this.buffer = this.buffer.slice(end + 4);
    } catch (error) { await this.close(); throw error; }
  }

  write(bytes) {
    const operation = this.writeQueue.then(async () => {
      let offset = 0;
      while (offset < bytes.length) {
        const part = bytes.slice(offset);
        const response = await this.rpc.request("connWrite", { connId: this.connId }, [part.buffer]);
        const n = response.payload.n;
        if (!Number.isInteger(n) || n <= 0 || n > bytes.length - offset) throw new Error("invalid TCP write count");
        offset += n;
      }
    });
    this.writeQueue = operation.catch(() => {});
    return operation;
  }

  send(payload, opcode = 1) {
    return this.write(encodeFrame({ opcode, payload: typeof payload === "string" ? encode.encode(payload) : payload, maskKey: clientMaskKey() }));
  }

  async readMore() {
    const response = await this.rpc.request("connRead", { connId: this.connId, max: 65536 });
    if (!response.buffer || response.payload.n <= 0) throw new Error("TCP stream closed");
    const part = new Uint8Array(response.buffer, 0, response.payload.n);
    if (this.buffer.length + part.length > 4 * 1024 * 1024 + 65550) throw new Error("receive buffer limit");
    const next = new Uint8Array(this.buffer.length + part.length);
    next.set(this.buffer); next.set(part, this.buffer.length); this.buffer = next;
  }

  async read() {
    while (this.connId) {
      while (this.buffer.length < 2) await this.readMore();
      const lengthCode = this.buffer[1] & 127;
      const headerLength = lengthCode === 127 ? 10 : lengthCode === 126 ? 4 : 2;
      while (this.buffer.length < headerLength) await this.readMore();
      const view = new DataView(this.buffer.buffer, this.buffer.byteOffset, this.buffer.byteLength);
      if (lengthCode === 127 && view.getUint32(2) !== 0) throw new Error("frame too large");
      const length = lengthCode === 127 ? view.getUint32(6) : lengthCode === 126 ? view.getUint16(2) : lengthCode;
      if (length > 4 * 1024 * 1024) throw new Error("frame too large");
      const total = headerLength + length;
      while (this.buffer.length < total) await this.readMore();
      const frame = decodeFrame(this.buffer.subarray(0, total), false);
      this.buffer = this.buffer.slice(total);
      const message = this.assembler.push(frame);
      if (!message) continue;
      if (message.control === 9) { await this.send(message.payload, 10); continue; }
      if (message.control === 10) continue;
      if (message.control === 8) throw new Error("websocket closed");
      return message.opcode === 1 ? decode.decode(message.payload) : message.payload;
    }
    throw new Error("websocket closed");
  }

  async close() {
    const connId = this.connId;
    this.connId = null;
    if (connId) await this.rpc.request("connClose", { connId });
  }
}
