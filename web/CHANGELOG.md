# Changelog

## M0 (2026-09-16)

- Scaffold: Vite + TypeScript + Preact, Vitest, Playwright, Biome, pnpm.
- `src/transport/endpoint.ts`: server address rules (same as the Flutter client).
- `src/protocol/auth.ts`: HMAC-SHA256 handshake via WebCrypto, mutual verification.
- `src/protocol/frames.ts`, `src/protocol/h264.ts`: binary demux, NAL scan, SPS codec string.
- `tools/probe.ts`, `tools/record-session.ts`: live probe and fixture recorder (Node, no deps).
- `index.html` unregisters the old Flutter service worker.
- CI job `web` in `.github/workflows/build.yml`.
