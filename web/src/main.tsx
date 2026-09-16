import { render } from "preact";
import { App, createAppContext } from "./ui/app.tsx";
import { H264Decoder } from "./video/decoder.ts";
import { DecodeQueuePolicy } from "./video/queue-policy.ts";
import "./ui/styles.css";

// Test hook: browser tests drive the decoder with recorded access units.
Object.assign(globalThis, { __monkeycraft: { H264Decoder, DecodeQueuePolicy } });

const root = document.getElementById("app");
if (!root) throw new Error("missing #app root");
render(<App ctx={createAppContext()} />, root);
