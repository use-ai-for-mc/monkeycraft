# Test prompt — remote-server-selection regression

Manual regression-test prompt for the remote-server-selection feature
(picker + per-join `acceptResourcePack` toggle) on each supported
Minecraft variant. The feature shipped on `master` in mod **1.4.0**
(PRs #2 and #4), validated end-to-end on iOS and Android against 1.19,
1.21.11, and 26.1. Re-run this when bumping the mod version, picking up
new MC builds, or touching the join / picker flow.

## Profile state when this doc was last written (2026-05-28)

All three variants are deployed to **PrismLauncher** (the build-and-deploy
scripts target it directly — no manual copy needed):

| Variant   | PrismLauncher instance | Mod jar in `<instance>/.minecraft/mods/` | ModMenu in profile |
| --------- | ---------------------- | ----------------------------------------- | ------------------ |
| `1.19`    | `Fabric 1.19`          | `monkeycraft-1.4.0-1.19.jar`              | enabled            |
| `1.21.11` | `ImagineFun`           | `monkeycraft-1.4.0-1.21.11.jar`           | enabled            |
| `26.1`    | `26.1`                 | `monkeycraft-1.4.0-26.1.jar`              | **disabled**       |

Passwords live in each instance's `config/monkeycraft.json` (`password`
field) — read them from there at test time rather than copying them
around. Legacy `autoLaunch` / `startServerAtLaunch` keys are migrated
transparently on first load to the new `serverAutoStart` enum.

## How to use

1. Open a fresh Claude Code session in `/Users/cusgadmin/if-local/monkeycraft`.
2. Pick one variant (`1.19`, `1.21.11`, or `26.1`) — do **not** test
   more than one at a time; they all bind port 9600.
3. Paste the prompt below, replacing every `<VERSION>` placeholder.

## Prompt

```
I'm regression-testing the remote-server-selection feature (picker +
acceptResourcePack toggle, mod 1.4.0) on Minecraft <VERSION>.

Working dir: /Users/cusgadmin/if-local/monkeycraft

What I want you to do:

1. Sanity-check we're on master at a tip that includes both PR #2 (the
   serverAutoStart enum rename) and PR #4 (the acceptResourcePack
   toggle). If not, stop and tell me.

2. Build + deploy the <VERSION> jar:
     cd mods/<VERSION>
     ./build-and-deploy.sh
   This deploys to the PrismLauncher instance listed in the doc's
   profile-state table and atomically replaces any existing monkeycraft
   jar there. Confirm the target mods/ folder now contains
   monkeycraft-1.4.0-<VERSION>.jar and no stale monkeycraft-*.jar from
   older versions — if any 1.3.x jars remain, rm them.

3. Read the profile's config/monkeycraft.json. Confirm one of:
     - "serverAutoStart": "AT_TITLE_SCREEN"  (new key, already set), OR
     - legacy "startServerAtLaunch": true    (will be auto-migrated on
       first launch of the 1.4.0 jar; you can leave it for the migration
       to handle, or pre-edit to the new key).
   The path is:
     ~/Library/Application Support/PrismLauncher/instances/<INSTANCE>/.minecraft/config/monkeycraft.json
   (where <INSTANCE> is "Fabric 1.19" / "ImagineFun" / "26.1" per the
   profile-state table). Show me the relevant lines. Preserve the
   existing password — I'll use it to pair.

   Note for 26.1: ModMenu is disabled in that profile, so the only way
   to read/edit the config is via the JSON file.

4. Tell me to launch the right PrismLauncher instance for <VERSION>.
   While I do that, confirm in parallel:
     - lsof -nP -iTCP:9600 -sTCP:LISTEN  (server is up after MC starts)
     - mcp__mcdev-mcp__mc_screenshot     (title screen shows QR + IP)
   If a stale MC from a previous variant is still holding 9600, ask me
   to quit it first.

5. After first launch with 1.4.0, peek at the JSON again. If legacy
   keys were present, confirm they've been removed and "serverAutoStart"
   was written. (One-time migration; harmless if not present.)

6. Once I confirm I see the QR/IP, walk me through the 5-step test plan:
   a. Title-screen QR/IP visible (covered in step 4).
   b. App connects from title screen → lands on Server Picker (NOT
      stream). Decision logic:
        flutter/monkeycraft/lib/auth/login_screen.dart
      WORLD_STATE phase = MENU → picker; IN_WORLD → stream.
   c. Picker shows the "Accept server resource pack" toggle at the top
      of the body, default ON. Toggling it should NOT trigger a join.
   d. With toggle ON, pick/type a server → JOIN_SERVER → world loads
      with NO "Accept Resource Pack?" prompt → app auto-transitions to
      the stream screen as phase flips to IN_WORLD.
   e. In-game Esc → Save and Quit to Title (or Disconnect) → app drops
      back to the picker, WebSocket stays connected (no re-auth).
      Decision logic: stream_screen.dart's WORLD_STATE handler.
   f. (Optional) Back at the picker, flip the toggle OFF, join again →
      the standard MC "Accept Resource Pack?" prompt appears as before.

After each test step, ask me to report what I saw. Don't move to the
next step until I confirm.

Important gotchas from the original validation runs:
- Restarting MC is mandatory after touching mods/ or config — the
  running JVM keeps the old jar/config in memory.
- "Server not listening on 9600" + "no QR on title screen" together =
  serverAutoStart is OFF (or still on the legacy false default).
  Set "serverAutoStart": "AT_TITLE_SCREEN" in the JSON.
- Phone must be on the same Wi-Fi (allowConnectionsFrom networkScope =
  LOCAL_NETWORK) or share Tailscale with the desktop (tailscaleAccess =
  ALWAYS or IF_DETECTED).
- Only one MC instance at a time across the 3 variants — they all bind
  port 9600.
```

## Notes

- This is now a **regression** prompt — the feature is on master and has
  shipped. Use it after merging mod changes that touch
  `WorldJoinHandler`, `ServerPickerScreen`, the `StreamProxy` join path,
  or any of the title-screen / `WORLD_STATE` lifecycle hooks.
- The legacy `autoLaunch` / `startServerAtLaunch` migration is one-time
  and harmless; you can mix old and new keys in the JSON and the new
  one wins (see `ModConfig.migrateLegacyAutoStartFlags`).
- The `acceptResourcePack` field on `JOIN_SERVER` is optional — older
  apps that don't send it fall back to MC's default `PROMPT` behaviour,
  so this is backward compatible with pre-1.4.0 app builds.
- For App Store / Play Store release builds, bump `pubspec.yaml`
  `version:` alongside the mod version (it's intentionally tracked
  separately so server-only mod releases don't force an app resubmission).
