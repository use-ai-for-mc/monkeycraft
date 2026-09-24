# GitHub Pages browser client

MonkeyCraft's production browser client is built from `flutter/monkeycraft/` and shares Flutter UI and business logic with the mobile apps. The historical TypeScript client under `web/` is retained for reference; its provenance tooling is reused by the Flutter build.

The Pages entry is https://use-ai-for-mc.github.io/monkeycraft/. Select **Connect with Tailscale** to sign into your own account, choose the game computer and pair without typing its MonkeyCraft password. This uses a browser Tailscale node; Funnel and a public game endpoint are unnecessary. The separate address option accepts a reachable HTTPS/WSS endpoint. Only one controlling client can connect at a time.

Published on 2026-09-24 from source `224dc9aa5c479be396bb913880b7e05334d52864` via [Pages run 35946801848](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/35946801848). The public [build provenance](https://use-ai-for-mc.github.io/monkeycraft/build-provenance.json) records the clean source, toolchain and file hashes. Twelve entry/runtime files were downloaded and matched against that manifest. Entry scripts use content hashes in their URLs so an updated page does not reuse the old program from HTTP cache. For the first transition from a previously cached page, open https://use-ai-for-mc.github.io/monkeycraft/?v=224dc9a.

## Browser Tailscale integration

The published browser client uses the same Flutter connection screen, Tailscale sheet, device picker, pairing and game screen as the apps. It adds **Connect with Tailscale** above the existing address connection. The experimental POC/debug page is never shipped. Real Chrome testing has verified account authorization, the actual 26.2 game stream through the PC embedded node, and a page refresh that restores both Tailscale identity and game authentication without another pairing. The concurrent credential-write defect found during that test is fixed. The user has also confirmed real iPhone Safari game video and a refresh that restores the game automatically after Tailscale startup. The public Chrome entry and WASM startup have also been verified. Tailscale identities belong to each site origin: a localhost test login does not transfer to Pages.

Users sign in to their own Tailscale account and select the computer running MonkeyCraft. Traffic passes through the browser's Tailscale node to that computer; Funnel or a public game endpoint is unnecessary for this path. Game password authentication/pairing still applies. The browser must support secure contexts, WebAssembly, Workers, IndexedDB and Web Locks. Existing address connections remain available.

The node identity is saved in IndexedDB for this site. Cancel closes the connection but retains sign-in; explicit Sign out removes the local identity. A second tab cannot run the same identity simultaneously. Clearing site data, private browsing, another origin, or a separately stored home-screen app can require signing in again. Remembered game credentials are separate from the Tailscale identity. The Remember option controls game credentials and automatic connection; Tailscale stays signed in until Sign out. A saved Tailscale computer is selected automatically on the next page launch after a successful remembered connection.

Pages builds include the pinned Go/WASM runtime and its license, hash-checked against VERSION.json, loaded only after selecting Tailscale. Builds with base `/` retain the existing smaller Mod bundle by default; set MONKEYCRAFT_WEB_TAILSCALE=1 explicitly for a standalone root-path browser build. The Pages workflow sets that flag even for a custom-domain root. No Mod or native app deployment is needed for this browser release.

## Saved connection

On first use, choose Tailscale and pair, or use the separate address form with a reachable game endpoint. A page served by the Mod defaults to that computer's address. An explicitly changed, remembered target takes precedence. Once the address is known, it is shown as a summary with a Change button.

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

## Current iPhone Safari handoff

Open the versioned Pages link above in a normal Safari tab. If a saved address connection opens the game, use Disconnect first. Select Connect with Tailscale, then Open Tailscale login; sign into the same Tailscale account as the computer and approve the new browser device. Return to MonkeyCraft, choose the computer named monkeycraft, keeping port 9600. Without a saved game credential the client automatically requests pairing; the user sends the displayed code so the computer can confirm. Keep Remember enabled. After the game appears, one refresh checks recovery. No sound, countdown or old-platform retests are required. The user has completed pairing, video and one refresh recovery on real iPhone Safari. No extra test matrix is required. Browser Tailscale retains the game screen through temporary reconnect failures while foregrounded; actual authentication failures still return to login. Backgrounding keeps the existing node rather than deliberately restarting it. This is separate from a full page reload or an OS-discarded tab, which requires startup again.
