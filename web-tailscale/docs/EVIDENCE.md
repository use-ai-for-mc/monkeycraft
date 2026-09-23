# 阶段证据（Web / WASM POC）

这是2026-08-30的历史基线。2026-09-24真实联调的结果另见[当前证据](../../doc/tailscale-integration/evidence/2026-09-24-browser-wasm.md)，以下“未测”仅描述当时状态。

日期：2026-08-30。主机：macOS darwin/arm64，Chrome 151.0.7922.174，本机 Go go1.26.3；WASM 构建使用 GOTOOLCHAIN=auto 的 go1.26.6。

## 已自动验证

| 项 | 证据 |
| --- | --- |
| RFC 6455 掩码/分片/续帧/控制帧/长度/非法 opcode/UTF-8/close | `go test ./internal/wsframe` |
| race | `go test -race ./internal/...` |
| fuzz ReadFrame | `go test -fuzz=FuzzReadFrame -fuzztime=5s` |
| 握手 Accept-Key（RFC 样例） | `TestAcceptKeyRFC` |
| TCP echo + 大二进制 WS 帧 | `./internal/tcpbridge`、`TestWebSocketOverEchoTCP` |
| RPC v1 校验（版本/方法/大小/dial） | `./internal/rpcschema` |
| 登录状态机 NeedsLogin→Running→logout 清 NetMap | `./internal/ipnmachine` |
| 日志脱敏 | `./internal/redact` |
| JS RPC + fake login/popup/cancel/echo/conn limit | `js/rpc_test.js` |
| JS 帧组装 | `js/ws-client_test.js` |
| Chrome headless fake 流程 | `tests/browser/chrome-headless.mjs` |
| 公开 API 无任意 TCP dial | 阅读 v1.102.3 `wasm_js.d.ts` |
| 内部 UserDial TCP 存在 | 阅读 `wasm_js.go` SSH/fetch |
| StableNodeID 存在于 tailcfg，未出现在官方 JS NetMap | 阅读 `tailcfg.Node` + `jsNetMapNode` |
| 浏览器 DERP 为 WSS 子协议 `derp` | 阅读 `derp/derphttp/websocket.go` `GOOS=js` |

## 已真机 / 本机验证

| 项 | 结果 |
| --- | --- |
| 本机 Chrome 二进制存在 | `/Applications/Google Chrome.app` 151.0.7922.174 |
| Chrome headless dump-dom | runner.html → `BROWSER_TESTS_OK`（fake backend） |
| Safari / Firefox / iOS | **未测**，不得宣称支持 |
| 真实交互式 Tailscale 登录 | **未测**（需要用户浏览器批准） |
| 两节点 DERP TCP echo | **未测** |
| WASM `GOOS=js GOARCH=wasm` | **已本机构建** v1.102.3 + 窄补丁，Go go1.26.6（GOTOOLCHAIN=auto）。`dist/main.wasm` 36 764 111 B / gzip 8 336 377 B，sha256 `65c3ba7321d0ad9363faa44f6e374a9bf8133093706b2d46c70b9cca6703731a`。`wasm_exec.js` 来自同一 toolchain，sha256 `0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14`。产物 gitignore，需 `./scripts/build-wasm.sh` 重建。 |

## 仍是假设 / 不得宣称

| 项 | 原因 |
| --- | --- |
| 实时 H.264 在 DERP-only 下可用 | 无 RTT/吞吐/内存/Worker CPU 样本 |
| GitHub Pages `application/wasm` + Brotli | Pages 头不可控；仅本地测试服务器设了 MIME |
| Go 1.26.6（上游 go.mod） | 本机 1.26.3；构建时 GOTOOLCHAIN=auto 可能拉取 1.26.6 |
| 与桌面 helper / 四棵 Mod 的 E2E | G2 门槛，本轮禁止 |
| Tailcat | 未实现，刻意不混入 |

## DERP-only 能力表

| 能力 | 状态 |
| --- | --- |
| 浏览器 TUN | 无 |
| UDP 直连 / disco STUN | 无（js 无 UDP） |
| DERP-over-WSS | 源码路径存在，**性能未测** |
| 任意 TCP via 公开 npm API | **无** |
| 任意 TCP via 本补丁 dialTcp | 设计完成；真实 tailnet **未测** |
| SOCKS / Funnel / exit / 扫描 | **明确不做** |
