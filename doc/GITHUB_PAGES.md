# GitHub Pages browser client

MonkeyCraft's production browser client is built from `flutter/monkeycraft/` and shares Flutter UI and business logic with the mobile apps. The historical TypeScript client under `web/` is retained for reference; its provenance tooling is reused by the Flutter build.

The Pages entry is https://use-ai-for-mc.github.io/monkeycraft/. Use a reachable HTTPS/WSS endpoint for your Minecraft computer, such as its Tailscale Serve address. Pages does not relay game traffic or embed a Tailscale node; the device uses its existing network or system Tailscale connection. Only one controlling client can connect at a time.

## Saved connection

On first use, enter your game computer's address on Pages, then enter its password or pair. A page served by the Mod defaults to that computer's address. An explicitly changed, remembered target takes precedence. Once the address is known, it is shown as a summary with a Change button.

Leave “Remember and connect automatically” enabled to save the successful connection credentials in this browser. Future page launches automatically connect once, including launches from a home-screen shortcut when its browser storage contains the saved connection. A new or separately stored home-screen installation needs its own first connection. Credentials remain scoped to the game computer; changing the target clears the autofilled password.

An unavailable computer or rejected password returns to the connection form. Cancel stops the attempt; Disconnect stays on the form until the user connects again or reloads the page. Turning off Remember and connecting clears the saved credentials. Clearing site data also requires a new first connection. Native app startup behavior is unchanged.

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
