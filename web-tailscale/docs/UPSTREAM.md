# 上游能力核对（固定 v1.102.3）

Commit `53a0d659afa51835dd7a9283873cca44261454f8`（tag v1.102.3，2026-08-20）。
许可证 BSD-3-Clause，副本在 `third_party/tailscale/LICENSE`（fetch 后写入）。

## 公开 JS API（wasm_js.d.ts）

`newIPN(config)` → `{ run, login, logout, ssh, fetch }`

`IPNNetMapNode` 字段：`name`, `addresses`, `machineKey`, `nodeKey`。

**没有** `dialTcp`、任意 TCP、可注入的浏览器 WebSocket transport。
因此不能把 `@tailscale/connect` 当 WebSocket SDK。本 POC 在固定源码上打最窄补丁。

## 内部确实存在的 TCP

`wasm_js.go` 里 SSH 走 `dialer.UserDial(ctx, "tcp", host:22)`，`fetch` 用同一 Dialer。
userspace netstack 的 `NetstackDialTCP` 已接好。缺的是暴露给 JS 的窄桥。

## Node ID

`tailcfg.Node` 有：

- `ID NodeID` — 控制面整数，同一 login-server 内不复用（文档 2025-01-06）
- `StableID StableNodeID` — 字符串形式，**跨 JS Number.MAX_SAFE_INTEGER 更安全**，应用该把它当持久设备键

官方 wasm NetMap JSON **未** 输出这两项。补丁增加 `nodeId` / `stableId`。
**禁止** 把 `name` 或可轮换 `nodeKey` 当永久 ID。

## DERP

`derp/derphttp/websocket.go`：`GOOS=js` 时 `websocket.Dial`，子协议 `derp`。
浏览器路径 **只能** DERP-over-WSS，没有 TUN、没有 UDP 直连。

## 存储

tsconnect README：开发态用 `sessionStorage`，关标签即丢。本 POC 默认同样；不植入 auth key。

## Tailcat

只作免账号配对的**备选对照**，未混入主线控制面。
