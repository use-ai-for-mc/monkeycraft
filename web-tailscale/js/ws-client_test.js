import { encodeFrame, decodeFrame, WsAssembler, clientMaskKey } from "./ws-client.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert");
}

const hello = encodeFrame({
  opcode: 0x1,
  payload: new TextEncoder().encode("Hello"),
});
const unmasked = decodeFrame(hello, false);
assert(new TextDecoder().decode(unmasked.payload) === "Hello");

const key = clientMaskKey();
const masked = encodeFrame({
  opcode: 0x2,
  payload: new Uint8Array([1, 2, 3, 4, 5]),
  maskKey: key,
});
assert((masked[1] & 0x80) !== 0);
const got = decodeFrame(masked, true);
assert(got.payload.length === 5 && got.payload[0] === 1);

const asm = new WsAssembler();
assert(asm.push({ fin: false, opcode: 0x2, payload: new Uint8Array([1, 2]) }) === null);
const msg = asm.push({ fin: true, opcode: 0x0, payload: new Uint8Array([3, 4]) });
assert(msg.opcode === 0x2 && msg.payload.length === 4 && msg.payload[3] === 4);

let threw = false;
try {
  new WsAssembler().push({ fin: true, opcode: 0x0, payload: new Uint8Array(1) });
} catch {
  threw = true;
}
assert(threw, "unexpected continuation");

console.log("js ws-client tests ok");
