# MonkeyCraft WebSocket protocol (26.2 server, as implemented)

This is the contract the browser client is written against. It is derived from the
26.2 mod source, not from the Flutter client. Line references point at
`mods/26.2/src/main/java/com/chenweikeng/monkeycraft/`. When this document and the
Java code disagree, the Java code wins; fix the document.

The protocol is frozen for the web rewrite. Nothing here may change without a
capability token (see `AGENTS.md`, "Adding New Features").

## 1. Transport

### 1.1 One port, HTTP and WebSocket

The mod listens on one TCP port, default `9600`, scanning `9600..9700` if the
preferred port is taken (`server/WebSocketServerHandler.java` `startServerWithPortRange`).
Every accepted socket goes through `server/HttpOrWebSocketChannel.java`:

- Headers are read until `\r\n\r\n` (8192-byte cap; overflow gives `400`).
- If any header is `Upgrade: websocket` (case-insensitive), the bytes are replayed
  into Java-WebSocket. **The request path is ignored.** `ws://host:port/` and
  `ws://host:port/anything` both work.
- Otherwise the request is served as HTTP and the socket is closed. Only `GET` and
  `HEAD` are accepted; anything else is `405`. No keep-alive.
- HTTP responses carry exactly `Content-Type`, `Content-Length`, `Connection: close`.
  **No cache headers, no CORS headers.**

Static assets come from the jar classpath under `/web/` (`server/WebAssetServer.java`):

- `/` and empty path resolve to `index.html`. If the jar has no `web/index.html`, a
  placeholder page is served.
- Any other missing path is `404`. **There is no SPA fallback.** Use hash routing.
- Paths containing `..`, `\`, or NUL are `400`. Query strings are stripped.
- MIME by extension: html, js, mjs, css, json, wasm, png, jpg/jpeg, gif, svg, ico,
  woff, woff2, ttf, otf, map, bin; everything else `application/octet-stream`.

### 1.2 Access control

- The HTTP asset path has **no** IP check.
- On WebSocket open, the remote address is checked against the configured
  `NetworkScope` (`utils/NetworkUtils.java` `isConnectionAllowed`): loopback always
  allowed; `LOCAL_NETWORK` (default) additionally allows link-local, site-local,
  RFC1918 and CGNAT `100.64.0.0/10`; `ANYONE` allows all; `THIS_COMPUTER` allows
  loopback only. A rejected client receives
  `{"type":"ERROR","message":"Connection not allowed from this address"}` then close.
- **No `Origin` check.** Same-origin is not required at the protocol level.

### 1.3 Single session

Many sockets may be open, but only one is the authenticated session
(`authenticatedSession`). When a second socket authenticates, the previous one
receives `{"type":"AUTH_RESPONSE","success":false,"message":"Logged in from another location"}`
and is closed. Any non-`AUTH` message from a socket that is not the session gets
`{"type":"ERROR","message":"Unauthorized"}` and close.

### 1.4 Liveness

The server never sends application heartbeats and never times out an idle
authenticated client at the application layer. Java-WebSocket's default
`connectionLostTimeout` (60 s) applies: a WebSocket Ping is sent every 60 s and a
socket whose last Pong is older than 90 s is closed with `1006`. Browsers answer
Pings automatically, but a throttled background tab can miss the window.

Client-side heartbeat (compatible baseline, matches the Flutter client): every 1 s,
if no server message for 3 s send `{"type":"HEARTBEAT"}`; if no `HEARTBEAT_ACK`
within 5 s, treat the connection as lost and close. Pause while the page is hidden.

## 2. Handshake

All client-to-server messages are **text frames containing a JSON object with a
`type` field**. Binary frames from the client are discarded. Malformed JSON gets
`{"type":"ERROR","message":"Invalid JSON"}`.

### 2.1 HELLO (server, immediately on open)

```json
{"type":"HELLO","salt":"<base64, 16 random bytes>","pairing":true,"keyId":"<16 chars base64url>"}
```

- `salt` is per connection and is reused for the whole handshake, including after
  pairing.
- `pairing` is `NetworkUtils.isPairingAllowed(remoteAddress)`: loopback, link-local,
  site-local, RFC1918, or IPv4 CGNAT `100.64.0.0/10`. **Hostnames play no role**;
  `*.ts.net` is not special. Tailscale IPv6 ULA peers are *not* eligible, IPv4
  `100.x` peers are.
- `keyId` identifies the current password. It rotates when the password changes.
  Cache `keyId -> password` and discard the cached password when `keyId` changes.

### 2.2 AUTH, HMAC mode (client)

```json
{"type":"AUTH","salt":"<clientSalt>","signature":"<base64>","protocolVersion":2,"deviceName":"<optional>"}
```

- `signature = base64(HMAC-SHA256(key = utf8(password), msg = utf8(serverSalt + clientSalt)))`.
  Standard Base64 with padding. Server salt first, no separator.
- `clientSalt` is any string; use 16 random bytes in Base64.
- `deviceName` is kept up to 48 printable characters and shown in game.
  `deviceModel` is accepted and ignored.
- Failure replies, each followed by close:
  `AUTH_RESPONSE {success:false, message:"Missing salt or signature"}`,
  `AUTH_RESPONSE {success:false, message:"Invalid signature"}`.

### 2.3 AUTH, PAIR mode (client)

```json
{"type":"AUTH","mode":"PAIR","protocolVersion":2,"deviceName":"<optional>"}
```

- Not eligible: `PAIR_FAILED {message:"Pairing is only allowed on this computer or LAN"}` + close.
- Otherwise `PAIR_WAITING {code:"ABCD2345", ttlMs:180000}`. Code alphabet is
  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 8 chars, displayed as `ABCD-2345`. The user
  accepts in game or runs `/monkey accept ABCD-2345`.
- Accept: `PAIR_OK {password:"<long-term password>"}`. **This does not authenticate.**
  The client must now send a normal HMAC `AUTH` using the returned password and the
  `salt` from the original `HELLO`.
- Decline: `PAIR_FAILED {message:"Pairing declined on the computer"}` + close.
- Replaced by another pairing attempt: `PAIR_FAILED {message:"Replaced by another pairing attempt"}` + close.
- Expiry after 180 s is **not** signalled. Run a client-side timer.

### 2.4 AUTH_OK (server)

```json
{"type":"AUTH_OK","signature":"<base64>","protocolVersion":2,
 "capabilities":["PLAYER_LIST","DATA_SAVER","PAIRING","KEY_ID"],
 "versionWarning":"<only when client protocolVersion != 2>"}
```

- `signature = base64(HMAC-SHA256(password, clientSalt + serverSalt))`. Note the
  **reversed** order. Verify it.
- `AUTH_RESPONSE {success:true}` is never sent by 26.2 but older servers may; accept it.
- Immediately after `AUTH_OK` the server sends, in order: `HIBERNATION_STATUS`
  (only if hibernating), `TIMED_STATUS` (only if a timed notification is pending),
  `SCREEN_STATE`, then `WORLD_STATE` one tick later.
- There is no server-side auth timeout. The Flutter client allows 4 minutes so a
  human can complete pairing.

## 3. Client to server messages

Handlers that touch game state run on the next client tick, so replies can arrive
out of order relative to each other.

| type | fields | effect / reply |
|---|---|---|
| `CLIENT_STATUS` | see 3.1 | configures video; always replies `SERVER_STATUS` |
| `INPUT` | `key` string, `pressed` bool | level-triggered key; see 3.2 |
| `LOOK_DELTA` | `yaw`, `pitch` floats, degrees | adds to rotation, pitch clamped ±90; replies `PLAYER_POSE` |
| `GET_PLAYER_POSE` | | replies `PLAYER_POSE` (nothing if no player) |
| `CLICK` | `button` int, 0 attack / 1 use | momentary press, auto-released after 2 ticks |
| `HOTBAR_SELECT` | `slot` int 0..8 | selects slot |
| `ACK` | | releases one pending video frame; see 5.2 |
| `REQUEST_KEYFRAME` | | forces IDR + resolution header, resets pending counter |
| `HEARTBEAT` | | replies `HEARTBEAT_ACK` |
| `PING` | | replies `SERVER_STATUS` |
| `RUN_COMMAND` | `command` string starting with `/` | runs, or `COMMAND_DENIED {command}` |
| `SEND_CHAT` | `message` string | sends chat; `/`-prefixed text is `CHAT_DENIED` |
| `SUBSCRIBE_CHAT` | | replies `CACHED_CHAT_MESSAGES`, enables `CHAT_MESSAGE` push |
| `UNSUBSCRIBE_CHAT` | | stops push; no reply |
| `ENTER_CHAT` / `EXIT_CHAT` | | legacy; do not use (see 3.5) |
| `SCREEN_CLICK` | `button` int, `normalizedX`, `normalizedY` doubles | GUI click; see 3.4 |
| `SCREEN_HOVER` | `normalizedX`, `normalizedY` | moves GUI cursor |
| `SCREEN_KEY` | `key` string, `pressed` bool | only `"ESCAPE"` is mapped |
| `SCREEN_MODIFIER` | `modifier` string, `active` bool | only `"SHIFT"`; sticky server flag |
| `SCREEN_TAP` | | **no-op on the server. Never send.** |
| `MAP_INTERACT` | `entityId` int | interacts (mounts); no reply |
| `LIST_SERVERS` | | replies `SERVER_LIST` |
| `JOIN_SERVER` | `address` string, `name` opt, `acceptResourcePack` opt bool | replies `JOIN_RESULT` |
| `LEAVE_WORLD` | | disconnects to title; `WORLD_STATE` follows |
| `GET_PLAYER_LIST` | | replies `PLAYER_LIST` |
| `GET_PLAYER_COUNT` | | replies `PLAYER_COUNT` |
| `INFO` | anything | no-op |

### 3.1 CLIENT_STATUS

```json
{"type":"CLIENT_STATUS","mode":"STREAMING","width":720,"height":1280,
 "colorMode":0,"fps":10,"dataSaver":false,"autoFaceMovement":false}
```

- `mode`: `"STREAMING"` (default), `"CHAT"`, `"MAP"`.
- **No video is sent until the first `CLIENT_STATUS`.**
- STREAMING: needs both `width` and `height`. `fps` clamped to `[1,20]`, default 10.
  `width`/`height` clamped to `[2,1920]` then rounded **down to even**.
  `colorMode`: 0 normal, 1 high-perf (12-bit), 2 retro (6-bit), 3 grayscale.
  `dataSaver`: GOP becomes `fps*4` instead of `fps`.
- The server rebuilds the encoder only when width/height/colorMode/fps/dataSaver
  changed, but **every** `CLIENT_STATUS` calls `resetBackpressure()`: the next
  frame is an IDR carrying the 6-byte resolution header.
- CHAT: stops video. MAP: like STREAMING but ignores hibernation; width/height optional.
- `autoFaceMovement` applies in every mode.
- Server defaults before the first status: 360×640, fps 10, colorMode 0.
- There is **no bitrate field**. Bandwidth levers are resolution, fps, colorMode, dataSaver.

### 3.2 INPUT keys

`W A S D SPACE SHIFT Q E F LEFT RIGHT UP DOWN`, uppercase, exact. `LEFT/RIGHT/UP/DOWN`
turn the camera at 5°/tick while held. Keys are level-triggered: **always send the
release**. The server releases everything only on disconnect and re-auth. Pressing any
of these while the in-game chat screen is open closes that screen first.

### 3.3 LOOK_DELTA units

`yaw`/`pitch` are degrees added to the current rotation. The Flutter client uses
0.12° per logical pixel of drag and flushes accumulated deltas every 16 ms, skipping
empty flushes.

### 3.4 Screen interaction coordinates

`normalizedX`/`normalizedY` are in `[0,1]` relative to the **crop rectangle the video
shows** (`utils/ScreenHelper.java` `getCropBoundsScreenCoords`), in GUI-scaled screen
coordinates. Container screens crop around the container with 16 px padding; book
screens around the 192×192 page; other screens the whole screen with 8 px padding.

Known inconsistency: for "letterboxed" screens (not container, not chat, not book,
e.g. the pause menu) the video is fit-with-black-bars while clicks are mapped with
scale-to-fill. Normalised coordinates taken from the displayed frame will be offset
on those screens. Verify on the pause menu before shipping; compensate by mapping
within the centred `min(w/W, h/H)` sub-rect if needed.

`SCREEN_CLICK` warps the real cursor and dispatches `mouseClicked` (or
`mouseReleased` when the cursor carries a stack, to finish drag-drop). `button` is
GLFW: 0 left, 1 right, 2 middle. `SCREEN_MODIFIER SHIFT` sets a sticky server flag
that is applied to later clicks and keys and is **not** reset on disconnect.

There is no text-entry path for GUIs (only `ESCAPE` is mapped).

### 3.5 Chat mode

Use `CLIENT_STATUS {mode:"CHAT"}` to pause video and `CLIENT_STATUS {mode:"STREAMING", ...}`
to resume. `ENTER_CHAT` also stops video but `EXIT_CHAT` does **not** resume it, so
the pair is not useful. Chat delivery is independent: `SUBSCRIBE_CHAT` returns the
last 100 messages and enables push in any mode.

## 4. Server to client JSON messages

| type | fields |
|---|---|
| `HELLO` | `salt`, `pairing`, `keyId` |
| `ERROR` | `message` |
| `PAIR_WAITING` | `code`, `ttlMs` |
| `PAIR_FAILED` | `message` |
| `PAIR_OK` | `password` |
| `AUTH_OK` | `signature`, `protocolVersion`, `capabilities[]`, `versionWarning?` |
| `AUTH_RESPONSE` | `success`, `message` |
| `SERVER_STATUS` | `videoState` `"ACTIVE"` or `"HIBERNATING"`, `message?`, `timedFireAtEpochMs` (number or explicit `null`), `timedTitle?`, `timedBody?`, `timedSound`, `timedCountDownText?` |
| `SCREEN_STATE` | `isOpen` bool |
| `WORLD_STATE` | `phase` `"MENU"`/`"CONNECTING"`/`"IN_WORLD"`, `serverName?`, `serverAddress?`, `singleplayer` |
| `NUDGE` | `title?`, `body?`, `sound` |
| `DISCONNECT` | `reason` (`"server_disconnect"`), followed by close |
| `HIBERNATION_STATUS` | `active` (always `true`), `message`; post-auth only |
| `TIMED_STATUS` | `fireAtEpochMs`, `title?`, `body?`, `sound`, `countDownText?`; post-auth only, **unprefixed** keys |
| `CACHED_CHAT_MESSAGES` | `messages[]` (≤100) |
| `CHAT_MESSAGE` | `sender`, `senderUuid?`, `segments[]`, `timestamp` ms |
| `CHAT_DENIED` | `reason` |
| `COMMAND_DENIED` | `command` |
| `HEARTBEAT_ACK` | |
| `PLAYER_POSE` | `yaw`, `pitch` |
| `PLAYER_LIST` | `count`, `players[]` (tab-list order) |
| `PLAYER_COUNT` | `count` |
| `SERVER_LIST` | `servers[]` of `{index, name, address}` |
| `JOIN_RESULT` | `ok`, `error?` |
| `CHAT_MODE_STARTED` / `CHAT_MODE_ENDED` | legacy |

Traps:

- Timed notification keys are unprefixed in the one-shot `TIMED_STATUS` and
  `timed`-prefixed in every later `SERVER_STATUS`. Cancellation is a `SERVER_STATUS`
  with `"timedFireAtEpochMs": null`.
- Un-hibernation is only ever `SERVER_STATUS {videoState:"ACTIVE"}`.
- `SERVER_STATUS.message` is present only while hibernating with a non-empty message.

Chat segment shape (`server/ChatSegment.java`):

```json
{"text":"...","color":"#RRGGBB","bold":true,"italic":true,"underlined":true,
 "strikethrough":true,"obfuscated":true,
 "clickEvent":{"action":"open_url|run_command|suggest_command|copy_to_clipboard","value":"..."},
 "hoverEvent":{"action":"show_text","value":[segments, one level deep]}}
```

Style booleans are present only when true. Legacy `§` codes are already parsed
server-side. System messages have `sender:"System"` and no `senderUuid`.

## 5. Binary frames (server to client)

Disambiguate on the first bytes:

| prefix | payload |
|---|---|
| `4D 43` (`MC`) | 6-byte header + H.264 access unit |
| `4D 4D` (`MM`), length ≥ 24 | map data frame (MAP mode) |
| `00 00 00 01` | H.264 access unit, no header |

### 5.1 Video

- One WebSocket binary message is exactly one Annex-B access unit with 4-byte
  start codes. Produced by jcodec 0.2.5 `H264Encoder`.
- Header, present only on an IDR **and** only while `sendResolutionHeader` is armed:
  `4D 43 | width u16 BE | height u16 BE`, then the raw AU. The flag is re-armed by
  `resetBackpressure()` (every `CLIENT_STATUS`, `REQUEST_KEYFRAME`, GUI open/close)
  and by every encoder recreation.
- Every IDR AU is `SPS(7) PPS(8) IDR(5)`. Parameter sets are in-band; WebCodecs can
  run Annex-B with no `description`. P frames are a single slice NAL (1).
- Baseline profile 66, level 40. Codec string `avc1.42<constraint>28`; read the three
  bytes after the SPS NAL header rather than hard-coding. No B-frames, no CABAC.
- Colour: the SPS advertises full-range YUV420J but samples are BT.601 limited range.
  Expect slightly low contrast; optional client-side compensation.
- **In non-dataSaver mode the server sets `needsIdr` after every P frame**
  (`server/H264Streamer.java` `encodeAndSend`), so the steady-state stream alternates
  IDR, P, IDR, P and roughly half the frames carry the 6-byte header plus fresh
  SPS/PPS. The client must handle the header cheaply on any frame. With `dataSaver`
  the encoder persists and the GOP is honoured.

### 5.2 ACK gating

- `MAX_PENDING_FRAMES = 1`; a frame is dropped when `pendingFrames > 1`, so at most
  two frames are in flight. Each `{"type":"ACK"}` decrements.
- **Send `ACK` immediately on receipt of every video message**, before decoding. Do
  not ACK `MM` map frames. Missing ACKs stall the stream after two frames.
- Every dropped frame (backpressure, encoder busy) sets `needsIdr`, so recovery is
  always a full IDR with header. `REQUEST_KEYFRAME` also zeroes the pending counter
  and therefore un-sticks a stream whose ACKs were lost.

### 5.3 Resolution change

Send `CLIENT_STATUS` with the new size. The old encoder is closed (up to 2 s), a new
one built, and the next frame is an IDR with the new dimensions in the header and
new SPS/PPS. The client should reconfigure its decoder when the SPS bytes change and
size the canvas from decoded frame dimensions, not from the requested size.

### 5.4 Frame rate

Capture is gated by wall-clock `1000/fps` ms evaluated once per client tick (20 Hz),
so the ceiling is 20 fps and intermediate values are uneven. The server reports no
statistics; measure locally.

### 5.5 Map data frame (`MapDataHandler.java`), big-endian

```
0   u8   'M'
1   u8   'M'
2   f64  playerX
10  f64  playerZ
18  f32  playerYaw (degrees)
22  i16  uuidLen
24  utf8 playerUuid
    i16  entityCount
    repeat:
      u8   type   0 vehicle, 1 player, 2 saddled mob
      f64  x
      f64  z
      i32  entityId   (use in MAP_INTERACT)
      i16  nameLen
      utf8 name
```

Sent every 5 ticks (~4 Hz) in MAP mode only, entities within ±8 blocks. In MAP mode
the server locks the player to face north and pitch 0 so WASD is cardinal.

## 6. Close codes

- `1001 "Monkeycraft shutting down"`: game closing.
- `1000` no reason: IP rejected, unauthorized, auth failure, session takeover, pairing failure.
- `DISCONNECT {reason:"server_disconnect"}` then `1000`: user pressed disconnect in game.
- `1006`: transport liveness (no Pong for 90 s).
