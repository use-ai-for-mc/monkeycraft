# Using MonkeyCraft over Tailscale

MonkeyCraft's WebSocket server is plaintext and authenticated by an HMAC
challenge-response. That's fine on a LAN but uncomfortable on the open
internet. [Tailscale](https://tailscale.com/) gives you a private,
end-to-end-encrypted (WireGuard) overlay network between your PC and your
phone, so the phone can reach the mod from anywhere as if it were on the
same LAN — without port-forwarding and without exposing the WebSocket
publicly.

This guide walks through pairing today, with the existing mod build.
There is no Tailscale-specific code in the mod yet; the trick is that
Tailscale gives every device a stable `100.x.y.z` address in the
[CGNAT range](https://tailscale.com/kb/1015/100.x-addresses) that the
mod's existing `Allow Connections From = Anywhere` setting will accept.

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

Install from the link above, sign in, and confirm the daemon is running.
You should see a `100.x.y.z` address listed:

```bash
# macOS / Linux
tailscale ip -4

# Windows (PowerShell)
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
```

Note this address — call it `<PC_TS_IP>`. It is stable across reboots and
network changes.

### 2. Install Tailscale on the phone

Install the app, sign in to the same account, and toggle the VPN on. Once
the phone shows it is connected to the tailnet, it can reach
`<PC_TS_IP>`.

### 3. (No special configuration needed)

MonkeyCraft treats Tailscale's `100.64.0.0/10` range as part of your
local network. The default `Allow Connections From` value
(`Only Local Network`) accepts these addresses alongside the standard
RFC1918 ranges (`10/8`, `172.16/12`, `192.168/16`), so no config change
is required.

If you previously flipped `Allow Connections From` to `Anywhere` solely
to enable Tailscale, you can move it back to `Only Local Network` to
tighten things up.

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
`100.x.y.z:9600`. The name survives Tailscale IP changes (rare, but
possible if you re-install).

Check your device's name with:

```bash
tailscale status
```

The first column is the device name; the FQDN is the device name plus
your tailnet's DNS suffix.

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

This is overkill for a personal tailnet but worth knowing if you share it.

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
  layer. As long as you have not also forwarded port 9600 on your home
  router, the only path to the WS port from outside your LAN is through
  the tailnet — which is the point. **Do not combine `Anywhere` with a
  router port-forward**; that re-introduces the public-internet exposure
  Tailscale was supposed to remove.
- **Password strength.** Treat the QR-code password as a long-lived
  secret. Rotate it via `/monkey config` if you ever share a screenshot
  of your title screen.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| App says "Connection refused" | Mod's WS server isn't running | `/monkey start`, or enable Start Server at Launch |
| App says "Connection not allowed from this address" | You're on an older mod version that doesn't yet treat `100.64/10` as local | Update the mod, or set `Allow Connections From` to `Anywhere` as a workaround |
| App times out | Phone's Tailscale VPN is off | Toggle Tailscale on in the phone app |
| App times out only on cellular | macOS / Windows firewall blocking inbound on the Tailscale interface | Allow Java / Minecraft inbound; on macOS, accept the firewall prompt the first time the WS server starts |
| Tailscale IP works on LAN, not on cellular | Your tailnet relays may be slow / Tailscale not yet connected on phone | Open the Tailscale app on the phone, confirm "Connected" before opening MonkeyCraft |
| `100.x.y.z` differs from what `tailscale ip -4` shows | You're looking at the wrong device | Run `tailscale status` to confirm device name → IP mapping |

To sanity-check the path independently of MonkeyCraft, from the phone's
Tailscale app or a ping tool, ping `<PC_TS_IP>` while the phone's
Tailscale VPN is on. Then try a generic TCP probe to `9600` from any
machine on the tailnet:

```bash
# from another tailnet device
nc -vz <PC_TS_IP> 9600
```

If the TCP probe succeeds but the app fails, the problem is the mod's
allowlist or the password, not the network.

---

## Heuristic, not assertion

The `100.64.0.0/10` range is RFC 6598 *Shared Address Space* — reserved
for Carrier-Grade NAT (CGNAT). Tailscale uses it for tailnet addresses,
but it's also used by some ISPs for CGNAT. The mod treats the whole
range as local-equivalent on the assumption that nothing on a typical
home LAN sits in `100.64/10` except Tailscale. If you're behind ISP
CGNAT *and* you port-forward 9600 on your router, CGNAT peers could in
principle reach the WS port — your HMAC handshake remains the actual
gate. Don't combine port-forwarding with `Anywhere` if you can avoid
it.
