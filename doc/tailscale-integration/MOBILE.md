# MonkeyCraft 手机端内嵌 Tailscale：开发与验证方案

> 2026-09-18：本文件包含早期实施建议与历史阶段编号；产品优先级以 [产品路线](../PRODUCT_ROADMAP_2026-09.md) 为准，当前证据见 [执行记录](../PRODUCT_ROADMAP_EXECUTION.md)。Flutter iOS/Android 与 `web/` 均长期维护；移动双端内嵌是已确认目标，Android 技术门槛不是取消产品目标。当前浏览器正式路径为 LAN/系统 Tailscale；WASM 属于 P4 候选探索，未经选择不自动产品化。

> 2026-09-19：iOS 正式 C archive 已改为从固定版本的隔离源码副本构建，并以受跟踪补丁将 `tsnet.Server.UserLogf` 设为 discard，避免认证 URL 写入系统控制台。该覆盖层与 `tailscale_set_logfd(-1)` 一起禁止正式运行时 raw 日志；诊断 archive 不参与正式构建。构建拒绝覆盖脏源码，并记录模块锁与许可证哈希。构建产物、精确 Go 1.26.3 的安装方式与本轮18项模拟器通过、真实设备待验收边界见[本轮记录](evidence/2026-09-19-ios-product.md)。

## 1. 目标、边界与当前结论

本方案让 MonkeyCraft 手机端可选择在自身进程内运行一个 Tailscale userspace 节点。用户只安装 MonkeyCraft，不必另装或开启系统 Tailscale VPN App；但首次使用仍需以自己的 Tailscale 账号登录并授权这个节点。它不是整机 VPN：只有 MonkeyCraft 到 Minecraft 的连接进入 tailnet，因此不占用系统 VPN 槽，也不改变其他应用的流量。

首个可交付目标为 **iOS 内嵌连接**：手机端成功登录、选择一台运行 MonkeyCraft 的 tailnet 电脑、经内嵌节点建立到该电脑 `9600` 端口的连接，并维持当前的 H.264、控制、聊天和 HMAC 鉴权协议不变。现有用户仍可选择 LAN 或“系统 Tailscale VPN”方式连接。Android 内嵌同样是已确认的产品目标：JNI/Kotlin桥接和ARM64/ARMv7构建已实现，API36 ARM64模拟器生命周期与通知集成通过；本人账户登录、拨号、系统VPN共存和后台恢复仍须真机验收。

官方 `libtailscale` 可把 Tailscale 编入进程并在完全 userspace 中获得 tailnet 地址；C API 可直接 `dial` tailnet 服务，Swift 的 TailscaleKit 已提供 iOS framework、节点状态和 `dial/listen` 能力。参考：[libtailscale](https://github.com/tailscale/libtailscale)、[TailscaleKit](https://github.com/tailscale/libtailscale/tree/main/swift)、[C API](https://github.com/tailscale/libtailscale/blob/main/tailscale.h)。

不在本项目范围内：复刻 Tailscale 的系统 VPN、出口节点、子网路由、局域网广播/扫描、绕过 tailnet ACL，或在 App 中内置可复用的 auth key。

## 2. 当前代码基线和总体架构

当前 [StreamProxy](../../flutter/monkeycraft/lib/stream/stream_proxy.dart) 在 `start()` 中直接执行 `WebSocketChannel.connect(wsUrl)`；其后认证、`CommandSender`、视频 relay 及重连状态均依赖这个 channel。iOS 已在 [AppDelegate.swift](../../flutter/monkeycraft/ios/Runner/AppDelegate.swift) 手工注册原生插件，Android 则在 [MainActivity.kt](../../flutter/monkeycraft/android/app/src/main/kotlin/com/chenweikeng/monkeycraft/MainActivity.kt) 创建原生插件。可以沿用这两种注册模式，不引入全局 VPN service。

推荐将网络层分为三种显式 transport：

| transport | 适用情形 | 对现有协议的影响 | 默认/回退 |
| --- | --- | --- | --- |
| `DirectWebSocketTransport` | LAN、手工填入 `ws://`/`wss://` | 现有实现 | 保持默认 |
| `SystemTailscaleTransport` | 用户已装并启用系统 Tailscale，填写 tailnet IP 或 MagicDNS | 与 Direct 相同，OS 路由负责 tailnet | 永久保留 |
| `EmbeddedTailscaleTransport` | iOS 内嵌节点 | Dart 仍连本机 loopback；原生层把流量转到 tailnet | 失败时退回前两者 |

```text
Dart StreamProxy ── ws://127.0.0.1:<随机端口> ──┐
                                                  │
                                 iOS 插件：本地 TCP ↔ TailscaleKit dial
                                                  │
                                       tailnet 的电脑:9600
                                                  │
                                    现有 Minecraft Mod WebSocket Server
```

这里的本地转发器只接受 loopback，并且每次会话随机端口及随机会话令牌；它只允许用户已选择的单个 `<tailnet host>:<port>`，不可成为通用 SOCKS/端口转发器。这样 Dart 继续使用成熟的 WebSocket client，RFC 6455 握手和帧边界不需要跨 Flutter platform channel 自行重写。若该假设在 iOS 的 `NWConnection` 桥接实验中不成立，备选方案是以原生 WebSocket 实现 transport 并用 `EventChannel` 传递文本/二进制帧；不要在尚无证据时改动全部协议层。

## 3. Flutter 共享改造（先做，不依赖内嵌库）

### 阶段 M0：抽象与不回归基线

1. 新增 `ConnectionTransport`（`open`、`close`、连接状态与结构化错误）及 `TransportFactory`；`DirectWebSocketTransport` 包装当前 `WebSocketChannel.connect`。
2. `StreamProxy` 依赖该抽象，仍将已打开的 WebSocket channel 交给 `CommandSender`。不改变 WebSocket 消息、HMAC、视频 relay、心跳或自动重连的语义。
3. 新增持久化的连接配置模型：`mode=direct|systemTailscale|embeddedTailscale`、上次电脑的稳定 node ID、显示名、端口及是否自动重连；机密状态不放入该模型。
4. 连接 UI 增加“直接/LAN”“使用已安装的 Tailscale”“内置 Tailscale”入口。内置模式不可用时展示原因和可操作的回退按钮，绝不静默降级到未知主机。

**自动化验证**：Dart unit test 覆盖 URL 解析、transport 选择、错误映射与取消；fake transport 验证 `StreamProxy` 的认证成功、认证失败、断线、三次重连、二进制帧路径未变；widget test 验证三个入口、不可用态与回退。准入标准是现有 direct/LAN 和系统 VPN 路径的所有测试及 `flutter analyze` 均通过，并至少在 LAN 真机回归一局完整游戏。

## 4. iOS 内嵌支持：实施与调试计划

### 技术选择与限制

采用官方 TailscaleKit，而不是自行将 C API 手工绑定到 Dart。它要求 Xcode 16.1+；官方提供 device、simulator 和 `ios-fat` 构建目标，其中 device framework 是面向 App Store 的版本，嵌入时必须由应用签名。[官方构建说明](https://github.com/tailscale/libtailscale/tree/main/swift)。TailscaleKit 通过 `browseToURL` 支持交互式网页登录；不得给通用客户端嵌入 auth key。

当前 Podfile 的统一最低版本是 iOS 15.5；在引入前必须在实际 Xcode/Swift 版本组合中验证 TailscaleKit 的最低部署目标和签名方式。若无法兼容，不暗中上调最低系统版本：记录影响、评估独立 C archive 绑定，再由产品明确决定。

### 阶段 I1：可复现的第三方构建与供应链

1. 固定 `libtailscale` commit、Go/Xcode 版本、构建脚本及 SHA-256；产物放在受版本控制的依赖清单或可重复构建流水线中，不把未验证的二进制混入 Runner。
2. 在 CI 生成 iOS device / simulator framework，验证 headers、签名、bitcode/架构和 release archive；同时记录产物压缩前后体积与许可证（libtailscale 为 BSD-3-Clause）。
3. 创建最小 `TailscaleTransportPlugin`，只暴露 `diagnostics`，不触达 Flutter 连接代码；确认 framework 嵌入、codesign 与真机加载。

**测试和退出条件**：CI 先执行 TailscaleKit 自带测试，再执行 MonkeyCraft `flutter analyze` 与 iOS simulator build；真机启动无 dyld/codesign 错误。任一签名、最小系统或可重复构建问题未解时，停止 I2，不以手工本地 binary 继续扩展。

### 阶段 I2：节点生命周期、登录与设备选择

1. `TailscaleNodeManager` 在 App Support（且禁止 iCloud 同步/备份）维护独立的 Tailscale state directory；私钥和状态文件由 iOS 数据保护保护。不要把节点私钥、登录 URL 或日志写到 Analytics、崩溃报告或普通 SharedPreferences。
2. App 点击“登录内置 Tailscale”后创建节点、订阅 ipn/LocalAPI 状态，收到 `browseToURL` 时使用系统浏览器或 `ASWebAuthenticationSession` 打开；原页面观察状态直到 `Running`、失败、取消或超时。登录完成不依赖 URL callback，而以节点状态为准。
3. 从 LocalAPI/netmap 读取可见 peer，显示在线状态、名称和 tailnet 地址；优先保存稳定的 Tailscale Node ID，而非可能轮换的 node key、IP 或名称，恢复时再解析。若固定版本的 API 没有暴露 Node ID，先把该限制写入 ADR，并以精确 peer identity 加用户确认恢复，不能宣称名称就是稳定身份。第一版不扫描全部端口；用户选择设备后仍以 MonkeyCraft 既有 HMAC 握手确认目标。
4. `logout` 必须关闭 node、停止 listener、删除 state directory 与内存中的已选设备；须二次确认。登录取消、ACL 拒绝、device approval、无在线电脑等情况使用不同错误码和可读提示。

**单元/集成测试**：Swift 为 state machine 注入 fake node/clock，覆盖 `idle → needsLogin → running → stopping`、重复点击、关闭时竞态、过期设备、日志脱敏和 logout 清理；Dart 为平台事件 decoder 写 unit test。以可控测试 tailnet 做集成测试，断言登录 URL 被展示、授权后 Running、可读取 peer、ACL 拒绝不被误报为密码错误。准入条件为至少两台真机、两个不同 Apple ID/网络完成首次登录与重启后恢复；模拟器只用于 UI，不作为网络可用性的依据。

### 阶段 I3：只针对 MonkeyCraft 的 loopback bridge

1. 原生 plugin 接收受验证的 Node ID 和端口，调用 TailscaleKit 的 `dial`/`OutgoingConnection` 能力建立到目标的 TCP 连接；具体 API 以 I1 固定版本的编译结果为准。
2. 在 `127.0.0.1` 的随机端口建立只服务当前会话的 TCP listener；双向桥接 listener socket 与 Tailscale connection，限制一个客户端、连接/空闲超时、最大缓冲和关闭传播。不要监听 `0.0.0.0`、不要提供任意 host 或 UDP。
3. 平台 channel 返回 loopback URL 与只用于生命周期管理的 opaque lease id；Dart 再使用 `WebSocketChannel.connect`。标准 WebSocket 客户端并不会自动发送原生层生成的“首包 nonce”，所以若安全评审要求一次性连接 token，I3 spike 必须先证明可通过 WebSocket handshake header/受控代理验证并避免泄露给远端；不能只生成一个未被验证的 nonce。bridge 断线应精确映射为“tailnet 链路失去”，由既有 `StreamProxy` 重连策略驱动，而不是伪装成认证失败。
4. App 进入后台时主动停止 bridge 或标记不可用；前台恢复先重新检查 node 状态，再新建 bridge 并重连。iOS 的暂停不可被当作持续运行保证；有关 loopback/listener 在 suspension 后状态陈旧的风险需在版本锁定时再次核验。[相关上游问题](https://github.com/tailscale/tailscale/issues/20060)

**测试**：Swift loopback bridge 测试使用本地 echo server 和 fake dial connection，验证双向字节完整性、并发拒绝、随机端口/lease 失效、目标白名单、半关闭、超时与资源释放；若实施 handshake token，再追加缺失、错误、重放和泄漏测试。集成环境使真实 Minecraft Mod 提供 `9600`，执行 auth、文本命令和二进制 H.264 帧端到端校验。Dart 回归 `StreamProxy` 的全部认证及重连测试。

**真机准入**：Wi-Fi、蜂窝、DERP 回退、Wi-Fi↔蜂窝切换、锁屏/前后台、电话/音频中断、冷启动、tailnet ACL 拒绝和远端 Mod 停止均须覆盖；每项记录连接时间、RTT、掉线原因、重连成功率、码率/FPS 与 CPU/内存。先以连续 30 分钟前台游戏和 20 次切网均无 crash/泄密/僵尸 listener 为 beta 准入阈值；性能阈值基于 M0 的 LAN 和系统 Tailscale 对照结果制定，不能凭主观“可用”放行。

### 阶段 I4：发布、合规与逐步开放

1. 构建 TestFlight archive，检查 App Store 上传、framework 签名、崩溃符号和体积变化；外测前完成真实设备矩阵。
2. 当前 `Info.plist` 和 `doc/APP_ENCRYPTION_DOCUMENTATION.md` 声明不使用非豁免加密；嵌入 WireGuard/Tailscale 后必须在每次发布前由负责人员重新填写 App Store Connect 的出口合规问卷并留存结论，必要时提交文档。不能沿用现有 `false`。Apple 的出口合规要求覆盖 app 使用或访问加密的情形。[Apple 说明](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
3. 更新隐私政策、第三方许可证、支持文档与故障诊断指引；说明创建的是 MonkeyCraft 自己的 tailnet 节点，用户仍需 Tailscale 账号、受其 ACL/device approval 约束。
4. 按各平台实际验收结果安排 beta；出现 node 无法启动、连续桥接崩溃、重大性能回归或合规未确认时立即关闭内嵌入口，direct 和系统 VPN 不受影响。

## 5. Android：已实现路径与剩余验收

已采用与iOS相同pin的libtailscale C shared library + JNI。当前构建方式见[Android构建说明](../../flutter/monkeycraft/android/third_party/libtailscale/README.md)，自动化和真实设备的证据边界见[App本轮记录](evidence/2026-09-19-app.md)。以下复核项是进入beta/发布的验证要求，不再是是否实施Android内嵌的产品选择。

### 已知条件

当前 Android 项目只声明网络、唤醒锁、通知及闹钟权限，未声明 `VpnService`；这与“仅 MonkeyCraft 进程内流量”的目标一致。官方 Android client 的源码公开且包含 Go/Kotlin 和 `gomobile` 绑定流程，但其产品本身是完整 Android VPN client，不应直接复制为 MonkeyCraft 的依赖方案。[tailscale-android](https://github.com/tailscale/tailscale-android)。

更关键的是，上游仍有公开的 `tsnet` AAR 风险：以 `gomobile bind` 构建的库在 Android 上 `Server.Start` 可因 `netlinkrib: permission denied` 失败，问题记录为 open，涉及 Android 16 和 tsnet 1.88.2，报告者依赖 Go runtime patch 才可绕过。[Issue #17311](https://github.com/tailscale/tailscale/issues/17311)。因此 Android 不能以“iOS POC 成功”推出可发布结论。

### 复核包交付物

实施与验收在**固定的** Tailscale commit、Go 版本、Android Gradle Plugin、NDK 与设备矩阵下给出以下证据，而不是仅给设计建议：

1. 方案对比：`libtailscale` C archive + JNI、从官方 Android client 最小化/改造的 Go backend、纯 `tsnet` AAR；逐项说明是否需要 `VpnService`、是否仅 proxy 单端口、升级路径、许可证、构建可复现性及维护成本。
2. 最小 repro：`gomobile`/JNI library 在 arm64-v8a 和 armeabi-v7a，Android API 29 至当前 target 的真机上完成 `Start → interactive auth → dial TCP → close`；附完整未脱敏的技术日志给开发组，向产品文档只提供脱敏摘要。
3. 上游风险审计：重新检查 #17311 状态、相关修复 commit 是否进入所固定版本、是否仍需 Go patch；若 patch 必需，给出最小 diff、维护人、CI rebase 验证与撤销方案。
4. 网络与生命周期测试：Wi-Fi/蜂窝切换、Doze、进后台/回前台、进程被杀、双 VPN/企业设备策略、IPv4/IPv6、DERP、ACL/device approval；确认不劫持其他 app 流量。
5. 安全与商店审查：密钥/state 存放、JNI 边界内存安全、日志脱敏、native crash 符号、APK/AAB 体积、依赖 SBOM、Google Play Data safety 与加密合规结论。

### Go / No-Go 门槛

**Go（仅进入受限 Android beta）**：固定版本的真机 repro 不需要私有 Go runtime patch；两个 ABI 均可稳定启动和退出；tailnet 登录、单端口 dial、前后台恢复及现有 direct/system-VPN 回退通过；没有系统 VPN permission 或流量劫持；构建/许可/安全审查完整；Android 负责人和前沿模型的独立复核结论一致。

**暂缓该平台内嵌发布（继续修复并保留系统 Tailscale VPN）**：上游 bug 仍未解决且只能靠未维护 patch；任一目标 ABI/API 无法稳定启动；需要改造成完整 `VpnService` 才能运作；无法保证状态与私钥保护；或性能/体积/商店风险超过团队明确阈值。No-Go 不是项目失败：用户仍可安装 Tailscale App 并使用现有 `100.x`/MagicDNS 路径，LAN 也完全不变。

## 6. 统一安全、可观测性和验收清单

- 永不把 reusable auth key、OAuth client secret、节点私钥、session nonce、WebSocket 密码或完整登录 URL 写入 Flutter bundle、日志、分析平台或截图。
- 设备列表只用于用户选择；不枚举、扫描或探测 Tailnet 中每台机器的端口。Tailscale ACL 仍是网络授权，MonkeyCraft HMAC 仍是应用授权，两者都保留。
- 保留“断开内置 Tailscale”“忘记此设备”“退出并删除节点数据”，并在 UI 明确两者的差别。
- 每个 transport 记录最小化、脱敏的诊断：模式、状态机阶段、错误类别、耗时、是否经 relay；不记录 host/IP 的完整值或 token。支持页面允许用户显式导出已脱敏报告。
- 发布前以同一组脚本执行：Dart unit/widget、iOS Swift unit、原生 bridge integration、真实 Mod E2E、真机网络矩阵、内存/CPU/体积对比、商店 archive 验证和回退演练。

## 7. 里程碑决策

| 里程碑 | 可交付物 | 决策 |
| --- | --- | --- |
| M0 | transport 抽象，不改变网络行为 | 仅在 direct/system VPN 全量回归通过后合入 |
| I1 | 可重复、可签名的 iOS framework 与空插件 | 不通过则不开始节点功能 |
| I2 | 真机交互登录、状态、设备选择 | 不通过则保留系统 Tailscale 路径 |
| I3 | 真实 Mod 的单端口 loopback bridge | 不通过则不改 WebSocket 协议 |
| I4 | TestFlight 灰度、合规与回退开关 | 仅 iOS beta/正式发布 |
| A-R | Android 复核包和独立结论 | 实现已进行；满足Go条件后才进入beta |

本文件是实施和测试计划；PC、iOS和Android内嵌是已确认目标，构建通过不等于已具备发布条件。每个阶段完成后都必须以实际产物和测试记录更新结论。
