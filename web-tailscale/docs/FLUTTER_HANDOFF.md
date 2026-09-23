# 下一轮：等 M0 合入后的 Flutter 接入清单

2026-09-24补充：正式Flutter现在已有`lib/stream/transport/connection_transport.dart`中的`TransportFactory`/`ConnectionTransport`，以及`lib/stream/tailscale/tailscale_models.dart`中的`TailscaleClient`、设备和租约模型。无需另建独立网页UI。后续可新增Web实现替换`tailscale_embedded_web_disabled.dart`的条件导出，将`js/tcp-websocket.js`的消息流封装为WebSocketChannel，继续复用StreamProxy和TailscaleLoginSheet。本轮只做原型真实联调，未修改该条件导出，也未把WASM纳入Pages构建。下面保留原阶段建议，M0不再是当前阻塞。

手机 agent 是 `ConnectionTransport` / `StreamProxy` / `CommandSender` 的首轮 owner。**本轮未改这些文件。**

M0 合入后，Web 下一轮（W5）建议：

1. 增加 `TailscaleWebTransport`（仅 `kIsWeb`），实现与 Direct adapter 相同的：`ready`、inbound text/binary、`send`、`close`、超时。
2. Transport 只跟 Worker RPC 说话，不把 TCP 或 WS 分帧泄漏给 `StreamProxy`。
3. HMAC / CommandSender / 三次重连 / 视频 AU 语义保持不变。
4. 功能 flag 默认关；失败时回到 `direct`。
5. Worker URL 必须相对 `base-href`（Pages 是 `/monkeycraft/`）。
6. 资产路径：`assets/tailscale/<content-hash>/main.wasm` + 同目录 `wasm_exec.js` + `bridge-worker.js`。
7. 登录 UI：用户手势里 **同步** `window.open`；blocked 时复制链接，不把 URL 打进 log。
8. 设备列表：只持久化 `stableId`，连接时再解析地址；不扫描端口。
9. 不要在 Dart 里用浏览器原生 `WebSocket` 去连 Tailnet IP。

本 POC 已提供：RPC schema、fake backend 契约、RFC 6455 可移植实现、dialTcp 形状。缺的是真实 DERP 视频证据和 M0 接口。
