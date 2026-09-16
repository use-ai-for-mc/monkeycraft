// Record a live session into a replayable fixture.
//
//   MONKEYCRAFT_PASSWORD=... node tools/record-session.ts --name streaming-360x640 \
//       --url ws://127.0.0.1:9600/ --seconds 10 --width 360 --height 640 --fps 10
//
// Output: test/fixtures/<name>/session.jsonl + binary.bin + meta.json.
// Each jsonl line is one message:
//   {"t":<ms>,"dir":"in"|"out","text":"<raw json>"}
//   {"t":<ms>,"dir":"in","bin":{"offset":n,"length":n,"kind":"video"|"map"|"unknown","idr":bool,"header":[w,h]?}}
// Passwords are never written: PAIR_OK.password is redacted, AUTH carries only salts and signatures.

import { closeSync, mkdirSync, openSync, writeFileSync, writeSync } from "node:fs";
import { join } from "node:path";
import { splitBinaryFrame } from "../src/protocol/frames.ts";
import { containsIdr } from "../src/protocol/h264.ts";
import { clientStatus, openSession, parseArgs } from "./lib/session.ts";

const args = parseArgs(process.argv.slice(2));
const name = args.name;
if (!name) {
  console.error("--name is required");
  process.exit(2);
}
const password = process.env.MONKEYCRAFT_PASSWORD ?? args.password;
if (!password) {
  console.error("set MONKEYCRAFT_PASSWORD or pass --password");
  process.exit(2);
}
const url = args.url ?? "ws://127.0.0.1:9600/";
const seconds = Number(args.seconds ?? 10);
const dir = join(import.meta.dirname, "..", "test", "fixtures", name);
mkdirSync(dir, { recursive: true });

const jsonl = openSync(join(dir, "session.jsonl"), "w");
const bin = openSync(join(dir, "binary.bin"), "w");
let binOffset = 0;
const counts = { text: 0, video: 0, idr: 0, headers: 0, map: 0, out: 0 };

function line(obj: Record<string, unknown>) {
  writeSync(jsonl, `${JSON.stringify(obj)}\n`);
}

function redact(raw: string): string {
  try {
    const msg = JSON.parse(raw) as Record<string, unknown>;
    if (typeof msg.password === "string") {
      msg.password = "<redacted>";
      return JSON.stringify(msg);
    }
  } catch {
    // keep raw
  }
  return raw;
}

let videoState = "";
const session = await openSession({
  url,
  password,
  deviceName: "web-recorder",
  onText(msg, raw, t) {
    counts.text++;
    if (msg.type === "SERVER_STATUS") videoState = String(msg.videoState ?? "");
    line({ t, dir: "in", text: redact(raw) });
  },
  onSend(raw, t) {
    counts.out++;
    line({ t, dir: "out", text: raw });
  },
  onBinary(data, t) {
    const frame = splitBinaryFrame(data);
    const entry: Record<string, unknown> = {
      offset: binOffset,
      length: data.length,
      kind: frame.kind,
    };
    if (frame.kind === "video") {
      counts.video++;
      const idr = containsIdr(frame.au);
      entry.idr = idr;
      if (idr) counts.idr++;
      if (frame.width !== undefined) {
        counts.headers++;
        entry.header = [frame.width, frame.height];
      }
    } else if (frame.kind === "map") {
      counts.map++;
    }
    writeSync(bin, data);
    binOffset += data.length;
    line({ t, dir: "in", bin: entry });
  },
});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// --waitActive N: send CLIENT_STATUS, then wait up to N seconds for
// SERVER_STATUS.videoState == ACTIVE before the recording clock starts.
const status = clientStatus(args);
session.send(status);
const waitActive = Number(args.waitActive ?? 0);
if (waitActive > 0) {
  const deadline = Date.now() + waitActive * 1000;
  while (videoState !== "ACTIVE" && Date.now() < deadline) {
    await sleep(2000);
    session.send({ type: "PING" });
  }
  console.log(`videoState=${videoState} after waiting`);
}

// --inventory: open the inventory with INPUT E after 3 s and close it with
// SCREEN_KEY ESCAPE 2 s before the end, so the fixture has SCREEN_STATE transitions.
const inventory = args.inventory === "true";
if (inventory) {
  await sleep(3000);
  session.send({ type: "INPUT", key: "E", pressed: true });
  session.send({ type: "INPUT", key: "E", pressed: false });
  await sleep(Math.max(0, seconds * 1000 - 5000));
  session.send({ type: "SCREEN_KEY", key: "ESCAPE", pressed: true });
  session.send({ type: "SCREEN_KEY", key: "ESCAPE", pressed: false });
  await sleep(2000);
} else {
  await sleep(seconds * 1000);
}
session.close();
closeSync(jsonl);
closeSync(bin);
writeFileSync(
  join(dir, "meta.json"),
  `${JSON.stringify(
    {
      recordedAt: new Date().toISOString(),
      seconds,
      clientStatus: status,
      capabilities: session.capabilities,
      counts,
      binaryBytes: binOffset,
    },
    null,
    2,
  )}\n`,
);
console.log(`recorded ${name}:`, counts, `${(binOffset / 1024).toFixed(0)} kB binary`);
