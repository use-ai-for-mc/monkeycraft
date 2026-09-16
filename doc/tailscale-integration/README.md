# MonkeyCraft 内嵌 Tailscale 集成计划

## 1. 文档目的与状态

本目录定义 MonkeyCraft 在电脑 Mod、Flutter 手机端和网页端内嵌 Tailscale 能力的开发、测试与发布路径。它是**实施方案，不是已完成功能说明**；当前已存在的 `doc/TAILSCALE.md` 仍描述“用户自行安装并运行系统 Tailscale”的现状。

本计划的产品目标是让用户只安装 MonkeyCraft 交付物即可使用相应的内嵌节点，不要求用户安装 Go、C/C++、Rust、Xcode、Android SDK、Tailscale CLI 或完整 Tailscale VPN App。首次使用仍须由用户在 Tailscale 官方登录页登录并授权设备，tailnet ACL、设备审批和 Tailnet Lock 等规则仍然生效。

三个工作流分别见：

- [MOD_DESKTOP.md](MOD_DESKTOP.md)：Minecraft Mod/电脑端的预编译 helper、登录、生命周期、四个 Minecraft 版本集成。
- [MOBILE.md](MOBILE.md)：Flutter 连接抽象、iOS 原生实现与真机调试、Android 调研和 Go/No-Go。
- [WEB.md](WEB.md)：浏览器 WASM 节点、登录与设备选择、WebSocket 传输和性能验证。
- [TEST_MATRIX.md](TEST_MATRIX.md)：跨工作流的自动化层级、平台矩阵、故障注入、证据和发布门槛。
- [AGENT_PROMPTS.md](AGENT_PROMPTS.md)：推荐的并行节奏、文件所有权和三个专门 AI agent 的首轮工作 prompt。

## 2. 先冻结的架构决策

### 2.1 电脑端先做，保持现有协议

第一条可交付链路是：

```text
已启用系统 Tailscale 的现有手机 App
                  │
                  │ tailnet TCP :9600
                  ▼
Mod 随包携带的 userspace Tailscale helper
                  │
                  │ loopback TCP 127.0.0.1:9600
                  ▼
现有 MonkeyCraft WebSocket Server
```

helper 使用 Tailscale 的 userspace 网络栈在 tailnet 内监听 `9600`，再把字节流转发到现有 Mod 的 loopback WebSocket 服务。这样不改 H.264、命令、聊天、HMAC challenge、单手机限制和重连协议，也不要求电脑安装系统 Tailscale。`tsnet` 官方说明它可以在 Go 程序中内嵌独立节点，无需 root、系统 daemon 或虚拟网卡，并可通过标准 `net.Listener`/`net.Conn` 接口监听或拨号：[tsnet](https://github.com/tailscale/tailscale/tree/main/tsnet)。

这里推荐 helper 直接编译 Go `tsnet.Server`，而不是让 Java/JNI 动态加载 C shared library：前者仍是一个随 Mod 发布的自包含可执行文件，能直接使用 `Listen`、`LocalClient` 和结构化状态接口，减少跨平台 ABI、动态库搜索路径和崩溃隔离问题。`libtailscale` 仍是手机原生绑定的候选；它是 BSD-3-Clause 开源项目，可把节点完全嵌入 userspace 进程：[libtailscale](https://github.com/tailscale/libtailscale)。

### 2.2 手机和网页都是“仅应用流量”，不是系统 VPN

- iOS 内嵌节点只承载 MonkeyCraft 到所选电脑端口的连接，不注册全局 VPN，不改变其他 App 的路由。
- Android 先完成固定版本、固定工具链和真机矩阵的适用性复核；不因 iOS 可行就默认 Android 可行。
- 浏览器在 Web Worker 中运行 WASM userspace 节点。浏览器不能创建 TUN、不能直接发 UDP；第一版必须按 DERP/WebSocket relay 路径评估，不能承诺与原生 Tailscale 相同的直连时延。

### 2.3 永久保留三种连接方式

| 模式 | 电脑端 | 手机/网页端 | 用途 |
| --- | --- | --- | --- |
| `direct` | 现有 Mod 服务 | 普通 WebSocket | LAN 和手工地址，默认回退 |
| `systemTailscale` | 系统 Tailscale 或内嵌 helper | OS 的普通 WebSocket 路由 | 当前手机端兼容路径，也是电脑 helper 的首个验收客户端 |
| `embeddedTailscale` | 内嵌 helper | iOS/未来 Android/WASM 内嵌节点 | 不安装完整 Tailscale App 的目标路径 |

任何内嵌失败都必须明确告诉用户原因并允许切换；不得静默改连另一个主机，也不得删除现有 LAN/系统 Tailscale 行为。

## 3. 登录与设备选择的统一体验

“在 MonkeyCraft 里登录”不表示 MonkeyCraft 收集 Tailscale 密码。各端只接收底层节点给出的短期登录 URL，在系统浏览器或新标签页打开 Tailscale 官方页面；用户在官方页面完成身份提供方登录、tailnet 选择、设备审批。原 MonkeyCraft 页面持续观察节点状态，直到 `running`、取消、超时或需要管理员审批。

建议统一状态模型：

```text
unavailable → stopped → starting → needsLogin(authUrl)
                                      │
                                      ├─→ needsApproval
                                      └─→ running(identity, addresses)

starting/running → degraded(reason) → reconnecting
任意活动状态   → stopping → stopped
任意活动状态   → failed(code, recoverable)
```

设备选择只在本机节点达到 `running` 后出现：

1. 从 LocalAPI/netmap 读取当前账号可见的 peers，而不是调用 MonkeyCraft 自建账号系统。
2. 显示设备名、在线状态和必要的区分信息；优先保存稳定 node ID，连接时重新解析地址。
3. 第一版可先筛选带 MonkeyCraft 明确标识的 helper 节点；若标识机制尚未验证，则列出 peers 并让现有 HMAC 握手确认目标，绝不扫描整个 tailnet 的端口。
4. 网络 ACL 只决定“能否到达”，MonkeyCraft HMAC 仍决定“能否控制游戏”；两层都保留。
5. “断开连接”“忘记电脑”“退出 Tailscale 并删除本地节点状态”是三种不同操作，UI 和测试必须分开。

完整登录 URL、节点私钥、可复用 auth key、OAuth client secret 和 WebSocket 密码都视为机密。它们不得进入普通日志、崩溃报告、分析平台、截图或前端持久化配置。通用客户端不随包放置 reusable auth key。

## 4. 跨端契约

### 4.1 连接配置

共享概念而不强求三端使用同一序列化实现：

| 字段 | 含义 | 持久化规则 |
| --- | --- | --- |
| `route` | `direct/systemTailscale/embeddedTailscale` | 可持久化 |
| `nodeId` | 所选电脑的稳定 Tailscale node ID | 可持久化；地址改变后重新解析 |
| `displayName` | 用户可识别名称 | 可持久化，不作为安全标识 |
| `port` | MonkeyCraft 端口，默认 `9600` | 可持久化且需范围校验 |
| `websocketCredential` | 现有 MonkeyCraft 密码/派生材料 | 继续走现有安全存储 |
| `tailscaleState` | 节点身份、私钥和控制面状态 | 仅由对应原生/helper/WASM 安全存储管理 |

### 4.2 helper 进程协议

电脑端 Java 与 helper 使用带版本号的 JSON Lines 协议：stdin 只接收命令，stdout 只输出协议消息，stderr 只输出已脱敏诊断。首个字节输出前必须完成协议握手；所有消息含 `protocolVersion`、`requestId` 或单调递增 `eventId`。

最小命令集为 `start`、`status`、`stop`、`logout` 和 `shutdown`；最小事件集为 `ready`、`stateChanged`、`authRequired`、`listening`、`error` 和 `stopped`。字段、错误码和兼容规则先在 standalone helper 阶段用 golden tests 冻结。不要依赖解析 `UserLogf` 的人类文本取得登录 URL；必须先验证能否经 IPN bus/LocalAPI 获得结构化 `BrowseToURL`，否则该阶段不得进入 Mod UI 集成。

### 4.3 版本与供应链

每个发布版本固定并记录：

- Tailscale/libtailscale commit 和上游许可证；
- Go、Xcode/Swift、Flutter、Android Gradle Plugin/NDK 和 WASM 工具链版本；
- helper protocol、Flutter native plugin 和 Web Worker message protocol 版本；
- 每个二进制/WASM 的目标 OS、架构、SHA-256、大小、构建来源和 SBOM；
- 上游安全更新的评估人、升级节奏和回滚版本。

最终用户路径只使用已签名或已校验的预编译产物。JAR/App/Web 构建如果缺少目标产物、hash 或许可证必须失败，不能回退成“请用户本地安装 SDK 后编译”。

## 5. 总体分期和依赖关系

| 阶段 | 主要结果 | 进入下一阶段的硬门槛 |
| --- | --- | --- |
| P0 基线冻结 | 固定上游版本、威胁边界、状态/错误码、性能基线 | 决策记录和测试数据可复现 |
| P1 电脑 helper 独立原型 | 登录、持久状态、tailnet `:9600` listener、loopback 转发 | 两个真实节点可稳定连接，重启可恢复 |
| P2 单一 Mod 集成 | 先接入 `mods/26.2`，页面打开登录、状态、停启 | fake-helper 单测和真实手机 E2E 都通过 |
| P3 四版本与发布 | 26.2、26.1、1.21.11、1.19 同步；全平台 helper 入 JAR | 四棵树一致性、JAR 内容和无 SDK 安装验证通过 |
| P4 手机共享抽象+iOS | direct 不回归；iOS 登录、选电脑、单端口 bridge | TestFlight 真机/切网/恢复/合规门槛通过 |
| P5 网页实验 | Worker+WASM 登录、peer 列表、协议字节流 | DERP 视频性能和浏览器矩阵达到书面阈值 |
| P6 Android 复核 | 最小 AAR/JNI repro、真机证据包、风险清单 | 明确 Go/No-Go；No-Go 时保持系统 VPN |
| P7 联合 beta | 三端可观测性、回退、升级和支持流程 | [TEST_MATRIX.md](TEST_MATRIX.md) 的发布门槛全部留证 |

P4、P5、P6 可在 P1 冻结登录/状态术语后并行，但电脑 helper 的 P2 是业务端到端的共同依赖。每个阶段只合入可独立测试、可关闭、不会破坏旧路径的最小切片。

## 6. 共同安全与运行约束

- helper、原生 bridge 和 WASM 只连接 MonkeyCraft 所需的单个 TCP 端口，不提供通用 SOCKS、出口节点、Funnel、子网路由或任意端口扫描。
- helper 必须与 Minecraft 生命周期绑定：单实例锁、父进程退出清理、有上限的重启退避、崩溃循环熔断；不得留下后台僵尸进程。
- 本地 bridge 只监听 loopback 和随机端口，并限制单会话、单客户端、目标白名单、缓冲区、空闲超时和关闭传播。标准 WebSocket 客户端不能自动发送自定义“首包 nonce”，因此 nonce 若作为安全条件，必须在 I3 spike 中证明可通过握手 header/受控代理验证；证明前不能把“有 nonce”写成已实现保障。
- Tailscale 上游日志上传行为、崩溃采集、诊断导出和 IP/设备名的隐私边界在 P0 明确。用户可见日志默认脱敏，完整登录 URL永不记录。
- 不把 tailnet 可达性当作 MonkeyCraft 身份认证，不降低现有 HMAC 强度，也不因 WhoIs 信息自动授予游戏控制权。
- 每条内嵌路径都必须有 kill switch；关闭后 direct 和 system-Tailscale 仍可使用。

## 7. 项目完成定义

只有同时满足以下条件，才能把相应平台标记为“支持内嵌 Tailscale”：

1. 新用户在干净机器/手机/浏览器上无需安装开发 SDK 或完整 Tailscale App，能从 MonkeyCraft 进入官方登录并完成设备授权。
2. 能选择正确电脑并完成现有 WebSocket HMAC、控制、聊天和 H.264 端到端会话。
3. 登录取消、审批等待、ACL 拒绝、断网、切网、休眠、崩溃、升级、退出和状态清理都有可理解的结果。
4. 自动化测试、真实 tailnet 测试、平台签名/商店或网页发布检查都有可追溯证据。
5. 许可证、SBOM、hash、代码签名/完整性、隐私和加密出口评估完成。
6. 内嵌功能关闭或失败时，既有 LAN 和系统 Tailscale 路径无回归。

Android 若最终为 No-Go，不影响电脑端、iOS、Web 或 Android 的系统 Tailscale 兼容路径完成各自目标。
