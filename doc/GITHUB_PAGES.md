# GitHub Pages browser client

MonkeyCraft's production browser client is built from `flutter/monkeycraft/` and shares Flutter UI and business logic with the mobile apps. The historical TypeScript client under `web/` is retained for reference; its provenance tooling is reused by the Flutter build.

The Pages entry is https://use-ai-for-mc.github.io/monkeycraft/. Use a reachable HTTPS/WSS endpoint for your Minecraft computer, such as its Tailscale Serve address. Pages does not relay game traffic or embed a Tailscale node; the device uses its existing network or system Tailscale connection. Only one controlling client can connect at a time.

## Build and publish

The manually dispatched `Pages` workflow pins the Flutter SDK and GitHub Actions, resolves the dependency lockfile, runs static analysis, and builds with base path `/monkeycraft/`. It records source, toolchain and artifact hashes in `build-provenance.json`. Publishing is disabled by default and is allowed only from `master` when the `publish` input is enabled.

For a local candidate, from `flutter/monkeycraft/`:

```sh
FLUTTER_BIN=/absolute/path/to/flutter \
  MONKEYCRAFT_PAGES_PROVENANCE=0 \
  bash tool/build_web_release.sh /monkeycraft/ build/pages
```

This command builds files locally; it does not deploy. The workflow generates provenance from the checked-out source commit when publishing. The build also writes to `build/web`; use base `/` when preparing browser assets embedded in a Mod.

## Release confirmation

The browser's shared functionality has already been accepted. Deployment confirmation is limited to opening the public entry and connecting to a game. Repeated sound, countdown, background, and per-Minecraft-version tests are not required for this release. Existing test sources are retained but the Pages publishing workflow does not rerun the full functional suites.

Normal mobile Safari pages do not guarantee timely alerts while locked or closed. Native mobile clients remain supported products.
