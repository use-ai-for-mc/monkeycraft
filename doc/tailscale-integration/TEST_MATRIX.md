# 内嵌 Tailscale 联合测试与发布矩阵

## 1. 原则

本矩阵把“代码能编译”“能登录一次”和“可发布”分开。普通 PR CI 不应依赖个人 Tailscale 账号、公共控制面的稳定性或长期 secret；真实 tailnet、DERP 和商店签名测试在受控集成环境、nightly 或人工发布门槛中执行，并保存脱敏证据。

任何性能结论都要与同设备、同版本、同视频设置的 LAN 和系统 Tailscale 基线比较。浏览器 DERP-only、iOS userspace bridge 和电脑 helper 的数据不能互相替代。

## 2. 测试层级

| 层级 | 环境 | 必测内容 | 失败影响 |
| --- | --- | --- | --- |
| L0 纯单元 | 无网络、fake clock/state/store/socket | 状态机、配置校验、错误映射、脱敏、退避、协议编码 | PR 阻断 |
| L1 进程/组件契约 | fake helper、echo server、fake native node、mock Worker | JSON Lines、半关闭、取消、超时、重启、版本不匹配、资源释放 | PR 阻断 |
| L2 本机集成 | standalone helper+测试 control/DERP，或本地 WASM/native harness | 登录事件、持久状态、listen/dial、loopback、WebSocket 字节完整性 | 合并相关功能前阻断 |
| L3 真实 tailnet E2E | 独立测试账号、两节点、真实 Mod 和 App/浏览器 | 官方登录、审批、ACL、HMAC、命令、聊天、H.264、重连 | beta 阻断 |
| L4 平台与网络 | 真机/真实 OS、Wi-Fi/蜂窝/relay/休眠 | 生命周期、性能、签名、杀进程、升级、恢复 | 平台发布阻断 |
| L5 分发验收 | 从最终 JAR/IPA/AAB/Web 部署安装 | 无 SDK 前置、产物 hash、架构、许可证、回滚/kill switch | 正式发布阻断 |

### 2.1 可重复的测试控制面

P1 先建立最小 hermetic harness：两个 userspace 节点、测试 control server、测试 DERP/relay 和 TCP echo/WebSocket fixture。它用于覆盖协议和故障，不宣称等同生产 Tailscale。每个 beta 仍须经过公共服务上的独立真实账号 E2E。

测试 fixture 不使用开发者个人 tailnet；CI secret 只在受保护 job 可见，日志和 artifact 必须通过机密扫描。测试结束删除临时节点或使用可验证的短生命周期身份。

## 3. 自动化套件分工

### 3.1 电脑 helper

- Go unit：配置、state dir、结构化 IPN 事件转换、错误分类、转发 copy loop、半关闭、连接上限、退避和脱敏。
- Golden protocol：合法/未知命令、乱序 request、超长行、无效 JSON、旧/新 protocol version、stdout 污染、stderr 日志。
- Process integration：首次登录、取消、超时、持久节点重启、`logout` 清理、父进程退出、重复启动锁、helper crash 和 corrupt state。
- Listener E2E：tailnet 客户端到 helper `:9600`，再到本地 echo/MonkeyCraft 服务；至少分别强制 direct 和 DERP 路径。
- Distribution：每个支持 OS/arch 从 JAR 解包并启动，核对 manifest/hash/执行权限；机器不预装 Go 或 Tailscale。

### 3.2 Java Mod

- 四棵 Mod 树都执行现有 Gradle tests；新增 extractor、manifest、IPC decoder、lifecycle、UI state 和端口策略的 unit tests。
- fake helper fixture 可脚本化 `authRequired → running → listening`、malformed stdout、timeout、crash、旧协议和权限错误；Java 测试不访问真实 Tailscale。
- 先在 26.2 完成一条真实手机 E2E，再同步 26.1、1.21.11、1.19；同步检查比较共享文件/协议常量，避免四份实现漂移。
- Minecraft UI 人工测试包括首次打开页面、复制/打开登录 URL、等待审批、取消、重试、登出、退出游戏、崩溃恢复和与系统 Tailscale 共存。

### 3.3 Flutter/iOS/Android

- Dart unit/widget：transport 选择、direct 不回归、平台事件、设备列表、错误提示、取消和回退。
- Swift unit：node state machine、存储、登录 URL 处理、peer 解析、bridge 的单目标/单客户端、缓冲/超时/关闭；通过 fake node 和 echo server 完成。
- iOS 真机：framework 签名加载、首次登录、重启恢复、Wi-Fi/蜂窝切换、前后台/锁屏、TestFlight archive、CPU/内存/发热和视频指标。
- Android 调研 job：固定 commit/toolchain 生成最小 AAR/JNI repro，在真实 ABI/API 矩阵验证 `Start → login → dial → close`；只有通过 `MOBILE.md` 的 Go 门槛才建立产品测试套件。

### 3.4 Web/WASM

- Go/WASM unit：登录/IPN 状态转换、peer 映射、dial/read/write/close、WebSocket framing、背压、最大 frame 和取消。
- TypeScript/Dart web unit：Worker RPC、弹窗被阻止、刷新恢复、IndexedDB 版本迁移、设备选择、错误与回退。
- 浏览器 E2E：首次登录、回到原标签页、设备审批、ACL 拒绝、刷新/多标签页/清站点数据、tab 隐藏、WASM 加载失败、离线缓存更新。
- 协议 E2E：真实 Mod 的 HMAC、文本/二进制 WebSocket、H.264 分辨率 header、持续帧、控制输入和断线重连。
- 性能：WASM 下载/解压/初始化、Worker CPU/内存、DERP RTT/吞吐、首帧、有效 FPS、码率、丢帧和连续会话；未达到书面门槛不得以“实验成功”替代发布结论。

## 4. 支持矩阵

最低系统版本和浏览器版本必须由 P0/P1 的实际构建结果写入 release manifest；下表不提前虚构版本下限。

### 4.1 电脑与 Minecraft

| 维度 | 必测项 | 说明 |
| --- | --- | --- |
| macOS | Apple Silicon、Intel；最低支持版本 TBD | universal 单文件或分架构文件须在 manifest 明确 |
| Windows | x86_64；Windows on ARM 策略 TBD | 测试 Defender/SmartScreen、只读/含空格路径 |
| Linux | x86_64；arm64 是否发布由证据决定 | 测试无桌面环境、`noexec` 配置目录和执行权限 |
| Minecraft | 26.2、26.1、1.21.11、1.19 | 分别使用 Java 25、25、21、17 目标要求 |
| 共存 | 无系统 Tailscale、系统 Tailscale 已运行、系统代理/防火墙 | 内嵌节点不得依赖或破坏系统 daemon |

### 4.2 手机

| 平台 | 自动化 | 真机覆盖 | 发布状态 |
| --- | --- | --- | --- |
| iOS | Dart+Swift unit、simulator build、archive check | 至少两代设备；Wi-Fi/蜂窝/前后台/TestFlight | I1-I4 逐级准入 |
| Android | 最小 native repro 和 existing Flutter regression | arm64-v8a 必测；其他 ABI/API 由复核定义 | 先调研，不预先承诺 |
| 现有系统 VPN | Flutter direct transport 全量回归 | iOS/Android 各至少一台 | 永久保留 |

### 4.3 浏览器

| 平台 | 必测浏览器 | 重点 |
| --- | --- | --- |
| macOS | Safari、Chrome、Firefox | Worker/WASM、弹窗、IndexedDB、内存 |
| Windows | Edge、Chrome、Firefox | WASM、企业策略/防火墙、长连接 |
| iOS/iPadOS | Safari | 内存上限、后台 tab、触控和视频解码 |
| Android | Chrome | 内存、切网、后台 tab |

网页正式支持矩阵以实际 CI provider 和真机证据为准；无法自动化的 Safari/iOS 项目写入每次 release checklist。

## 5. 网络与会话场景

每个已承诺的平台至少覆盖：

| 类别 | 场景 |
| --- | --- |
| 路径 | LAN direct、系统 Tailscale、内嵌 direct（能形成时）、强制 DERP/relay |
| 网络变化 | Wi-Fi 断开/恢复、Wi-Fi↔蜂窝、NAT 变化、IPv4/IPv6、代理/防火墙 |
| 质量 | RTT 20/100/250 ms，丢包/抖动/限速阶梯，突发拥塞 |
| 生命周期 | Mod/App/tab 正常关闭、强杀、电脑睡眠、手机锁屏、浏览器刷新、OS 重启 |
| 账号 | 首次登录、取消、URL 过期、管理员审批、ACL deny、Tailnet Lock、logout、节点过期 |
| MonkeyCraft | 密码错误、已有手机占用、端口改变、Mod 停止、错误分辨率帧、20 FPS 上限 |

网络仿真数据与真实家庭 Wi-Fi/移动网络各保留一份；结果记录路由类型、客户端/服务端版本、机器、时长和失败原因。

## 6. 故障注入清单

### 6.1 产物与进程

- helper 缺失、hash 不匹配、截断、旧版本、错误架构、不可执行、被安全软件隔离；
- state dir 不可写、磁盘满、状态损坏、两个 Minecraft 实例争用同一 identity；
- helper 启动超时、握手前退出、stdout 混入日志、消息过大、快速崩溃循环、停止卡住；
- Java/Minecraft 崩溃后 helper 是否退出，下一次启动是否能安全恢复。

### 6.2 登录与控制面

- 浏览器无法打开、弹窗被拦截、用户关闭页面、登录 URL 过期；
- 登录成功但设备待审批、ACL 拒绝、节点过期、Tailnet Lock 未签名；
- 控制面短暂不可达但数据面仍可用，以及数据面断开后的重连差异；
- 登出过程中连接仍活跃、删除 state 失败、旧登录回调晚到。

### 6.3 数据面

- local `9600` 未监听、端口配置错误、半关闭、读写一侧卡住、慢消费者、超过 buffer；
- 多个客户端同时竞争、错误 peer、远端 HMAC 失败、远端中途退出；
- DERP 迁移、重连期间重复输入、视频帧截断/合并、背压导致内存增长。

## 7. 性能和稳定性基线

P0 在同一手机、电脑和 Minecraft 场景记录 LAN 与现有系统 Tailscale：登录到首个 H.264 帧、RTT、平均/95p 帧间隔、有效 FPS、码率、CPU、RSS/内存、耗电和 30 分钟重连次数。后续各内嵌方案都用同一脚本和场景对照。

beta 的初始稳定性检查至少包括：

- 30 分钟连续游戏，无 crash、僵尸 helper/listener、无界内存增长或机密日志；
- 20 次进程/连接重启和 20 次网络切换，记录成功率和恢复时间；
- 10 次首次登录/取消/登出清理循环；
- 浏览器分别在直接 relay 条件和受限带宽下测量，不能用 native direct 结果代替。

具体 FPS、时延、CPU、内存和包体阈值在 P0 基线得到后由负责人签入 ADR；本计划不凭空给出看似精确的产品阈值。

## 8. 安全、隐私和供应链验证

- Secret scan 覆盖 auth URL、auth key、OAuth secret、node/private key、MonkeyCraft credential 和 session token；测试日志只保留脱敏值。
- ACL allow/deny 与 MonkeyCraft HMAC allow/deny 做四象限测试，证明两层独立生效。
- 本地 bridge 验证只绑定 loopback、目标和端口白名单、单客户端、关闭清理；电脑 helper 验证不启用 Funnel/exit node/任意代理。
- 明确验证 Tailscale 诊断/日志上传的默认行为和可配置项，把隐私决策写入 ADR 与用户说明。
- 二进制重建后比对 hash/可重复性；生成 SBOM、第三方许可证清单、来源 commit、代码签名与平台架构信息。
- iOS/App Store、Android/Play 和各桌面平台分别完成加密出口、隐私、codesign/notarization/安全软件影响评估；这些是人工门槛，不用“CI 绿”替代。
- Web 设置 CSP、Worker/WASM hash、依赖锁、缓存版本和回滚测试；不得从未固定的第三方 CDN 动态加载核心 WASM。

## 9. 每阶段证据包

每个阶段在 `doc/tailscale-integration/evidence/<milestone>/` 或外部受控 artifact 中保存下列索引；机密原始日志不进入 Git：

1. 上游 commit、工具链、构建命令、产物 manifest/hash/SBOM；
2. 自动化测试报告和失败重试记录；
3. 真实设备/OS/浏览器/网络矩阵及未覆盖项；
4. 脱敏登录、设备选择、HMAC、视频 E2E 结果；
5. 性能与 M0 基线对比；
6. 已知问题、风险接受人、kill switch 和回滚演练；
7. 安全、隐私、许可证、商店/分发审批结论；
8. 明确的 Go/No-Go 决策和下一阶段 owner。

## 10. 发布门槛

平台发布负责人只在以下项目全部满足后签字：

- 最终安装包在干净环境运行，用户无需安装 Tailscale/编译器/SDK；
- direct 和 system-Tailscale 回归全绿；内嵌失败提示和回退实测有效；
- 真实 tailnet 的首次登录、审批、ACL、HMAC、聊天/控制/H.264 和断线恢复通过；
- 目标 OS/arch/浏览器矩阵与最低版本已写入发布说明；
- 无 P0/P1 安全问题、无机密日志、无已知 crash loop/僵尸进程/无界内存增长；
- hash、签名、SBOM、许可证、隐私与加密出口结论齐全；
- kill switch 和上一稳定版本回滚已演练；
- Android 若未达到 Go 门槛，产品只显示系统 Tailscale 模式，不暴露半成品入口。
