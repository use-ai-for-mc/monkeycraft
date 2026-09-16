# P0/P1 阶段 0–1 证据：桌面 helper

记录日期：2026-08-30  
主机：macOS Darwin 25.6.0 arm64（Apple Silicon）  
工作范围：`native/tailscale-helper/` 独立 helper。未修改 Flutter、Web WASM、四棵 Mod 产品代码。

## 固定版本

| 项 | 值 | 证据级别 |
| --- | --- | --- |
| Tailscale module | `tailscale.com v1.102.3` | 已自动验证（go.mod/go.sum） |
| 上游许可证 | BSD-3-Clause；见 `native/tailscale-helper/LICENSE.tailscale` | 已自动验证（上游 LICENSE 文本） |
| Go | `go1.26.6`（模块要求；本机 Homebrew go1.26.3 通过 GOTOOLCHAIN 拉取） | 已自动验证 |
| Helper | `0.1.0-p1` protocolVersion=1 | 已自动验证 |
| darwin-arm64 SHA-256 | 见本机 `native/tailscale-helper/dist/darwin-arm64/*.sha256`（不入库） | 已真机验证构建 |

升级必须单独 PR，禁止跟浮动 `latest`。

## 未经验证、开场已列出的假设

1. ~~`WatchIPNBus` + `Notify.BrowseToURL` 能否给出交互登录 URL，而不解析 `UserLogf`。~~ **已真机验证（macOS arm64）。**
2. 持久 state 重启后无需再登录。 **仍是假设**（需要完成一次浏览器授权后再重启 helper）。
3. helper listener 经真实 tailnet 转发到 127.0.0.1 WebSocket/H.264。 **仍是假设**（本轮只有 loopback fake/TCP echo）。
4. Windows x64 / Linux 可运行。 **仅 compile-only**；无真实机器证据，不得宣称支持。
5. Java-WebSocket 能否只绑 loopback。 **仍是假设**；本轮未接入 Minecraft。
6. 无系统 Tailscale App 时的防火墙/Gatekeeper。 **仍是假设**。

## 已自动验证

- Go unit：protocol golden、未知字段拒绝、target 必须 `127.0.0.1`、脱敏、state lock、fake backend 状态机。
- Race：`protocol` / `redact` / `lockfile` / `forward` / `engine` / `backend`。
- 转发：双向 TCP echo、半关闭、连接上限、慢消费者不 panic。
- Helper process：`-fake` 下 ready → status → shutdown 有界退出；`-version` 输出。
- Java harness：Java 17.0.19 / 21.0.11 / 25.0.2 启动 fake helper、收发 JSON Lines、shutdown 与 stdin EOF 后进程退出；stderr 无 auth URL/auth key。
- 交叉编译产物类型：darwin-arm64 Mach-O arm64、darwin-amd64 Mach-O x86_64、linux-amd64 ELF、windows-amd64 PE32+。
- stdout 只出 JSON；stderr 脱敏后不含 `login.tailscale.com/a/<token>`。

## 已真机验证（macOS arm64）

- 真实 `tsnet.Server` 启动，`LocalClient.WatchIPNBus(NotifyInitialState|NotifyInitialStatus)` 产生 `state=needsLogin`。
- 随后 `event=authRequired` 携带结构化 `authUrl`（https login.tailscale.com）。**不是**解析 UserLogf。
- 本轮未在浏览器完成授权，因此没有：持久恢复、两节点 TCP echo、direct vs DERP。

一次性操作（若要继续 P1 真实两节点）：在系统浏览器打开 helper 给出的登录 URL，批准设备后重新跑 smoke；不要把完整 URL 写入 git/CI artifact。

## 明确不做 / 未启用

SOCKS、Funnel、exit node、子网路由、任意目标、控制端口、reusable auth key。

## 架构结论（本轮）

选用 `tsnet.Server`（非 libtailscale C ABI）。登录 URL 路径已证明可用。无阻塞级架构失败，无需切 libtailscale。
