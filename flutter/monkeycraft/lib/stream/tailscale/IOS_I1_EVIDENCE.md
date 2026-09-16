# iOS I1/I2 spike evidence (Flutter-owned)

Date: 2026-08-30

## Pinned versions

| Item | Value |
| --- | --- |
| libtailscale commit | `80771313ac4127973677c993889fe215abcf1fbd` |
| go.mod | `go 1.25.5`, `tailscale.com v1.94.1` |
| Local Go | `go1.26.3 darwin/arm64` |
| Xcode | 26.6 (17F113) |
| App `IPHONEOS_DEPLOYMENT_TARGET` | 16.6 (unchanged) |
| Podfile | iOS 15.5 (unchanged) |
| License | BSD-3-Clause (`ios/third_party/libtailscale/LICENSE`) |

Build with `ios/third_party/libtailscale/build.sh ios` (device) or `ios-sim`.
SHA-256 is written next to each `.a` and into `out/MANIFEST.json`.

## Why not TailscaleKit.framework in Runner

Official `swift/TailscaleKit.xcodeproj` sets `IPHONEOS_DEPLOYMENT_TARGET = 18.1`
and Swift 6. MonkeyCraft must not silently raise its 16.6 floor. The C archive
clangwrap uses `-mios-version-min=12.0`, so linking `libtailscale_ios.a` keeps
the existing app target.

`diagnostics()` still reports `kitIosMinimum=18.1` so I4 can revisit embedding
the Swift package once product agrees to raise the floor.

## Target uses

| Recipe | Artifact | Use |
| --- | --- | --- |
| `make c-archive-ios` / `build.sh ios` | `libtailscale_ios.a` | device and App Store |
| `make c-archive-ios-sim` / `build.sh ios-sim` | `libtailscale_ios_sim.a` | simulator only |
| `swift/make ios-fat` | `TailscaleKit.xcframework` | local mixed-slice convenience; **not** App Store |

Xcode links `libtailscale_ios.a` for `sdk=iphoneos*` and `libtailscale_ios_sim.a`
for `sdk=iphonesimulator*`. `MONKEYCRAFT_HAS_LIBTAILSCALE=1` is set only when the
matching archive exists.

## Login path (no auth key)

1. `tailscale_new` + `tailscale_set_dir` (App Support, excluded from backup) + `tailscale_start`.
2. Poll `tailscale_status_json` (in-memory LocalAPI; survives iOS loopback reclaim, upstream #20060).
3. `BackendState=NeedsLogin` + `AuthURL` → `ASWebAuthenticationSession` (ephemeral) / `UIApplication.open`.
4. Completion is **node state** (`Running` / `NeedsMachineAuth`), not a URL callback.
5. Optional `POST /localapi/v0/login-interactive` via `tailscale_loopback`.
6. Stable identity is `Status.Self.ID` (`Tailcfg.StableNodeID`). Name/IP are display-only.
7. No reusable auth key is compiled in or stored.

Logs redact `https://…` and `tskey-…`. Flutter events expose `authUrlHost` only.

## Export compliance (human review required)

Current `Info.plist` / `doc/APP_ENCRYPTION_DOCUMENTATION.md` still say
`ITSAppUsesNonExemptEncryption=false`. Embedding WireGuard/Tailscale **must not**
keep that answer. Items for a person to re-evaluate before any TestFlight/App
Store upload:

- App Store Connect export-compliance questionnaire
- whether an annual self-classification report is required
- privacy policy language that a MonkeyCraft-owned tailnet node is created
- third-party BSD-3-Clause notice in the app licenses screen

This file is not legal advice.

## What this round did not do

- No `StreamProxy` Tailscale loopback bridge (I3)
- No product login UI mode switcher
- No Android product connection code
Verified on this machine (2026-08-30):

| Artifact | Arch | SHA-256 | Size |
| --- | --- | --- | --- |
| `libtailscale_ios.a` | arm64 device | `ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9` | 27119712 |
| `libtailscale_ios_sim.a` | x86_64+arm64 sim | `41c1b3c0c3f81ccc580989d5d45bc90d94374fd12cfbdd5d5e1dd5ade01f462e` | 52911024 |

Symbols present in the device archive: `tailscale_new`, `tailscale_start`,
`tailscale_status_json`, `tailscale_loopback`, `tailscale_dial`, `tailscale_close`.

`flutter build ios --simulator --no-codesign` succeeds both without the archive
(`diagnostics.available=false`) and with `MONKEYCRAFT_HAS_LIBTAILSCALE` after
`build.sh ios-sim`. Device/archive codesign and on-device dyld were not run
here (no attached phone in this session).
