# Using MonkeyCraft over Tailscale

MonkeyCraft's WebSocket server is plaintext and authenticated by an HMAC
challenge-response. That's fine on a LAN but uncomfortable on the open
internet. [Tailscale](https://tailscale.com/) gives you a private,
end-to-end-encrypted (WireGuard) overlay network between your PC and your
phone, so the phone can reach the mod from anywhere as if it were on the
same LAN — without port-forwarding and without exposing the WebSocket
publicly.

The mod ships with native Tailscale awareness: it detects a local
Tailscale daemon and treats Tailscale's `100.x.y.z`
[CGNAT-range addresses](https://tailscale.com/kb/1015/100.x-addresses)
as part of your local network. In practice that means you install
Tailscale, type the `100.x.y.z` address into the app, and connect —
no special `/monkey config` changes required.

---

## Prerequisites

| What | Where to get it |
| ---- | --------------- |
| Tailscale on your PC | [tailscale.com/download](https://tailscale.com/download) (Windows, macOS, Linux) |
| Tailscale on your phone | App Store / Play Store |
| Same tailnet | Sign both devices in to the same account (or the same shared tailnet) |

You do **not** need a paid Tailscale plan for personal use — the free
tier covers up to 100 devices.

---

## Setup

### 1. Install Tailscale on the PC

Install from the link above, sign in, and look up your PC's tailnet
address from the Tailscale menubar icon (macOS) or system tray icon
(Windows / Linux GUI). It's a `100.x.y.z` number — call it `<PC_TS_IP>`.
The address is stable across reboots and network changes.

MonkeyCraft labels addresses in this range as `(Tailscale)` — or
`(possibly Tailscale)` if local detection couldn't confirm Tailscale is
running — in the `/monkey` IP listing and on the title-screen overlay,
so you can pick the right one.

### 2. Install Tailscale on the phone

Install the app, sign in to the same account, and toggle the VPN on.
Once the phone shows it is connected to the tailnet, it can reach
`<PC_TS_IP>`.

### 3. Connection allowlist

MonkeyCraft's `Allow Connections From` setting understands Tailscale:

- **`Only Local Network`** (default) accepts Tailscale addresses
  (`100.64.0.0/10`) when the mod can detect a running Tailscale daemon
  locally. For most users this just works, no config change required.
- **`Local + 100.64/10`** accepts any `100.64.0.0/10` source regardless
  of detection. Use this if auto-detection misses your Tailscale install
  (e.g. unusual macOS App Store sandboxing), or you're connecting from a
  host you're confident is on the tailnet.
- **`Anywhere`** accepts any source. Avoid unless you understand the
  exposure.

The config screen (`/monkey config`) shows whether Tailscale was
detected, so you don't have to guess. When the mod rejects a `100.64/10`
connection because detection failed and the setting is `Only Local
Network`, it sends an in-game chat message suggesting the `Local +
100.64/10` switch.

### 4. Start the WebSocket server

Either:

- run `/monkey start` in-game, or
- enable **Start Server at Launch** in `/monkey config` so the server is
  up at the title screen (recommended; it lets the phone drive
  server-selection and joining without you ever opening Minecraft on the
  desktop).

### 5. Connect from the app

In the MonkeyCraft phone app's login screen:

- **Host**: `<PC_TS_IP>` (the `100.x.y.z` you noted in step 1)
- **Port**: `9600` (or whatever your mod config shows)
- **Password**: scan the QR shown in the corner of Minecraft, or paste
  it manually.

You should be paired and streaming.

---

## Optional: use MagicDNS instead of the raw IP

Tailscale's [MagicDNS](https://tailscale.com/kb/1081/magicdns) lets you
address devices by name rather than by IP — e.g. `my-pc.tail1234.ts.net`.
Enable it once in the Tailscale admin console (DNS → Enable MagicDNS),
and you can type `my-pc:9600` into the app instead of
`100.x.y.z:9600`. The name survives the rare case where you reinstall
Tailscale and get a different IP.

---

## Optional: lock it down further with ACLs

By default any device on your tailnet can reach `<PC_TS_IP>:9600`. If
your tailnet has multiple users or shared devices, you can use
[Tailscale ACLs](https://tailscale.com/kb/1018/acls) to allow only your
phone to reach the port. Example policy fragment:

```json
{
  "acls": [
    {
      "action": "accept",
      "src":    ["user:you@example.com:phone"],
      "dst":    ["user:you@example.com:9600"]
    }
  ]
}
```

This is overkill for a personal tailnet but worth knowing if you share
it.

---

## Security notes

- **Transport encryption.** Tailscale wraps the WebSocket traffic in
  WireGuard, so the plain-WS protocol becomes irrelevant on the wire.
- **Auth still matters.** Tailscale gives you the network, not
  authorization. The mod's HMAC challenge-response (per
  [WebSocketServerHandler.java](../mods/26.1/src/main/java/com/chenweikeng/monkeycraft/server/WebSocketServerHandler.java))
  still gates who can pair, regardless of how they reached the port.
- **`Anywhere` is broader than Tailscale.** With that setting selected,
  *any* source the mod's socket can reach will be accepted at the IP
  layer. **Do not combine `Anywhere` with a router port-forward**; that
  re-introduces the public-internet exposure Tailscale was supposed to
  remove. For Tailscale-only access, `Only Local Network` (with
  detection) or `Local + 100.64/10` is preferred.
- **Password strength.** Treat the QR-code password as a long-lived
  secret. Rotate it via `/monkey config` if you ever share a screenshot
  of your title screen.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| App says "Connection refused" | Mod's WS server isn't running | `/monkey start`, or enable Start Server at Launch |
| App says "Connection not allowed from this address" | Mod couldn't auto-detect Tailscale locally (rare; e.g. macOS App Store sandboxing) | Set `Allow Connections From` to `Local + 100.64/10` in `/monkey config`. You'll also see an in-game chat message suggesting this. |
| App times out | Phone's Tailscale VPN is off | Toggle Tailscale on in the phone app |
| App times out only on cellular | macOS / Windows firewall blocking inbound on the Tailscale interface | Allow Java / Minecraft inbound; on macOS, accept the firewall prompt the first time the WS server starts |
| Tailscale IP works on LAN, not on cellular | Your tailnet relays may be slow / Tailscale not yet connected on phone | Open the Tailscale app on the phone, confirm "Connected" before opening MonkeyCraft |

To sanity-check the path independently of MonkeyCraft, ping
`<PC_TS_IP>` from another tailnet device while the phone's Tailscale VPN
is on, then try a TCP probe to `9600`:

```bash
# from another tailnet device
nc -vz <PC_TS_IP> 9600
```

If the TCP probe succeeds but the app fails, the problem is the mod's
allowlist or the password, not the network.

---

## How the detection works

The mod checks for a running Tailscale daemon by enumerating local
network interfaces:

- **Linux** — interface literally named `tailscale0`.
- **Windows** — Wintun adapter whose display name contains "Tailscale".
- **macOS** — any `utun*` interface holding an IPv4 address in
  `100.64.0.0/10`. (The interface number varies per boot, so the IP is
  the only reliable signal on macOS.)

It's not a definitive check — on a personal device a `100.64/10` address
almost always comes from Tailscale (the range is RFC 6598 CGNAT shared
space, also used by some ISPs for carrier NAT). Under the default
`Only Local Network` setting, the mod accepts `100.64/10` traffic only
when the local detection passes, so a host behind ISP CGNAT without
Tailscale won't accidentally allow CGNAT-internet traffic.

For a stricter check (resolving the exact Tailscale-assigned IPs by
querying `tailscaled`), see Tailscale's CLI: `tailscale status --json`.
The mod intentionally avoids the CLI dependency in favor of the
interface-enumeration heuristic.
