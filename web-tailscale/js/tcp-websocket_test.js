import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { TcpWebSocket } from './tcp-websocket.js';
import { encodeFrame, decodeFrame } from './ws-client.js';

const large = new Uint8Array(180000).map((_, i) => i % 251);
const largeFrame = encodeFrame({ opcode: 2, payload: large });
assert.deepEqual(decodeFrame(largeFrame, false).payload, large);
assert.throws(() => decodeFrame(largeFrame.subarray(0, 1000), false), /short/);
const malicious = largeFrame.slice(0, 10);
malicious[2] = 1;
assert.throws(() => decodeFrame(malicious, false), /too big/);

const encoder = new TextEncoder();
const chunks = [];
let closed = false;
let writes = 0;
const rpc = {
  async request(method, payload, transfer) {
    if (method === 'dialTcp') return { payload: { connId: 'test' } };
    if (method === 'connWrite') {
      const bytes = new Uint8Array(transfer[0]);
      if (writes++ === 0) {
        const key = new TextDecoder().decode(bytes).match(/Sec-WebSocket-Key: (.+)\r\n/)[1];
        const accept = createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
        const headers = encoder.encode(`HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
        const hello = encodeFrame({ opcode: 1, payload: encoder.encode('hello') });
        const combined = new Uint8Array(headers.length + hello.length + largeFrame.length);
        combined.set(headers); combined.set(hello, headers.length); combined.set(largeFrame, headers.length + hello.length);
        chunks.push(combined.slice(0, 5), combined.slice(5, headers.length + hello.length + 7));
        for (let i = headers.length + hello.length + 7; i < combined.length; i += 17000) chunks.push(combined.slice(i, i + 17000));
      }
      return { payload: { n: bytes.length } };
    }
    if (method === 'connRead') {
      const data = chunks.shift();
      assert.ok(data, 'no unexpected read');
      return { payload: { n: data.length }, buffer: data.buffer };
    }
    if (method === 'connClose') { closed = true; return { payload: {} }; }
    throw new Error(method);
  },
};
const socket = new TcpWebSocket(rpc);
await socket.open('100.64.0.1', 9600);
assert.equal(await socket.read(), 'hello');
assert.deepEqual(await socket.read(), large);
await socket.close();
assert.equal(closed, true);
console.log('large video frames, split TCP reads and coalesced upgrade+HELLO passed');
