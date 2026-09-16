# Web + tailnet plan (26.2)

## Goal

Browser is the long-term client. Phone and PC use **official Tailscale** (same tailnet). The mod does **not** embed Tailscale. The Flutter app is not maintained once the browser path works.

WebSocket over Tailscale is plain intranet: `100.x:9600` / MagicDNS, no Funnel. The browser still needs **Tailscale Serve** so the page is `https://*.ts.net` (WebCodecs requires a secure context). Bare `http://100.x` cannot decode video.

## Frozen

- Protocol: PAIR / AUTH HMAC / binary H.264 AU.
- Do not delete mod/app Tailscale until Safari + home-screen video is proven.
- App Review / Funnel is a separate path; ignore it while dropping the store app.
- 26.2 only until this lands.

## Done (in tree, this deploy)

- AUTH_OK sets `wizardDone`.
- Port 9600 multiplex: `GET` → HTML placeholder; `Upgrade: websocket` → existing game server. Client source IP unchanged.

## Remaining (order)

1. **Restart Minecraft** on `ImagineFun Add-Ons` so this jar loads.
2. **Local check:** `curl http://127.0.0.1:9600/` shows the placeholder; phone app still streams over WS.
3. **Serve (tailnet only, not Funnel):** pick a free HTTPS port (443→8081 and 8443 Funnel are taken). Example:
   `tailscale serve --bg --https=10800 http://127.0.0.1:9600`
   Phone on official Tailscale opens `https://mac.tail977122.ts.net:10800`.
4. **Secure-context check** in Safari/Chrome: `window.isSecureContext === true`, placeholder loads, Add to Home Screen on **iOS and Android**.
5. **Embed Flutter web** in the 26.2 jar; 9600 `GET` serves the real SPA; same origin `wss://`. Login defaults to current origin; `*.ts.net` uses Compatibility password (not PAIR).
6. **Video proof:** iPhone Safari + home screen, Android Chrome + home screen, ~20 FPS, background/lock resume. Compare to the native app on the same tailnet.
7. **Only then:** remove mod embedded Tailscale; shrink the wizard to “start server + show Serve URL if Tailscale is up”. Stop app releases.

## Not this cycle

- WASM Tailscale in the page.
- Funnel as the everyday URL.
- Porting the multiplex to 26.1 / 1.21.11 / 1.19.
- Software/WASM H.264 decode.
