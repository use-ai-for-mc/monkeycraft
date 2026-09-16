# 内嵌 Tailscale 移植指南（给实现 agent）

这份文档教另一个项目把 MonkeyCraft 已经跑通的**内嵌 Tailscale**搬过去。目标产品形态：

- **桌面端**：macOS App + Windows App，本机有一个已有的同步/编码服务（HTTP、WebSocket、gRPC 都可以）。
- **手机端**：iOS App，需要从任意网络连上那台桌面，做 coding 数据同步。
- **用户不装** Tailscale 官方 App、不装 Go/Xcode/NDK、不占用系统 VPN 槽。
- 首次使用仍须在 **Tailscale 官方登录页**授权设备。

读完后先按第 8 节顺序实现。实现时打开本仓库对应源文件，按文件抄模式，不要凭印象重写网络栈。

相关但不要当“已实现说明书”的旧计划：

- `doc/TAILSCALE.md`：用户自己安装系统 Tailscale 的兼容路径（要保留，不是本方案）。
- `doc/tailscale-integration/README.md`：总纲与冻结决策。
- `doc/tailscale-integration/MOD_DESKTOP.md`：桌面 helper 方案。
- `doc/tailscale-integration/MOBILE.md`：iOS 内嵌方案。

本文件描述的是 **2026-09 仓库里已经落地的架构**，以代码为准。

---

## 1. 先记住的产品映射

MonkeyCraft 里“游戏 WebSocket + HMAC + H.264”对你的项目没有意义。要抄的是**网络嵌入方式**，不是业务协议。

| MonkeyCraft | 你的项目应替换成 |
| --- | --- |
| Minecraft Fabric Mod（Java） | macOS / Windows 桌面 App |
| `WebSocketServerHandler` 监听 `9600` | 本机 sync server（任意 TCP：HTTP / WS / gRPC） |
| HMAC 配对密码 | 你们已有的应用层鉴权（token、配对码、TLS client cert） |
| Flutter iOS App | iOS App（Swift 原生或 Flutter 都行） |
| `ws://127.0.0.1:<leasePort>` | `http(s)/ws/grpc://127.0.0.1:<leasePort>` |
| 只允许一台手机 | 按你们产品决定并发；helper 默认最多 8 条 TCP |

**不要改业务协议去迁就 Tailscale。** 两端都把 Tailscale 藏在 loopback 后面，现有 client/server 继续连 `127.0.0.1`。

---

## 2. 必须遵守的架构（不要改）

```text
iOS App 进程内
  libtailscale userspace node
       │  tailscale_dial(desktopTailnetIP:listenPort)
       ▼
  loopback TCP listener  127.0.0.1:<随机或首选端口>
       │  现有 iOS 网络库连这里
       ▼
  你们现有的 sync client（URLSession / grpc-swift / 自有 WS）


桌面 App 进程
  现有 sync server 只绑 127.0.0.1:<localPort>
       ▲
       │  普通 TCP 转发
  随包 helper（Go tsnet.Server）
       │  tsnet.Listen("tcp", ":listenPort")
       ▲
  tailnet 上的 100.x / MagicDNS
```

三条硬约束：

1. **userspace，不是系统 VPN。** 桌面用独立 Go helper（`tsnet`）；iOS 用进程内 `libtailscale` C archive。两边都不创建 TUN，不改系统路由，不占用 iOS Network Extension。
2. **只代理一个 TCP 端口。** 禁止 SOCKS、Funnel、subnet router、exit node、任意 host:port 指令、扫端口。
3. **Tailscale 只解决“到得了”。** 应用鉴权必须另外做。谁在 tailnet 上能拨号 ≠ 谁能读写你们的代码数据。

永久保留三种连接，失败时显式告诉用户，禁止静默改连未知主机：

| 模式 | 电脑 | 手机 | 用途 |
| --- | --- | --- | --- |
| `direct` | 本机 LAN 服务 | 填 IP / 扫码 | 同一 Wi-Fi 默认回退 |
| `systemTailscale` | 系统 Tailscale 或内嵌 helper | 系统 VPN 路由普通 TCP | 兼容已装官方 App 的用户 |
| `embeddedTailscale` | 内嵌 helper | iOS 内嵌节点 + loopback bridge | 目标路径 |

---

## 3. 为什么拆成“桌面 helper + 手机 C 库”

这是仓库里已经验证过的分工，移植时保持：

| 端 | 嵌入方式 | 原因 |
| --- | --- | --- |
| macOS / Windows 桌面 | **独立可执行文件** + stdin/stdout JSON Lines | Java/Swift/C#/Electron 都只需拉起子进程。崩溃隔离。不把 Go runtime 链进宿主。 |
| iOS | **进程内** `libtailscale` C API（`.a`） | App Store 不能随包再塞一个可执行 helper 当 VPN；C archive 最低版本可到 iOS 12 工具链，不强迫升到 TailscaleKit 的 18.1。 |

不要做：

- 桌面用 JNI / Swift 直接链 `libtailscale`（ABI、搜索路径、崩溃会拖死整个 App）。
- iOS 用系统 VPN / Packet Tunnel，去“复用官方 Tailscale App”。
- 给通用客户端塞 reusable auth key 或 OAuth client secret。
- 解析 `UserLogf` 人类日志拿登录 URL。必须走结构化 `BrowseToURL` / `AuthURL` / LocalAPI。

上游依据：

- [`tsnet`](https://github.com/tailscale/tailscale/tree/main/tsnet)：Go 程序内嵌独立节点，无需 root / daemon / 虚拟网卡。
- [`libtailscale`](https://github.com/tailscale/libtailscale)：C API `dial` / `listen` / `status_json` / `loopback`。
- 本仓桌面钉 `tailscale.com v1.102.3`；iOS 钉 libtailscale commit `80771313ac4127973677c993889fe215abcf1fbd`（其 go.mod 是 `tailscale.com v1.94.1`）。**两端版本可以不同，仍能进同一 tailnet。** 不要为了对齐去改 iOS pin。

---

## 4. 统一状态机与登录体验

各端只接收底层节点给出的短期登录 URL，用**系统浏览器**打开 Tailscale 官方页。宿主 UI 观察节点状态，直到 `running`、取消、超时或需要管理员审批。登录完成看节点状态，不依赖 OAuth redirect callback。

```text
unavailable → stopped → starting → needsLogin(authUrl)
                                      │
                                      ├─→ needsApproval
                                      └─→ running(nodeId, tailnetIp, peers)

starting/running → degraded → reconnecting
任意活动状态     → stopping → stopped
任意活动状态     → failed(code, recoverable)
```

设备选择只在本机节点 `running` 之后：

1. 从 LocalAPI / `status_json` 的 `Peer` 读可见设备，不要自建账号系统。
2. **持久化稳定 Node ID**（`Status.Self.ID` / peer `ID`），不要持久化 `100.x` 或显示名。下次连接用 ID 重新解析 IP。
3. 第一版列出 peers，让应用层握手确认目标。不要扫整个 tailnet 端口。
4. 三种操作必须分开：断开本次同步、忘记这台电脑、退出 Tailscale 并删除本地节点 state。

机密（完整登录 URL、节点私钥、auth key、应用密码）不得进普通日志、崩溃报告、分析、截图、UserDefaults。日志只留 host。

---

## 5. 桌面端：原样复用 Go helper

### 5.1 建议：直接拷 `native/tailscale-helper/`

这是已经用 fake backend、race、golden JSON、Java harness 冻过的 IPC。新项目最省事的做法是：

1. 把整个目录拷到新仓库，改 module path 和二进制名。
2. 改 `hostname()` 默认前缀（现在是 `monkeycraft-<osHostname>`）。
3. 保持协议 v1 字段不动，或升 `protocolVersion` 并同时改两端。
4. 用 `scripts/build.sh` 产出 `darwin-arm64`、`darwin-amd64`、`windows-amd64`。

入口：`native/tailscale-helper/cmd/monkeycraft-tailscale-helper/main.go`  
引擎：`native/tailscale-helper/internal/engine/engine.go`  
tsnet：`native/tailscale-helper/internal/backend/tsnet.go`  
转发：`native/tailscale-helper/internal/forward/forward.go`  
协议：`native/tailscale-helper/internal/protocol/protocol.go`  
schema：`native/tailscale-helper/internal/protocol/schema.v1.json`  
脱敏：`native/tailscale-helper/internal/redact/redact.go`  
单实例锁：`native/tailscale-helper/internal/lockfile/`

`tsnet.Server` 关键配置（必须保持）：

```go
&tsnet.Server{
    Dir:       dir,          // 持久节点身份，owner-only
    Hostname:  hostname,     // 手机 peer 列表里看到的名字
    Logf:      discard,      // 不要把内部日志当协议
    UserLogf:  redactedLogf,
    Ephemeral: false,        // 重启后不必重新授权
}
```

登录 URL 来自 `LocalClient.WatchIPNBus(..., NotifyInitialState|NotifyInitialStatus)` 的 `BrowseToURL`，缺 URL 时再 `StartLoginInteractive`。见 `tsnet.go` 的 `Watch()`。

### 5.2 IPC（stdin 命令 / stdout 事件 / stderr 诊断）

握手：父进程先发一条带 `protocolVersion=1` 和随机 `sessionNonce` 的 JSON（常用 `status`）。helper 记下 nonce，回 `ready`。之后每条消息必须带同一 nonce，不匹配则丢弃。

最小命令：`start` `status` `stop` `logout` `shutdown`  
最小事件：`ready` `stateChanged` `authRequired` `listening` `error` `stopped`

`start` 必填：

```json
{
  "protocolVersion": 1,
  "sessionNonce": "<32 hex>",
  "requestId": "1",
  "command": "start",
  "target": "127.0.0.1:<localSyncPort>",
  "listenPort": 9600,
  "stateDir": "<absolute owner-only dir>",
  "hostname": "yourapp-office-mac"
}
```

`target` **必须是** `127.0.0.1:<port>`，见 `ValidateTarget`。helper 在 tailnet 上 `Listen("tcp", ":listenPort")`，把字节流转到这个 loopback。它不接受远程指定其它目标。

黄金用例：`native/tailscale-helper/internal/protocol/testdata/golden/`。

### 5.3 宿主 App 要做的事（Swift / C# / Electron 对照 Java）

Java 参考实现按这个顺序读，然后用你们的语言重写同等状态机：

| 职责 | MonkeyCraft 文件 | 新项目怎么做 |
| --- | --- | --- |
| 选 OS/Arch | `mods/26.2/.../tailscale/HelperPlatform.java` | 映射 `darwin-arm64` / `darwin-amd64` / `windows-amd64`。不要靠一个 macOS universal 糊过去。 |
| 从包内解压 + SHA-256 sidecar | `NativeHelperExtractor.java` | 资源 hash ≠ sidecar 就原子重解压（tmp + rename）。macOS/Linux 设 executable。 |
| 拉起进程、握手、读 JSON Lines | `HelperProcess.java` | 随机 16 字节 hex nonce；stdout 行长上限 64KiB；stderr 脱敏且有字节上限；父退出要 `shutdown` → destroy → destroyForcibly，只杀**直接子进程**。 |
| 生命周期 | `HelperTailscaleService.java` | 本地 sync server **已经拿到真实端口**后再 `ensureRunning(actualPort)`。停服/退出先 stop helper。 |
| UI 快照 | `TailscaleSnapshot.java` + `MonkeyPanelScreen.java` `buildEmbeddedPath` | `needsLogin` 时用户点击才打开系统浏览器；同时提供“复制 URL”。不要让 helper 自己 `open` URL。 |
| 接到业务 server | `WebSocketServerHandler.java` 约 347 行 | server start 成功后 `ensureRunning`；server stop / App 退出调用 `stop()`。helper 失败不得拖垮本地 sync。 |

目录约定（改名即可，不要混进普通 settings JSON）：

```text
<appSupport>/yourapp/tailscale/state/     节点私钥与控制面状态，仅 helper 写，0o700
<appSupport>/yourapp/tailscale/helper/    解压的二进制 + .sha256 sidecar
<appSupport>/yourapp/tailscale/logs/      可选，已脱敏
```

macOS：`Application Support`，排除 Time Machine / iCloud。  
Windows：`LocalAppData`，尽量收紧 ACL。  
多个桌面实例禁止共享同一 `stateDir`；helper 用 `helper.lock` 拒绝第二个（`lockfile_unix.go` / `lockfile_windows.go`）。

### 5.4 桌面业务 server 必须绑 loopback

内嵌模式下，helper 从 tailnet 接进来再转到 `127.0.0.1`。宿主 server 若继续听 `0.0.0.0`，LAN 上任何人都能绕过 Tailscale。

正确默认：

- 内嵌模式：sync server bind `127.0.0.1:<port>`。
- LAN 模式：按原样听局域网。
- 两套可以并存，但不要把“内嵌 Tailscale”宣传成已经隔绝 LAN，除非 loopback-only 已实现。

MonkeyCraft 的 helper 在 tailnet 上固定听 `9600`（`HelperTailscaleService.LISTEN_PORT`），本地 WS 端口可以是范围内另一个数。手机只连 `9600`。你们也可以让 `listenPort == localPort`，但手机必须显示 helper 报告的最终端口。

### 5.5 构建与随包

```bash
cd native/tailscale-helper
./scripts/build.sh                          # 当前主机
GOOS=darwin GOARCH=arm64 ./scripts/build.sh
GOOS=darwin GOARCH=amd64 ./scripts/build.sh
GOOS=windows GOARCH=amd64 ./scripts/build.sh
```

`CGO_ENABLED=0`，产物自包含。每个 target 写 `manifest.json`（version、SHA-256、goos/goarch）。  
缺少对应二进制时 UI 显示“此平台暂不支持”，**禁止**提示用户去装 Go。

发布阻塞：macOS 签名 / notarization、Windows 代码签名。未签名时 Gatekeeper / SmartScreen 会拦首次启动 helper。

---

## 6. iOS 端：进程内节点 + loopback bridge

### 6.1 分层（按这个抄）

```text
UI：登录、选电脑、登出
  → TailscaleClient（方法频道）
    → TailscaleNodeManager（状态机、轮询 status_json、打开官方登录页）
      → LibtailscaleBackend（C API）
    → TailscaleLoopbackBridge（127.0.0.1 listener ↔ tailscale_dial fd）
  → 现有 sync client 连 bridge 返回的 loopback URL
```

必读文件：

| 文件 | 作用 |
| --- | --- |
| `flutter/monkeycraft/ios/Runner/TailscaleCBackend.swift` | C API：`tailscale_new/set_dir/set_hostname/start/status_json/dial/loopback/close`；登录用 LocalAPI `POST /localapi/v0/login-interactive` |
| `flutter/monkeycraft/ios/Runner/TailscaleNodeManaging.swift` | 状态机、1s 轮询、`AuthURL` 打开浏览器、state 目录排除备份 |
| `flutter/monkeycraft/ios/Runner/TailscaleLoopbackBridge.swift` | 单会话、只接受 `127.0.0.1`、按 nodeId 白名单 dial、idle 30s、半关闭 |
| `flutter/monkeycraft/ios/Runner/TailscaleTransportPlugin.swift` | MethodChannel `diagnostics/start/loginInteractive/listPeers/openBridge/closeBridge/...` |
| `flutter/monkeycraft/lib/stream/tailscale/tailscale_models.dart` | Dart 侧契约；纯 Swift 项目把同名字段做成 Codable |
| `flutter/monkeycraft/lib/stream/tailscale/tailscale_embedded_io.dart` | 频道封装；校验 bridge URL 必须以 `ws://127.0.0.1:` 开头 |
| `flutter/monkeycraft/lib/stream/connection_endpoint.dart` | `resolve()` = 确保 running → 关旧 lease → `openBridge` → 返回 loopback URL |
| `flutter/monkeycraft/lib/stream/tailscale/tailscale_login_sheet.dart` | 登录 / 等审批 / 选 peer / 登出删 state |
| `flutter/monkeycraft/ios/third_party/libtailscale/build.sh` | 固定 commit 编 device / sim 两套 `.a` |
| `flutter/monkeycraft/ios/third_party/libtailscale/VERSION.json` | 为什么用 C archive 而不是 TailscaleKit.framework |

### 6.2 供应链（先做这个，再写功能）

1. pin libtailscale commit，用 `build.sh` 分别编：
   - `ios` → `libtailscale_ios.a`（真机 / App Store，**不要** lipo 进 simulator slice）
   - `ios-sim` → `libtailscale_ios_sim.a`（仅模拟器，**永不**进 Archive）
2. 写 SHA-256 sidecar 和 `MANIFEST.json`。
3. Xcode：device SDK `-force_load libtailscale_ios.a -lresolv`；sim SDK 用另一份。用 compilation condition（本仓是 `MONKEYCRAFT_HAS_LIBTAILSCALE`）在缺库时变成 `unavailable`，不要链接失败。
4. Bridging header 按条件 `#import "tailscale.h"`。参考 `ios/Runner/Runner-Bridging-Header.h`、`TailscaleKitPin.h`。
5. **不要**把 `TailscaleKit.xcframework`（ios-fat）提交 App Store。官方 Kit 的 `IPHONEOS_DEPLOYMENT_TARGET=18.1`；C archive 的 clangwrap 是 `-mios-version-min=12.0`。本仓 App 仍是 16.6。

### 6.3 C API 启动顺序（照抄 `LibtailscaleBackend`）

```text
handle = tailscale_new()
tailscale_set_logfd(handle, -1)                  // 不要把 Go 日志打到 fd 1
tailscale_set_dir(handle, appSupport/YourAppTailscale)
tailscale_set_hostname(handle, "yourapp-ios")
tailscale_set_control_url(handle, "https://controlplane.tailscale.com")
tailscale_set_ephemeral(handle, 0)
tailscale_start(handle)
```

登录：

1. `tailscale_loopback` 拿到 `127.0.0.1:port` + LocalAPI key。
2. `POST http://127.0.0.1:port/localapi/v0/login-interactive`  
   Header：`Authorization: Basic base64("tsnet:" + key)`，`Sec-Tailscale: localapi`。
3. 轮询 `tailscale_status_json`。出现 `AuthURL` 就 `UIApplication.shared.open`。  
   `BackendState`：`NeedsLogin` / `NeedsMachineAuth` / `Running` / `Starting` / `Stopped`。
4. `Self.ID` 是稳定 Node ID；`Peer` map 里跳过自己，优先 IPv4，否则 MagicDNS。

登出：`POST /localapi/v0/logout`，`tailscale_close`，**删除整个 state 目录**。须二次确认。

state 目录：`Application Support/<YourApp>Tailscale`，`isExcludedFromBackup = true`。不要 iCloud。

### 6.4 loopback bridge（不要让 Dart/Swift 业务层直接拿 Tailscale fd）

`openBridge(nodeId, port)` 必须：

1. 节点 `running`，否则 `notRunning`。
2. `peers` 里找得到该 `nodeId`，否则 `unknownNode`。用 peer 的 IPv4 或 DNS 拼 `host:port`。
3. `tailscale_dial(handle, "tcp", "host:port", &fd)`。
4. 在 `127.0.0.1` 听（可先试业务端口，失败再 `port=0`）。`accept` 后若来源不是 `127.0.0.1` 立刻关掉。
5. 同时只允许一个 lease（`alreadyBridging`）。双向拷贝，idle timeout（本仓 30s，同步场景可加长），缓冲上限。
6. 返回 `{ url: "http://127.0.0.1:<boundPort>", leaseId }`。上层必须拒绝非 loopback URL。
7. App 进后台：停 bridge 或标不可用。回前台先看 node 是否还 `running`，再新建 bridge。iOS suspend 不是持续运行保证。

业务层继续用现有 HTTP/WS/gRPC client 连这个 URL。**不要**在 platform channel 上重写帧协议。

### 6.5 连接配置（可持久化 vs 不可）

| 字段 | 持久化 | 说明 |
| --- | --- | --- |
| `route` | 是 | `direct` / `systemTailscale` / `embeddedTailscale` |
| `nodeId` | 是 | 所选桌面的稳定 ID |
| `displayName` | 是 | 仅展示 |
| `port` | 是 | 桌面 helper 的 listenPort |
| 应用凭证 | 走现有 Keychain | 与 Tailscale state 分开 |
| 节点私钥 / tailscale state | 仅原生 state 目录 | 禁止写入 UserDefaults |

`EmbeddedTailscaleEndpoint.resolve()` 的语义：确保节点 running → 关掉旧 lease → `openBridge` → 把返回的 loopback URL 交给现有 client。重连时重新 `resolve()`，不要缓存已死的 lease。

---

## 7. 安全模型（必须原样保留）

| 边界 | 控制 |
| --- | --- |
| tailnet → helper | 节点身份 + ACL + 只听一个端口 |
| helper → 桌面服务 | 只拨 `127.0.0.1:<约定端口>` |
| 手机 → 桌面应用协议 | 你们自己的鉴权；不要用 WhoIs / hostname 当授权 |
| 宿主 → helper | 继承的 stdin/stdout、session nonce、协议版本、行长限制 |
| 磁盘 | owner-only state、登出删除、日志不含 token |
| 更新 | 包内 hash manifest；hash 变了才重解压 |

其它：

- helper / bridge 不是通用代理。
- 默认不用 auth key。用户通过官方页把这个节点加入自己的 tailnet。
- ACL / device approval / SSO 拒绝要显示成“等待批准 / 无访问权限”，不能靠放大监听范围绕过。
- 内嵌路径必须有 kill switch。关掉后 LAN 和系统 Tailscale 仍可用。
- iOS 嵌入 WireGuard 后，App Store 出口合规问卷必须重填。本仓旧的“未使用非豁免加密”声明不能沿用。
- 体积：iOS `libtailscale_ios.a` 大约十几到几十 MB；桌面 helper 也是数 MB 到十几 MB。发布说明里写清楚。

---

## 8. 给实现 agent 的工作顺序

不要并行写 UI 和真 Tailscale。按切片合入，每一刀都能单独关。

### P0 — 冻结契约（1 天，只写文档/类型/空实现）

- 定 listenPort、hostname 前缀、state 目录名、三种 `route`。
- 复制本文件第 4 节状态枚举和错误码。
- 画你们 sync server 的 loopback 地址。确认现有 client 能连 `127.0.0.1`。

**退出：** 书面约定 + 空接口能编译。现有 LAN 同步零回归。

### P1 — 桌面 helper 独立跑通（不改 UI）

- 拷 `native/tailscale-helper/`，改名，跑 `go test ./...` 和 `-race`。
- 用 fake backend（`main -fake`）接你们语言的 IPC harness。对照 `native/tailscale-helper/harness/java/` 和 `mods/26.2/.../tailscale/*Test.java`。
- 真机：helper `start` → 浏览器登录 → 另一台已装官方 Tailscale 的设备 `nc -vz <100.x> <listenPort>`，确认转到本机 echo。

**退出：** 两个真实节点能 TCP 打通；重启 helper 不用重新登录；stdin EOF 会清理 listener。

### P2 — 桌面 App 接入

- 实现解压器、进程监督、设置页（状态 / 打开登录 / 复制 URL / 登出）。
- sync server 成功 bind 之后才 `start` helper。
- 内嵌开关默认关；失败只影响 Tailscale，不影响 LAN。

**退出：** 已装系统 Tailscale 的手机（或第二台电脑）能走完你们的应用鉴权并同步一份真实数据。Wi-Fi 与至少一次 DERP 都要测。

### P3 — iOS 供应链 + 空插件

- 按 `ios/third_party/libtailscale/build.sh` pin 并编出两套 `.a`。
- 只暴露 `diagnostics`，确认真机 dyld/codesign 通过。

**退出：** 缺 `.a` 时 App 仍能跑，入口显示不可用原因。

### P4 — iOS 登录与选设备

- 抄 `TailscaleNodeManager` + `LibtailscaleBackend`。
- UI 抄 `tailscale_login_sheet.dart` 的状态文案和三种按钮。
- 单测用 fake backend，见 `ios/RunnerTests/TailscaleNodeManagerTests.swift`。

**退出：** 两台真机、两个网络完成首次登录和重启恢复。模拟器只测 UI。

### P5 — iOS bridge + 接上现有 sync client

- 抄 `TailscaleLoopbackBridge`。把返回 URL 的 scheme 改成你们的（`http` / `ws` / `grpc`），**host 必须是 `127.0.0.1`**。
- 现有 client 只改“连哪个 URL”，不改帧/鉴权。
- 后台/切网/锁屏后重新 `openBridge`。

**退出：** 前台同步 30 分钟无僵尸 listener；切 Wi-Fi↔蜂窝能恢复；ACL 拒绝不要报成“密码错误”。

### P6 — 发布门禁

- macOS notarize helper；Windows 签 helper。
- iOS Archive 只用 device `.a`；重填出口合规。
- 许可证：Tailscale / libtailscale 为 BSD-3-Clause，随包保留 `LICENSE`。
- 灰度 flag：出问题只关内嵌入口。

---

## 9. 新项目文件骨架（建议）

```text
native/tailscale-helper/                 # 从本仓拷贝，改名
  cmd/<app>-tailscale-helper/
  internal/{protocol,engine,backend,forward,lockfile,redact,version}
  scripts/build.sh
  dist/{darwin-arm64,darwin-amd64,windows-amd64}/

desktop-macos/                           # 或你们现有 macOS target
  Tailscale/HelperProcess.swift
  Tailscale/HelperExtractor.swift
  Tailscale/TailscaleService.swift
  Resources/native/tailscale/darwin-arm64/...
  Resources/native/tailscale/darwin-amd64/...

desktop-windows/
  Tailscale/HelperProcess.cs             # 或 C++
  Resources/native/tailscale/windows-amd64/...

ios/
  Tailscale/TailscaleCBackend.swift      # 从 TailscaleCBackend.swift 改名
  Tailscale/TailscaleNodeManager.swift
  Tailscale/TailscaleLoopbackBridge.swift
  Tailscale/TailscalePlugin.swift        # 若 Flutter；纯 Swift 则直接调 Manager
  third_party/libtailscale/{build.sh,VERSION.json,out/}

shared-models/                           # 可选
  TailscaleSnapshot.{swift,dart,ts}
```

桌面若**本身就是 Go**，可以不走 IPC，直接把 `internal/backend` + `internal/forward` + `internal/engine` 链进主程序。UI 仍用同一套状态枚举。不要在 Swift/C# 里重写 tsnet。

---

## 10. 测试：抄哪些，改哪些

必须先有、且不依赖真实 tailnet：

- helper 协议 golden + `DisallowUnknownFields`
- `ValidateTarget` 拒绝非 `127.0.0.1`
- fake backend 走完 `needsLogin → running → listening → stop`
- nonce 不匹配丢弃
- 解压器：hash 变了才重写
- iOS NodeManager：fake clock/backend 覆盖重复点击、cancel、logout 删目录、URL 脱敏
- bridge：本地 echo + fake dial；第二客户端拒绝；非 loopback accept 丢掉

真实 tailnet（发布前）：

1. 干净 macOS / Windows，不装官方 Tailscale，桌面 App 能打开官方登录页。
2. iOS 不装官方 Tailscale，能看到桌面 hostname 并完成一次同步。
3. 重启两端，无需重新授权。
4. 登出桌面或手机后，对端不能再同步。
5. 关内嵌开关，LAN 路径与关之前一致。

本仓对照测试：

- `native/tailscale-helper/internal/protocol/protocol_test.go`
- `native/tailscale-helper/internal/engine/engine_test.go`
- `native/tailscale-helper/internal/forward/forward_test.go`
- `mods/26.2/src/test/java/com/chenweikeng/monkeycraft/tailscale/`
- `flutter/monkeycraft/ios/RunnerTests/TailscaleNodeManagerTests.swift`
- `flutter/monkeycraft/test/stream/tailscale/`
- `flutter/monkeycraft/test/stream/connection_endpoint_test.dart`

---

## 11. 已踩过的坑（不要重踩）

1. **登录 URL 必须结构化。** `WatchIPNBus` 的 `BrowseToURL`，或 `status_json` 的 `AuthURL`。解析日志是禁止项。
2. **iOS 用 C archive，不用官方 TailscaleKit.framework。** Kit 会把最低系统抬到 18.1。见 `VERSION.json` 的 `embeddingReason`。
3. **device 与 simulator 两套静态库。** 混进 App Store archive 会签不过或被拒。
4. **helper 听的是 tailnet 端口，forward 目标是 loopback。** 手机连 helper 的 `listenPort`，不是桌面 server 偶尔换掉的那个 LAN 端口——除非你们保证两者相同并在 UI 上显示 helper 回传的 port。
5. **内嵌模式下对端 IP 变成 127.0.0.1。** 不要再用“来源是 100.x”判断 Tailscale 是否工作。健康状态只看 IPC / `status_json`。
6. **Android 现在不要做内嵌。** `tsnet.Start` 会因 `netlinkrib: permission denied` 失败（[upstream #17311](https://github.com/tailscale/tailscale/issues/17311)）。调研见 `doc/tailscale-integration/ANDROID_SPIKE.md`。Android 继续走系统 Tailscale App。
7. **浏览器 WASM 是另一条实验路径**（`doc/tailscale-integration/WEB.md`），时延按 DERP 评估，不要承诺和原生直连一样。
8. **不要把 hostname 当安全身份。** 只展示；连接键是 Node ID。
9. **父进程死掉必须带走 helper。** stdin EOF → cleanup。Windows 额外处理 job object 更稳，本仓 Java 侧是 destroy 直接子进程 + descendants。
10. **完整 auth URL 是短期能力。** UI 可复制，日志只打 host（`HelperRedact.authUrlHost` / `redact.AuthURLHost`）。
11. **iOS 后台会停 listener。** 同步任务回前台必须重建 bridge，不要复用旧 fd。
12. **桌面 helper 与 iOS libtailscale 的 Tailscale 版本不必相同。** 不要为对齐去升 iOS pin。

---

## 12. Agent 执行时的禁止事项

- 不要引入系统 VPN、Network Extension、Wintun 安装、或“请用户先装 Tailscale”作为内嵌路径的前提（系统路径可以单独保留）。
- 不要在包里放 `tskey-` reusable auth key。
- 不要实现通用端口转发或“用户输入任意 tailnet host:port”。
- 不要修改现有同步协议来穿过 platform channel。
- 不要在 LAN 能用时因内嵌失败而自动改连其它 peer。
- 不要把本仓的 HMAC、H.264、Minecraft UI、四棵 `mods/` 树一起抄走。
- 不要把 `doc/TAILSCALE.md` 的“检测 tailscale0 网卡”当成内嵌健康检查。

---

## 13. 完成定义（对你的项目）

同时满足才可写“支持内嵌 Tailscale”：

1. 干净的 Mac / Windows / iPhone，用户不装开发 SDK、不装官方 Tailscale App，能从你们的 App 打开官方登录并完成授权。
2. iOS 能选出正确电脑，走完你们现有的应用鉴权，并完成一次真实数据同步。
3. 取消登录、等待审批、ACL 拒绝、断网、切网、休眠、崩溃、升级、退出、清除 state，都有可读结果。
4. 关掉内嵌后，LAN 与系统 Tailscale 路径无回归。
5. helper / `.a` 有 pin、hash、许可证；macOS/Windows 签名策略已定；iOS 出口合规已重填。

做不到的平台从矩阵里拿掉，不要用交叉编译成功冒充已支持。
