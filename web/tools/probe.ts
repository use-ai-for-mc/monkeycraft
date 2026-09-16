// Live protocol probe: authenticate, request video, print per-second stats.
//
//   MONKEYCRAFT_PASSWORD=... node tools/probe.ts --url ws://127.0.0.1:9600/ --seconds 20 \
//       --width 360 --height 640 --fps 10 [--dataSaver true]

import { splitBinaryFrame } from "../src/protocol/frames.ts";
import { codecStringFromSps, containsIdr, findSps } from "../src/protocol/h264.ts";
import { clientStatus, openSession, parseArgs } from "./lib/session.ts";

const args = parseArgs(process.argv.slice(2));
const url = args.url ?? "ws://127.0.0.1:9600/";
const seconds = Number(args.seconds ?? 20);
const password = process.env.MONKEYCRAFT_PASSWORD ?? args.password;
if (!password) {
  console.error("set MONKEYCRAFT_PASSWORD or pass --password");
  process.exit(2);
}

let frames = 0;
let bytes = 0;
let idr = 0;
let headers = 0;
let lastHeader = "";
let codec = "";
let heartbeatSentAt = 0;
let lastRtt = -1;
let videoState = "?";
const textCounts = new Map<string, number>();

const session = await openSession({
  url,
  password,
  deviceName: "web-probe",
  onText(msg, _raw, t) {
    const type = String(msg.type);
    textCounts.set(type, (textCounts.get(type) ?? 0) + 1);
    if (type === "HEARTBEAT_ACK" && heartbeatSentAt) lastRtt = t - heartbeatSentAt;
    if (type === "SERVER_STATUS") videoState = String(msg.videoState ?? "?");
    const fireAt = type === "TIMED_STATUS" ? msg.fireAtEpochMs : msg.timedFireAtEpochMs;
    if (typeof fireAt === "number") {
      const title = String(msg.title ?? msg.timedTitle ?? "");
      console.log(`timed: "${title}" fires in ${((fireAt - Date.now()) / 1000).toFixed(0)}s`);
    }
  },
  onBinary(data) {
    const frame = splitBinaryFrame(data);
    if (frame.kind !== "video") return;
    frames++;
    bytes += data.length;
    if (frame.width !== undefined) {
      headers++;
      lastHeader = `${frame.width}x${frame.height}`;
    }
    if (containsIdr(frame.au)) {
      idr++;
      if (!codec) {
        const sps = findSps(frame.au);
        codec = (sps && codecStringFromSps(sps)) ?? "?";
      }
    }
  },
  onClose(code, reason) {
    console.log(`closed ${code} ${reason}`);
  },
});

console.log(`authenticated; keyId=${session.keyId} capabilities=${session.capabilities.join(",")}`);
session.send(clientStatus(args));

let prevFrames = 0;
let prevBytes = 0;
for (let s = 1; s <= seconds; s++) {
  await new Promise((r) => setTimeout(r, 1000));
  if (s % 3 === 0) {
    heartbeatSentAt = Date.now() - session.startedAt;
    session.send({ type: "HEARTBEAT" });
  }
  const df = frames - prevFrames;
  const db = bytes - prevBytes;
  prevFrames = frames;
  prevBytes = bytes;
  console.log(
    `t=${s}s fps=${df} kB/s=${(db / 1024).toFixed(1)} total=${frames} idr=${idr} headers=${headers} ` +
      `last=${lastHeader || "-"} codec=${codec || "-"} video=${videoState} rtt=${lastRtt}ms`,
  );
}
console.log("text messages:", Object.fromEntries(textCounts));
session.close();
