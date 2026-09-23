# web-tailscale

Isolated MonkeyCraft web/WASM Tailscale spike (Prompt C: W0/W2/W3/W4).

This directory is an experimental implementation retained for browser Tailscale integration. It does not modify Flutter, the Minecraft mods, or `native/tailscale-helper/`. The Flutter Pages build now packages only the Worker, storage, RPC and pinned WASM runtime; the POC and diagnostic probe remain excluded.

## What this is

A Dedicated Worker + versioned RPC + portable RFC 6455 parser + a **narrow** `dialTcp` patch on top of Tailscale `cmd/tsconnect/wasm`.

It is **not** a product UI, not a SOCKS proxy, not Tailcat, and not a Flutter integration.

## Live WASM login (local Chrome)

```bash
python3 scripts/serve.py          # http://127.0.0.1:8765/poc/
```

1. Chrome: allow popups for `127.0.0.1`.
2. **Init WASM** (first load ~35MB, 10–30s). backend should become `wasm`.
3. **Login** — a popup must open in that click. Sign in / approve the ephemeral node.
4. Wait until IPN is `Running`. Peers list shows `stableId` + addresses (no keys).
5. Optional: put a peer Tailscale IP in echo host and **dialTcp echo** (requires the TCP echo test server; the game port is not an echo server).
6. **Logout** clears in-memory node state.

Do not use `file://`. If the popup is blocked, use **Open login page** / **Copy login link**. The log never prints the auth URL.

## Quick test (no Tailnet, no WASM)

```bash
./scripts/test.sh
```

Runs Go unit/race/fuzz, Node RPC/WS tests, and Chrome headless (`--headless=new`) against a fake backend.

## WASM build (fixed upstream, no CDN)

```bash
./scripts/fetch-upstream.sh
./scripts/build-wasm.sh
```

- Upstream: `tailscale.com` **v1.102.3** / commit `53a0d659afa51835dd7a9283873cca44261454f8` (see `LOCK.json`)
- `wasm_exec.js` is copied from the **same** Go toolchain that compiled `main.wasm`
- Output: `dist/main.wasm`, `dist/wasm_exec.js`, `dist/VERSION.json`

`@tailscale/connect` is **not** used: its public API has `login` / `logout` / `ssh` / `fetch` only. There is no arbitrary TCP dial.

## Layout

| Path | Role |
| --- | --- |
| `schema/` | Worker RPC v1 and dialTcp JSON schemas |
| `internal/wsframe` | RFC 6455 encode/decode/handshake (host Go tests) |
| `internal/tcpbridge` | Single-conn dial/read/write/close |
| `internal/ipnmachine` | NeedsLogin → Running → logout mapping |
| `js/` | Worker RPC, fake backend, WS assembler |
| `poc/` | Tiny page for manual Chrome |
| `patches` applied at build | `scripts/patch-wasm-js.py` |
| `docs/` | W0 baseline, evidence, Flutter handoff |

## Security rails

- One live TCP connection, one destination host:port from the user, no port scan
- Logs never include auth URLs, auth keys, node keys, full NetMap, or H.264 bytes
- Default state is session-scoped (`sessionStorage` / in-memory in Worker)
- Core WASM must not load from an unpinned CDN
- Suggested CSP sketch: `worker-src 'self'; script-src 'self'; connect-src 'self' https://controlplane.tailscale.com https://*.tailscale.com wss://*.tailscale.com` — exact DERP set is still unmeasured

## Status

The 2026-08-30 baseline is recorded in `docs/EVIDENCE.md`. The current joint investigation is recorded in `../doc/tailscale-integration/evidence/2026-09-24-browser-wasm.md`; distinguish those results from the older fake-backend checks.

`js/tcp-websocket.js` adapts the real Worker TCP RPC to a WebSocket byte stream, including split reads and an upgrade response immediately followed by a game message. `js/live-probe.ts` is a diagnostic client using the existing recorded-video decoder and authentication helpers under `web/`; it is not a second product client. It sends authentication, stream settings, acknowledgments and keyframe requests, but no gameplay input.

Run its focused framing regression with `node js/tcp-websocket_test.js`. To bundle the live probe from the repository root after installing `web/` dependencies:

```sh
node --input-type=module <<'JS'
import { build } from './web/node_modules/vite/dist/node/index.js';
await build({ configFile: false, build: {
  lib: { entry: 'web-tailscale/js/live-probe.ts', formats: ['es'], fileName: () => 'live-probe.js' },
  outDir: 'web-tailscale/dist', emptyOutDir: false, minify: false,
} });
JS
```

The probe exports `probe(rpc, options, progress)` for the local diagnostic page's `window.__rpc`. Use a selected peer's address and a test server first. A real game probe authenticates as a controller and must only start when another client is not connected. Real credentials and authorization URLs must not be included in saved evidence. The `authenticate` callback permits local test tooling to sign a challenge without exposing the stored password to the page.

The POC defaults to an in-memory ephemeral node. Flutter requests persistIdentity: true, using IndexedDB, a single-owner browser lock and a non-ephemeral node. Cancel stops the Worker without deleting identity; logout clears saved identity. Flutter integration status and its remaining real-login acceptance are recorded in the execution log.
