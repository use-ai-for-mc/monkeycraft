import { render } from "preact";
import { App, createAppContext } from "./ui/app.tsx";
import { H264Decoder } from "./video/decoder.ts";
import { DecodeQueuePolicy } from "./video/queue-policy.ts";
import "./ui/styles.css";

const ctx = createAppContext();

// Test hook: browser tests drive the decoder with recorded access units and
// send control messages through the live session.
Object.assign(globalThis, {
  __monkeycraft: {
    H264Decoder,
    DecodeQueuePolicy,
    send: (msg: unknown) => ctx.controller.send(msg as never),
    state: () => ctx.controller.snapshot,
  },
});

const root = document.getElementById("app");
if (!root) throw new Error("missing #app root");
render(<App ctx={ctx} />, root);
