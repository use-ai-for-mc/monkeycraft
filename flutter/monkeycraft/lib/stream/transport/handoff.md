# M0 ConnectionTransport handoff

`StreamProxy` no longer calls `WebSocketChannel.connect`. It takes a
`TransportFactory` (default `DirectWebSocketTransportFactory`) and uses the
returned `ConnectionTransport.channel` for HMAC, `CommandSender`, binary/text
frames, and close.

## Interface

- `TransportFactory.connect(Uri url, {Duration timeout})` must wait until the
  socket is ready or throw (including `TimeoutException`). Same 5s default as
  today.
- `ConnectionTransport.channel` is a `WebSocketChannel`. Dart still owns RFC 6455.
- `close` maps to `sink.close(normalClosure)` unless a code is supplied.

## URL parsing

`parseMonkeycraftServerUrl` is the frozen host/port/ws/wss/http/https rules.
Factories receive the already-parsed `Uri`.

## Adding a transport later

- iOS loopback: native plugin returns `ws://127.0.0.1:<port>`, then use
  `DirectWebSocketTransportFactory` against that URI. Do not rewrite frames on
  the platform channel.
- Web Worker: implement `TransportFactory` that yields a `WebSocketChannel`
  adapter. Do not special-case Worker inside `StreamProxy`.

Do not add unused Tailscale UI or a third default factory in this round.
Direct/LAN behavior must stay the default.
