# MonkeyCraft Mod / 桌面端内嵌 Tailscale 方案

> 2026-09-18：本文件包含早期实施建议与历史阶段编号；产品优先级以 [产品路线](../PRODUCT_ROADMAP_2026-09.md) 为准，当前证据见 [执行记录](../PRODUCT_ROADMAP_EXECUTION.md)。Flutter iOS/Android 与 `web/` 均长期维护；移动双端内嵌是已确认目标，Android 技术门槛不是取消产品目标。当前浏览器正式路径为 LAN/系统 Tailscale；WASM 属于 P4 候选探索，未经选择不自动产品化。

## 1. 目标、范围与结论

本方案让运行 Minecraft 的电脑在**未安装 Tailscale 桌面 App、未安装任何 SDK**的前提下，随 MonkeyCraft Mod 启动一个预编译的原生 helper。helper 在用户态运行 Tailscale 节点，只把 MonkeyCraft WebSocket 端口代理到 Tailnet；用户从 Mod 的设置页发起登录，系统浏览器完成 Tailscale 授权。首个交付目标是：现有已开启系统 Tailscale VPN 的手机 MonkeyCraft App，能够以 helper 报告的 Tailnet 地址和端口连接 Minecraft。

这不是系统级 VPN，也不试图代理电脑的其它应用流量。Tailscale 节点、WireGuard、DERP 和控制面协议在 helper 进程内运行；Mod 保留现有的 WebSocket 协议和 HMAC 配对认证。

本文件是开发和测试计划，不将下列尚未在 MonkeyCraft 环境中验证的事情当作既成事实：

- `tsnet`/`libtailscale` 版本能否以目标平台所需的交叉编译方式稳定产出；
- helper 的 userspace listener 能否与 Minecraft 本机监听端口按预期隔离、并稳定转发长时间 H.264 WebSocket 流；
- Minecraft/Fabric 的系统浏览器打开方式在 Windows、macOS、Linux 各发行版上是否一致可用；
- 无外部 Tailscale App 时 Windows 防火墙、macOS Gatekeeper/隔离属性、Linux 安全策略的真实行为。

这些均列为先导 spike，任何一个失败都应先缩小或改变实现，而不是把未经测试的假设扩散到四个 Mod 树。

### 非目标

- 不改写现有手机端、网页端或浏览器 WASM 方案；它们由对应专题文档负责。
- 不将可复用 auth key、OAuth client secret 或用户密码放进 JAR、helper 参数、日志或二维码。
- 不提供子网路由、出口节点、MagicDNS 配置、SSH、系统 VPN 或任意端口转发。
- 不移除现有“用户自行安装 Tailscale”的兼容路径；嵌入式模式失败时该路径仍可使用。

## 2. 现状与设计约束

仓库目前有四套平行的 Fabric Mod 树：`mods/1.19`（Java 17）、`mods/1.21.11`（Java 21）、`mods/26.1` 和 `mods/26.2`（Java 25）。其中网络与配置代码高度相似，但并非完全相同；不能假定一次改动会自动覆盖全部版本。

现有 `WebSocketServerHandler`：

- 在 `9600–9700` 中选择实际端口并启动 `org.java_websocket` 服务器；
- 只允许一个已认证客户端，认证仍是基于 Mod 密码的 HMAC challenge-response；
- 已有 `NetworkScope` 与 `TailscaleAccess`。后者只是依据网卡启发式判断是否存在**外部** `tailscaled`，并允许来自 `100.64.0.0/10` 的连接；
- `NetworkUtils` 和 `AccessPolicyTest` 已提供可复用的纯访问策略测试基础；
- 服务器在标题页持久启动、进世界启动或手动启动三种生命周期下工作。

因此，首版不能只把 helper 启动起来：它必须与实际选择的 WebSocket 端口、服务器停止、标题页持久模式和 Mod 退出一同收敛。特别地，helper 转发给 `127.0.0.1` 时，Mod 看到的远端地址是 loopback；这正好允许 `THIS_COMPUTER` 策略继续生效，但也意味着旧的“100.x 来源地址”判定不能再被用作内嵌模式是否工作的依据。

## 3. 推荐架构

### 3.1 进程边界

```text
手机（现有系统 Tailscale VPN）
       │ Tailnet TCP
       ▼
随 Mod 解压并启动的 monkeycraft-tailscale-helper
  - tsnet/libtailscale userspace node
  - 只监听一个 MonkeyCraft 服务端口
  - 将字节流转发到 127.0.0.1:<actualWsPort>
       │ loopback TCP
       ▼
现有 Java-WebSocket 服务器 → HMAC 认证 → 输入/聊天/H.264

Java Mod ── stdin/stdout JSON Lines（私有子进程管道）── helper
       │
       └─ 系统浏览器打开一次性 Tailscale 登录 URL
```

helper 首选直接使用 Go 的 `tsnet.Server`，而不是运行或控制系统 `tailscaled`。Java 只负责提取、启动、监督和显示状态；不通过 JNI 链接 Tailscale C 库。这样既符合 Java 17–25 的兼容范围，也能直接使用 `Listen`、`LocalClient` 和结构化 IPN 状态，并把原生运行时和崩溃隔离在可替换进程中。只有阶段 0 证明 `tsnet` 存在不可接受的构建或运行阻塞后，才比较基于 `libtailscale` 的替代 helper；两者都必须最终交付为自包含可执行文件。

helper 的监听器是单用途的：只接受 Tailnet 内到指定服务端口的 TCP，连接后只允许目标 `127.0.0.1:<actualWsPort>`。它不得接受“host/port”形式的远程指令、SOCKS 代理、LocalAPI、子网路由或出口节点配置。

### 3.2 Java ↔ helper IPC

使用 helper 的 stdin/stdout JSON Lines 作为唯一控制通道；stderr 仅作经脱敏的诊断日志。这样端口不暴露给本机其它进程，也不需要在 Mod 中保存控制 API 密钥。Java 每次启动生成随机会话 nonce，并通过继承的 stdin 发送；helper 的每条响应都必须带相同 nonce，Java 忽略不匹配消息。

建议的最小协议（字段与事件名称可调整，但语义必须版本化）：

```json
{ "protocolVersion": 1, "sessionNonce": "…", "requestId": "1", "command": "start", "target": "127.0.0.1:9600", "listenPort": 9600, "stateDir": "…" }
{ "protocolVersion": 1, "sessionNonce": "…", "eventId": 1, "event": "stateChanged", "state": "needsLogin" }
{ "protocolVersion": 1, "sessionNonce": "…", "eventId": 2, "event": "authRequired", "authUrl": "https://login.tailscale.com/a/…" }
{ "protocolVersion": 1, "sessionNonce": "…", "eventId": 3, "event": "stateChanged", "state": "running", "tailnetIp": "100.x.y.z", "port": 9600 }
{ "protocolVersion": 1, "sessionNonce": "…", "requestId": "2", "command": "status" }
{ "protocolVersion": 1, "sessionNonce": "…", "requestId": "3", "command": "logout" }
{ "protocolVersion": 1, "sessionNonce": "…", "requestId": "4", "command": "stop" }
```

需要的状态至少为 `extracting`、`starting`、`needsLogin`、`loginOpened`、`needsApproval`、`running`、`degraded`、`stopping`、`stopped`、`unavailable`、`failed`。事件应附带稳定的错误码（例如 `BINARY_MISSING`、`STATE_LOCKED`、`LOGIN_TIMEOUT`、`LOCAL_TARGET_UNREACHABLE`），而不是要求 Java 根据英文错误文本分支。完整 schema、字段上限与前后兼容规则以本目录总纲为准，并在阶段 1 以 golden vectors 冻结。

**浏览器登录：** helper 只报告登录 URL。Mod 在玩家明确点击“登录 Tailscale”后通过受限的 `BrowserLauncher` 打开系统默认浏览器，并显示可复制 URL；不得让 helper 自行执行 shell 或打开任意 URL。系统浏览器打开 API 和 Linux fallback 是 spike 的一部分。

### 3.3 生命周期与状态保存

建议将状态分为两类，且不混入 `config/monkeycraft.json`：

```text
config/monkeycraft.json                    非秘密的用户开关与显示偏好
config/monkeycraft/tailscale/state/        helper 节点状态、节点私钥及控制面登录状态
config/monkeycraft/tailscale/helper/       从 JAR 解压的当前 helper 和 .sha256 sidecar
config/monkeycraft/tailscale/logs/         轮转且脱敏的诊断日志（可选）
```

实际目录必须通过 `FabricLoader.getInstance().getConfigDir()` 取得，不能猜测启动器的游戏目录。state 目录只由 helper 访问：创建时尽量设为 owner-only；Windows ACL 的可行性需在 spike 中验证。退出登录应由 helper 清除其身份状态，再由 Java 删除已验证属于该 state 目录的文件。绝不把 state 内容显示在 Minecraft 聊天、配置 GUI、崩溃报告或 CI artifact。

电脑端默认使用持久节点身份（`Ephemeral=false`）：同一份 state 在 Minecraft 和 Mod 升级后复用，避免用户每次启动都重新授权，也让手机可以保存稳定 Node ID。只有用户点击“退出 Tailscale 并删除此节点状态”才清除身份。多个 Minecraft 实例不能共享写入同一 state；首版通过 owner lock 明确拒绝第二个 helper，而不是复制身份或并发打开。

建议的生命周期规则：

1. Mod 初始化不自动登录、不自动启动 helper，除非用户明确启用“随服务器启动维持嵌入式 Tailscale”。
2. WebSocket server 成功取得实际端口后，`TailscaleService.ensureRunning(actualPort)` 再启动 helper；不得把预期端口当成实际端口。
3. Mod 的服务器端口改变或 server 重启时，先停止代理 listener，再重建到新 loopback 目标的 listener；已有手机连接按现有断线语义处理。
4. 标题页持久服务器继续运行时 helper 也继续运行；非持久服务器随世界断开而停止时 helper 必须停止 listener，并可选择保留已登录 state。
5. Fabric 客户端停止事件中，先拒绝新的 helper 连接、再停止 WebSocket server/转发、最后有界等待 helper 退出；超时才强杀其**直接子进程**，不可按名称杀进程。
6. helper 意外退出时，不重启 Minecraft；将状态改为失败并以指数退避最多重试有限次数。用户仍可手动重试或走现有外部 Tailscale 路径。

### 3.4 与现有 WebSocket 的集成策略

首个端到端目标保持 Mod 的 WebSocket、HMAC、单客户端限制、视频 backpressure 和现有 Flutter 协议完全不变。仅新增一个 `TailscaleService`（Java 接口）以及一个以真实进程实现的 `HelperTailscaleService`。`WebSocketServerHandler` 在 start/stop 和端口变更点调用该接口，但不解析 helper JSON。

必须先在 spike 中确认 Java-WebSocket 是否可绑定到 loopback。若可以，嵌入式模式应提供“仅 loopback + helper”的监听选项，以保证 LAN 客户端无法绕过 Tailnet；若暂时不能，首版必须在 UI 和文档清楚说明仍受现有 `NetworkScope` 约束，且不以“内嵌 Tailscale”宣称隔绝 LAN。无论哪种选择，HMAC 密码仍是第二道必需防线。

现有 `TailscaleAccess` 的含义需要保留用于**外部** tailscaled 模式；建议另设：

- `embeddedTailscaleEnabled`：默认 `false`；
- `embeddedTailscaleAutoStart`：默认与 WebSocket server 生命周期绑定；
- `embeddedTailscaleListenPort`：初期默认请求等于实际 WebSocket 端口，helper 必须报告最终端口；
- `embeddedTailscaleLastEndpoint`：仅展示缓存，不作为安全身份来源。

不要让“检测到 `tailscale0`”决定 embedded 状态。helper 应通过 IPC 直接报告健康状态。

## 4. 原生资源、平台矩阵与构建

### 4.1 从 imf 借鉴的部分

`/Users/cusgadmin/if-local/imf` 已验证了适合本仓库的分发形态：CI 分别在 macOS 与 Windows 构建原生 helper，上传短期 artifact，在 Linux 汇总进 Mod JAR；`NativeHelperExtractor` 使用 JAR 资源 SHA-256 sidecar 判断缓存是否过期，并以临时文件加移动方式重解压。MonkeyCraft 应复用该**模式**，而不是复制其 WebView 业务代码：

- helper 二进制和 `.sha256` 缓存校验，避免 Mod 更新后继续运行旧 helper；
- 在 JAR 内按 OS/架构保存原始二进制；
- CI 在打包后用 `jar tf` 及 SHA-256 manifest 验证每个资源；
- 进程监督采用带超时、监听失败和子进程清理的状态机，而非一次 `ProcessBuilder` 调用。

imf 当前 macOS 为 universal binary、Windows 为 `win-x64`，没有 Linux helper；MonkeyCraft 不能把这当作自身的平台覆盖证据。

### 4.2 建议目录和命名

```text
native/tailscale-helper/                  Go module、锁定的 Tailscale 版本、构建脚本、测试
native/tailscale-helper/cmd/monkeycraft-tailscale-helper/
native/tailscale-helper/scripts/
mods/<mc>/src/main/resources/native/tailscale/
  manifest.json                           版本、目标、SHA-256、构建来源
  darwin-arm64/monkeycraft-tailscale-helper
  darwin-amd64/monkeycraft-tailscale-helper
  windows-amd64/monkeycraft-tailscale-helper.exe
  linux-amd64/monkeycraft-tailscale-helper
  ...
tools/sync-tailscale-helper-resources.sh  将经验证 artifact 同步到四个 Mod 树
```

不要依赖 `os.name` 的模糊匹配或一个 macOS universal 文件来掩盖架构选择；Java 选择器应映射明确的 `darwin-arm64`、`darwin-amd64`、`windows-amd64`、`windows-arm64`、`linux-amd64`、`linux-arm64`。每一个目标只有在 CI 构建、JAR 存在性检查和真实设备 smoke test 都通过后才标为支持。

初始发布范围建议保守地从开发团队实际可测试的 `darwin-arm64`、`darwin-amd64` 和 `windows-amd64` 开始。Linux（尤其 glibc/musl、桌面环境与防火墙差异）及 Windows ARM64 都应作为独立 spike，不得仅因为 Go 可交叉编译就标示支持。

### 4.3 helper 构建与供应链

- 固定 Go 版本、Tailscale module 版本及其校验和；升级通过独立 PR 完成。
- build 脚本打印 `GOOS/GOARCH`、helper 版本和依赖版本，产出 SHA-256 manifest；不得从“最新”下载预编译 Tailscale。
- macOS、Windows、Linux 各自 runner 构建或在已验证的交叉构建流程中构建；交叉构建本身不能替代真实运行测试。
- 在 helper 启动时输出 `protocolVersion` 与 `helperVersion`；Java 对不兼容版本 fail closed，并建议重解压，而不是发送未知命令。
- macOS 签名、notarization、Windows SmartScreen/代码签名会影响用户体验；在签名方案定案前将其列为发布阻塞项，而不是承诺无警告运行。

## 5. 分阶段开发、测试与准入标准

每阶段先以 `mods/26.2` 为主实现和验证；通过后再移植到其它树。共享的、无 Minecraft API 依赖的 Java 类应保持逐文件一致，并由脚本比较内容哈希；不要在四个树中静默产生不同协议实现。

### 阶段 0：技术 spike 与决策记录

实现最小 Go helper（不进入发布 JAR）并记录每项结果：

1. `tsnet` 节点启动、经结构化 IPN/LocalAPI 事件取得交互式登录 URL、持久 state、重新启动后无需再次登录；禁止把解析 `UserLogf` 人类文本作为正式协议。
2. helper listener 到 `127.0.0.1` echo/WebSocket echo 的双向转发、半关闭、断开和至少 30 分钟空闲连接。
3. 同一 tailnet 中已装 Tailscale 的手机/另一电脑到 helper 的实际 TCP 连通；记录 direct 与 DERP 情况。
4. Java 17/21/25 启动子进程、读取 JSON Lines、关闭时清理的独立 harness。
5. Windows x64、macOS arm64/amd64 上系统浏览器打开 URL、state 目录权限、被杀进程后的恢复；Linux 只在目标发行版上单独判定。
6. Java-WebSocket 对 loopback 绑定能力和 `networkScope` 行为。

**准入：** 将每个平台、Tailscale 版本、命令、结果和已知限制写入 spike 记录；至少一个桌面平台完成真实 Tailnet echo。

**退出：** 选定 `tsnet` 或其它封装、初始支持矩阵、监听地址方案和最小 IPC v1。失败则停止后续集成，先更改架构。

### 阶段 1：helper 可重复构建与离线协议测试

- 建立 `native/tailscale-helper`、JSON Lines 协议、版本和结构化错误码。
- 用 fake backend/loopback echo 测试 state transition、非法命令、nonce 不匹配、target 不是 loopback、端口占用、子进程 EOF 与超时。
- 为所有候选目标产出 helper；尚不能真机验证的产物不放入稳定发布集合。

**自动测试：** Go 单元测试、race 检查、JSON schema/黄金文件、helper 启动健康测试、二进制 SHA-256 与 `manifest.json` 一致性。

**准入：** 协议可在无 Minecraft 条件下由 Java harness 驱动，错误不泄漏 state/URL token。

**退出：** 生成可由 CI 下载和复现的、带版本 manifest 的 artifact。

### 阶段 2：Java 提取器与进程监督（尚不接入 GUI）

- 实现与 imf hash-sidecar 语义相同的 `NativeHelperExtractor`，但资源路径和缓存位于 MonkeyCraft 专用目录。
- 实现 `TailscaleService` 接口、`HelperProcess`、平台选择器、stdout 限额/行长限制、stderr 脱敏轮转和有界停止。
- 使用 fake helper 脚本/测试 fixture，覆盖旧二进制重解压、崩溃、卡住、协议版本不符、重复 start/stop、只杀直接子进程。

**自动测试：** 每个 Mod 树最少运行纯 Java 单测；平台选择表、SHA sidecar、状态转换和超时测试必须共享同一组测试向量。

**准入：** 不启动真实 Tailscale 时，Mod 也能安全加载；缺少对应二进制只显示“此平台暂不支持”。

**退出：** 关闭 Minecraft 或停服不留下可工作的 listener；异常不会令现有 LAN WebSocket server 不可用。

### 阶段 3：26.2 中的服务器生命周期与设置 UI

- 在实际 `startServerWithPortRange` 成功后调用 `ensureRunning(actualPort)`；在 stop 与客户端退出路径调用停止。
- 加入配置项、翻译文本、状态页和“登录/复制 URL/登出/重试”操作；所有 UI 操作回到 Minecraft 客户端线程更新。
- `authRequired` 携带的 URL 仅由用户动作打开；处理浏览器启动失败、设备审批等待和登录取消。
- 展示 helper 报告的地址、端口、连接状态和简短可操作错误；不展示私钥、完整控制 URL token 或日志。

**自动测试：** `TailscaleService` fake 的 start/stop 与实际端口传递；配置 JSON 向后兼容；既有 `AccessPolicyTest` 保持通过。

**集成测试：** 本机 WebSocket echo 通过 helper loopback 转发；反复 start/stop、端口从 9600 回退至范围内其它端口、标题页持久模式。

**准入：** 嵌入式开关关闭时行为与当前版本逐项一致。

**退出：** 26.2 上现有手机 App（系统 Tailscale 已登录）可完成 WebSocket HMAC 握手并在至少一次直连和一次 DERP 条件下传输真实视频/输入。

### 阶段 4：安全收紧、真实设备矩阵与故障降级

- 根据阶段 0 的结果决定是否将 Mod WS 限制为 loopback；若不能，明确 LAN 暴露的残余风险和默认 `NetworkScope`。
- 测试状态文件被复制、权限过宽、另一个 helper 持有 state lock、helper 二进制篡改、登录 URL 被重复/过期使用和远程端口扫描。
- 实现默认关闭、显式启用、失败后保留 LAN/外部 Tailscale 手动连接、可登出并清理 state 的体验。

**手工矩阵：** 每个已声明桌面目标至少覆盖首次登录、重启后恢复、注销再登录、Wi-Fi 切换、睡眠/唤醒、Minecraft 崩溃、helper 崩溃、网络离线、Tailnet ACL 拒绝、手机切蜂窝网络、长时间 20 FPS 流。

**准入：** 失败可解释、可恢复，且不会自动打开公网端口。

**退出：** 初始支持平台签收，发布说明明确未支持的系统和 fallback。

### 阶段 5：移植四个 MC 版本与发布门禁

- 按 `26.2 → 26.1 → 1.21.11 → 1.19` 移植；每一树独立编译、Spotless、单测和实际 JAR 检查。
- 与 Minecraft API 有关的浏览器/UI/生命周期适配可以不同；`tailscale` 进程、IPC、配置迁移和安全策略代码必须使用相同协议版本。
- 扩充 GitHub Actions：先按 OS/架构构建 native artifact，再汇总并同步到四个 resources 目录，最后构建四个 JAR。

**CI 必检：**

1. helper 的版本和 SHA manifest；
2. 每个声明支持 target 的 JAR 都含有对应 `native/tailscale/<target>/…`；
3. JAR 内二进制 hash 与 manifest 一致，且 macOS 文件具有预期 Mach-O 架构、Windows 为 PE、Linux 为 ELF；
4. 四个 Gradle build/test，26.2 的 Spotless（并逐步统一其余版本的格式检查）；
5. helper 协议单测与 Java fake-helper 单测；
6. release job 不得在 native artifact 缺失、版本不匹配或未签名策略未满足时发布。

**发布退出：** 每个正式 JAR 均可在其声明支持的平台提取正确 helper；某个 MC 或 OS 失败时从该版本 release matrix 移除 embedded 功能，不影响其它 Mod 基础功能。

## 6. 安全模型与操作风险

| 边界 | 控制措施 |
| --- | --- |
| Tailnet → helper | Tailscale 节点身份、tailnet ACL、只监听一个服务端口；不启用路由/出口/SOCKS。 |
| helper → Mod | 只允许固定 loopback 目标和 TCP；helper 不接受远程目标地址。 |
| 手机 → Mod 协议 | 继续使用既有 HMAC 配对、单客户端限制、命令 allow/deny list。 |
| Java → helper | 继承 stdin/stdout、随机 nonce、协议版本、消息与日志长度限制。 |
| 磁盘 | state 与私钥置于专用目录、最小权限、登出时删除、日志不含 token/私钥。 |
| 更新 | JAR 内 hash manifest、缓存 hash sidecar、可回退到上一已验证 helper。 |

登录 URL 本身是短期敏感能力，UI 只展示到完成/过期为止；日志仅记录 host 与状态，不记录完整 URL query。默认不使用 auth key；让用户通过官方浏览器页将这个 helper 节点加入自己的 Tailnet。设备审批、ACL 或 SSO 拒绝必须原样呈现为“等待批准/无访问权限”，不能通过提高网络范围来绕过。

## 7. 升级、回滚与故障处理

- **helper 更新：** JAR manifest 版本或 SHA 改变即原子重解压；旧文件可在新 helper 已报 `running` 后清理。若新版本启动失败，保留上次已验证版本的诊断信息，但默认不自动降级运行旧加密组件；是否支持受控回滚应经过安全评估。
- **协议更新：** helper 与 Java 各自声明 protocol min/max。未知高版本、低版本或非 JSON 输出一律 fail closed，显示“重新安装匹配版本”，不继续转发。
- **state 迁移：** helper 对 state schema 做备份与原子迁移；迁移失败不覆盖原 state，并提供“登出并重新登录”恢复按钮。
- **登录失败：** helper 继续处于 `needsLogin`/`failed`，现有 LAN 和用户自行安装 Tailscale 的路径不受影响。
- **服务故障：** helper listener 断开时主动关闭受影响 WebSocket，利用现有手机端重连策略；不得假装已连接或将流量改送公网。
- **紧急停用：** 远程配置/本地开关只能禁用 embedded helper 的启动与 listener，不能删除用户状态，除非用户明确选择登出。

## 8. 需要先回答的决策问题

1. 初始版本是否只支持“手机仍安装官方 Tailscale App”的对端？本文件假定是；这能把桌面 helper 与手机内嵌工作拆开验收。
2. 首版是否要求 WebSocket 只绑定 loopback？若是，必须先完成 Java-WebSocket 绑定 API spike；若否，发布文案必须说明 LAN 策略仍生效。
3. 首选 `tsnet` helper；只有实际 spike 暴露阻塞时，才以同一组跨平台构建、登录和长连接数据评估 `libtailscale` 封装替代，不能仅凭 API 偏好切换。
4. 哪些 OS/架构有真实测试设备和签名能力？它们决定初始支持范围，不能由 CI runner 替代。
5. 持久节点已经作为默认方案；仍需决定设备命名、Tailnet ACL 提示，以及登出后是否同时引导用户从 Tailscale 管理页删除设备记录。

在这些问题完成前，任何代码实现都应维持在 spike 或实验性开关下，不能改变当前 `doc/TAILSCALE.md` 所描述的外部 Tailscale 使用承诺。

## 9. 阶段 0/1 实测结论（2026-08-30）

独立 helper 在 `native/tailscale-helper/`。固定 `tailscale.com v1.102.3`（BSD-3-Clause）与 Go 1.26.6。IPC v1 与 fake-backend 测试、race、Java 17/21/25 harness、darwin-arm64 真机构建均已通过。真实 `tsnet` 经 `WatchIPNBus` 的 `BrowseToURL` 发出 `authRequired`，未解析 UserLogf。尚未做浏览器授权后的持久恢复或两节点 TCP。Windows/Linux 仅交叉编译。细节与 P2 清单见 [evidence/p0-p1/PHASE0.md](evidence/p0-p1/PHASE0.md) 和 [evidence/p0-p1/P2_NEXT.md](evidence/p0-p1/P2_NEXT.md)。
