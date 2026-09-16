# I2/I3 remaining (device)

Done without a phone:

- Login sheet + peer list from `statusJSON` `Peer` map
- Persist last `nodeId` in SharedPreferences
- Loopback bridge with node whitelist, loopback bind, single client, idle timeout
- Dart still connects with `DirectWebSocketTransport` to `ws://127.0.0.1:<port>`

Still needs a phone:

1. Two-device interactive login + restart restore
2. Device dyld of `libtailscale_ios.a` and TestFlight archive
3. Real Mod HMAC / H.264 over the bridge
4. Wi-Fi/cellular/background

# Previous leftover

I2 leftover after this spike:

1. Wire `TailscaleEmbeddedClient` into a real login affordance (still no silent
   host fallback). Keep LAN/system Tailscale as the default connect path.
2. Persist last `nodeId` (not IP / node key) in existing credential storage.
3. Two-device interactive login + restart restore on a test tailnet.
4. Peer list from `statusJSON` `Peer` map; HMAC still confirms the game target.

I3 loopback bridge:

1. Native `dial(nodeId, port)` via `tailscale_dial`.
2. Loopback TCP listener on `127.0.0.1` random port, one client, idle timeout.
3. Return `ws://127.0.0.1:<port>` to Dart; `DirectWebSocketTransportFactory`
   connects. Do not rewrite WebSocket frames on the method channel.
4. Map bridge drop to connection-lost, not auth failure.
5. Prove any handshake token via WebSocket headers before calling it a control.

Do not start I3 until I1 archives sign and load on a device.
