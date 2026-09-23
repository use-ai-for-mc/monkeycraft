# W0 — 现有 Flutter Web 直连基线（只读）

记录于 2026-08-30。本轮 **没有修改** `stream_proxy.dart` / `command_sender.dart` 或任何 Flutter 产品文件。

## 构建与发布

| 项 | 现状 |
| --- | --- |
| 本地 | `cd flutter/monkeycraft && flutter run -d chrome` |
| CI | `.github/workflows/build.yml` job `flutter`：`flutter analyze`、`flutter test`、`flutter build web --release --base-href /monkeycraft/` |
| Pages | `.github/workflows/pages.yml`：同样的 web release 构建，部署 GitHub Pages |
| 浏览器 E2E | **没有** Playwright/Chrome 产品测试 |
| 本轮补测 | 只加在 `web-tailscale/`（隔离），不改共享 transport |

## 连接与认证

`StreamProxy.start`（`flutter/monkeycraft/lib/stream/stream_proxy.dart`）：

1. `stop()` 清旧连接
2. `VideoRelay.start()`（Web 上为 no-op）
3. `_parseServerUrl`：
   - `https://` → `wss://`，`http://` → `ws://`
   - 已是 `ws://` / `wss://` 原样
   - `host:port` → `ws://host:port`
   - 无端口 → `wss://host`
4. `WebSocketChannel.connect(wsUrl)`，`ready` 超时默认 **5s**
5. `CommandSender.attach(channel)`
6. 文本 `HELLO` HMAC-SHA256，认证超时默认 **5s**
7. 认证前丢弃二进制

`CommandSender` 直接 `ws.sink.add(jsonEncode(command))`，未认证时 `trySendCommand` 返回 false。

## 文本 / 二进制

- 文本：JSON 控制面（AUTH、CLIENT_STATUS、INPUT、CHAT、…）
- 二进制：
  - `0x4D 0x43` 后 4 字节宽高 + H.264 AU
  - `0x4D 0x4D` map data
- Web 视频：`WebH264Decoder`，WebCodecs `avc1.420028`，`DecodeQueuePolicy` maxQueue=3
- `VideoRelay` MPEG-TS TCP 在 Web 上是 no-op；帧走 `accessUnits`

## 可见性与重连

- `page_visibility_web.dart`：`document.hidden`
- `web_frame_keep_alive_web.dart`：失焦但未 hidden 时每秒 `scheduleWarmUpFrame`；**不能**对抗后台冻结
- `SessionController`：最多 **3** 次重连，延迟 `1 << retryCount` 秒（1s/2s/4s，约 7s）
- HTTPS 页不能连明文 `ws://`

## 本轮未采集（仍是假设）

分辨率 / FPS / RTT / 码率 / 解码丢帧的 **数字基线** 需要真实 Mod + Chrome 会话。没有把 LAN 直连视频标成已测。

现有 Dart 测试覆盖 `CommandSender` mock 通道和 session/decode policy，**没有** `StreamProxy` 对 `WebSocketChannel.connect` 的集成测试。这是手机 agent M0 的范围。
