# Test prompt — remote-server-selection on 1.19 and 26.1

Pre-built test prompt for verifying the remote-server-selection feature
(branch `feature/remote-server-selection`, commit `144ef00`, mod `1.3.1`)
on the two variants that still need a manual run after 1.21.11 passed.

## Profile state when this doc was written (2026-05-20)

| Variant | ModrinthApp profile               | Old jar to replace             | Password in config  | ModMenu in profile |
| ------- | --------------------------------- | ------------------------------ | ------------------- | ------------------ |
| 1.19    | `Fabric 1.19`                     | `monkeycraft-1.2.3-1.19.jar`   | `YGq8Ma5fMZdv`      | enabled            |
| 26.1    | `Fabric 26.1`                     | `monkeycraft-1.2.3.jar`        | `ForAppleBetaReview`| **disabled**       |

The per-version `mods/<ver>/build-and-deploy.sh` already targets these
ModrinthApp profiles, so no manual copy is needed.

## How to use

1. Open a fresh Claude Code session in `/Users/cusgadmin/if-local/monkeycraft`.
2. Pick one variant (`1.19` or `26.1`) — do **not** test both at once;
   they conflict on port 9600.
3. Paste the prompt below, replacing both `<VERSION>` placeholders.

## Prompt

```
I'm testing the remote-server-selection feature (branch
feature/remote-server-selection, commit 144ef00, mod 1.3.1) on Minecraft
<VERSION>. It's already been validated on 1.21.11; I want to repeat the
same test on the <VERSION> variant.

Working dir: /Users/cusgadmin/if-local/monkeycraft

What I want you to do:

1. Sanity-check the branch is feature/remote-server-selection at commit
   144ef00 (or later on that branch). If not, stop and tell me.

2. Build + deploy the <VERSION> jar:
     cd mods/<VERSION>
     ./build-and-deploy.sh
   This deploys to the ModrinthApp "Fabric <VERSION>" profile and
   atomically replaces any existing monkeycraft jar there. Confirm the
   target mods/ folder now contains monkeycraft-1.3.1-<VERSION>.jar and
   no stale monkeycraft-*.jar from older versions.

3. Edit the profile config to set startServerAtLaunch: true. The file is:
     ~/Library/Application Support/ModrinthApp/profiles/Fabric <VERSION>/config/monkeycraft.json
   Insert "startServerAtLaunch": true after the "autoLaunch" line. This
   defaulted to false bit us last time — the WS server stayed silent at
   the title screen, the QR didn't render, and the app couldn't connect.
   Show me the diff. Preserve the existing password — I'll use it to pair.

4. Tell me to launch the "Fabric <VERSION>" profile in ModrinthApp.
   While I do that, confirm in parallel:
     - lsof -nP -iTCP:9600 -sTCP:LISTEN  (server is up after MC starts)
     - mcp__mcdev-mcp__mc_screenshot     (title screen shows QR + IP)
   For 26.1 specifically: ModMenu is disabled in that profile, so the
   config must be edited via the JSON file (not via in-game UI).

5. Once I confirm I see the QR/IP, walk me through the 4-step test plan:
   a. Title-screen QR/IP visible (covered in step 4)
   b. App connects from title screen → lands on Server Picker (NOT stream)
      Decision logic: flutter/monkeycraft/lib/auth/login_screen.dart:129
      WORLD_STATE phase = MENU → picker; IN_WORLD → stream.
   c. Pick/type a server → JOIN_SERVER → world loads → app auto-transitions
      to the stream screen as phase flips to IN_WORLD.
   d. In-game Esc → Save and Quit to Title (or Disconnect) → app drops back
      to the picker, WebSocket stays connected (no re-auth).
      Decision logic: stream_screen.dart:394.

After each test step, ask me to report what I saw. Don't move to the next
step until I confirm.

Important gotchas from the 1.21.11 run:
- Restarting MC is mandatory after touching mods/ or config — the running
  JVM keeps the old jar/config in memory.
- "Server not listening on 9600" + "no QR on title screen" together = the
  startServerAtLaunch flag is still false. Recheck the JSON.
- Phone must be on the same Wi-Fi (allowConnectionsFrom=ONLY_LOCAL_NETWORK).
```

## Notes

- The `1.19` profile currently has `autoLaunch: false` (the `1.21.11`
  ImagineFun profile had `true`). After the prompt sets
  `startServerAtLaunch: true`, the server starts at launch regardless,
  so leaving `autoLaunch` alone is fine.
- If you re-enable ModMenu in the `26.1` profile before testing, the
  in-game config UI becomes available again and step 3 can be done
  from the title-screen Mods menu instead of editing JSON.
