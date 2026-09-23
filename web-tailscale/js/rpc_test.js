import { parseMessage, makeReq, RpcClient, ERROR_CODES } from "./rpc.js";
import { createFakeBackend } from "./fake-backend.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert");
}

function testParse() {
  const ok = parseMessage(makeReq("1", "hello", {}));
  assert(ok.method === "hello");
  let threw = false;
  try {
    parseMessage({ protocolVersion: 2, kind: "req", id: "1", method: "hello" });
  } catch (e) {
    threw = e.code === ERROR_CODES.PROTOCOL;
  }
  assert(threw, "version");
  threw = false;
  try {
    parseMessage({ protocolVersion: 1, kind: "req", id: "1", method: "socks" });
  } catch (e) {
    threw = e.code === ERROR_CODES.UNSUPPORTED;
  }
  assert(threw, "socks");
}

async function testFakeFlow() {
  const events = [];
  const fake = createFakeBackend((e) => events.push(e));
  const hello = await fake.handle({ id: "1", method: "hello", payload: {} });
  assert(hello.ok && hello.payload.backend === "fake");
  await fake.handle({ id: "2", method: "init", payload: {} });
  const login = await fake.handle({ id: "3", method: "login", payload: {} });
  assert(login.payload.running);
  const status = await fake.handle({ id: "4", method: "status", payload: {} });
  assert(status.payload.ipn === "Running");
  const dial = await fake.handle({ id: "5", method: "dialTcp", payload: { host: "100.64.0.1", port: 9600 } });
  const buf = new TextEncoder().encode("abc").buffer;
  await fake.handle({ id: "6", method: "connWrite", payload: { connId: dial.payload.connId } }, buf);
  const read = await fake.handle({ id: "7", method: "connRead", payload: { connId: dial.payload.connId } });
  assert(read.payload.n === 3);
  const logout = await fake.handle({ id: "8", method: "logout", payload: {} });
  assert(logout.ok);
  const after = await fake.handle({ id: "9", method: "status", payload: {} });
  assert(after.payload.loggedOut === true);
  assert(after.payload.hasNetMap === false);
  const blocked = await fake.handle({ id: "10", method: "login", payload: { popupBlocked: true } });
  assert(blocked.ok);
  const cancel = await fake.handle({ id: "11", method: "login", payload: { cancel: true } });
  assert(cancel.payload.cancelled);
  const limit1 = await fake.handle({ id: "12", method: "login", payload: {} });
  assert(limit1.ok);
  await fake.handle({ id: "13", method: "dialTcp", payload: { host: "100.64.0.1", port: 9600 } });
  const limit2 = await fake.handle({ id: "14", method: "dialTcp", payload: { host: "100.64.0.1", port: 9600 } });
  assert(limit2.ok === false && limit2.error.code === "CONN_LIMIT");
  const states = events.filter((e) => e.method === "state").map((e) => e.payload.ipn);
  assert(states.includes("NeedsLogin"));
  assert(states.includes("Running"));
  assert(states.includes("Stopped"));
}

class LoopbackPort {
  constructor() {
    this.other = null;
    this.onmessage = null;
  }
  postMessage(msg) {
    const other = this.other;
    queueMicrotask(() => {
      if (other && other.onmessage) other.onmessage({ data: msg });
    });
  }
}

async function testRpcClientQueue() {
  const a = new LoopbackPort();
  const b = new LoopbackPort();
  a.other = b;
  b.other = a;
  b.onmessage = (ev) => {
    b.postMessage({ protocolVersion: 1, kind: "res", id: ev.data.id, ok: true, payload: { echo: ev.data.method } });
  };
  const client = new RpcClient(a, { queueLimit: 2 });
  const r = await client.request("hello", {});
  assert(r.payload.echo === "hello");
}

await testParse();
await testFakeFlow();
await testRpcClientQueue();
console.log("js rpc tests ok");
