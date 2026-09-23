# 历史矩阵快照：不作为待执行清单

2026-09-23按用户要求简化前留档。当前范围与结论以[现行矩阵](../TEST_MATRIX.md)为准；本快照中的旧待验项、重复版本测试和探索性清单不自动恢复为任务。以下保留原文，原相对链接基于上级目录。

# 内嵌 Tailscale 联合测试与发布矩阵

## 2026-09-23 最新增量：iPhone Safari提示音验收完成

26.2 JAR `19ea7e9b` / Web JS `32617edb`已部署、重启进服并核对HTTPS资源。Chrome自动化33项、analyze、Web Release、26.2 JUnit66项通过。用户完整刷新后确认：连接和画面正常、Test sound可听、连续两次锁屏返回新提醒可见可听、静音不响、相同提醒去重、关闭Reminder sounds后有声类型提醒仍不响。证据见[本轮真机记录](evidence/2026-09-23-iphone-safari.md)。

按用户要求，本部分验收到此结束，不再追加测试，除非静态检查发现具体且重要的风险。关闭声音跨后台未实测，普通Safari锁屏期间准时投递不在承诺范围。旧候选26bc49dd的一次失声记录保留；下文旧日期的“待复验”由本节在该分项内更新，不将旧自动化结果迁移到新包。其余三个Mod/Pages尚未同步本次Web资源；原生App园区音频仍独立待验。

## 2026-09-21 最新增量（下面旧表按原包保留）

| 范围 | 本轮结果 | 尚未替代的门槛 |
|---|---|---|
| 共享Flutter | 232 VM/widget、analyze、28 Chrome通过 | 实际手机声音/系统后台 |
| 26.2 + IMF | 最终8aaaf7实际启动与原生音频交接，保持PC原意图/音量 | 物理手机正常GUI；异常退出与PC重启 |
| 26.1 / 1.21.11 | 最终c2f7664c / e0df7343真实60秒核心回归，467/550新帧、0错误 | 各自节点授权、远端/混合网络 |
| 1.19 | 最终b42beea2在MCParks七项核心回归通过，60秒487新帧；Android正式包音频Home/熄屏返回、单曲停止、Refresh与断开通过 | 失焦自动暂停前提单列；未覆盖实际手机听感/各版内嵌授权 |
| 原生最终包 | Android906884a7签名/ZIP/ARM64对齐，iOS Runner0c9549f0嵌套平台/签名通过 | 新iOS未安装；Android物理设备/账户授权 |
| Pages | 99文件普通副本232+28、6 provenance、Release及本地路径E2E通过 | 无头系统通知跳过；未公开发布；精确范围授权 |
| helper | Go/race、五平台构建、3 JDK harness通过 | Windows/Linux原生联网、真实DERP/撤销/切网 |

精确产物、命令、异常与证据见 [自主收尾记录](evidence/2026-09-21-closeout.md)。目前没有“全平台可正式发布”的结论。

## 之前批次（历史）

2026-09-21 Android 自主验收更新：正式最终 APK `23c543a3…`，26.2 Mod `33235b10…`。已修复并实测库存 E 积压／ESC重开与原生即时提醒重复投递；保留数据升级、旋转、4000重连、按键释放、权限拒绝/允许、精确闹钟入口、Doze到点及恢复不重发通过。Flutter 229、Chrome 28、Android JVM 11、四 Mod JUnit 66/61/61/61通过。模拟器系统投递不等于真机听感或本人内嵌授权；详见[本轮证据](evidence/2026-09-21-android-acceptance.md)。下方条目保留历史版本边界。

> 2026-09-18：本文件包含早期实施建议与历史阶段编号；产品优先级以 [产品路线](../PRODUCT_ROADMAP_2026-09.md) 为准，当前证据见 [执行记录](../PRODUCT_ROADMAP_EXECUTION.md)。Flutter iOS / Android / Web 均是长期正式产品线；独立 TypeScript / Preact `web/` 保留参考与测试资产，不再作为待发布浏览器客户端。移动双端内嵌是已确认目标，Android 技术门槛不是取消产品目标。当前浏览器正式路径为 LAN/系统 Tailscale；WASM 属于 P4 候选探索，未经选择不自动产品化。

2026-09-19 追加：iPhone Safari 已实测配对并进入休眠界面；重复倒计时已修复，26.2本地运行包现为 `bc6f919f…` / Web `60cbdf20…`。13项Flutter定向测试、analyze、66项JUnit及Chromium窄屏前后对照通过，手机已刷新，并确认测试休眠无重复倒计时；以下 `ee2dbc…` 等完整回归保留为各自旧包记录。见[专项证据](evidence/2026-09-19-hibernation-countdown.md)。

最新26.2本地包已更新为 `a56d2814…` / Web `ca4d7352…`：处理iPhone Safari返回后提示音实例失效，15项Chrome定向测试和4项真实AudioContext/合成生命周期E2E通过、analyze通过；新包手机听感待复测。前一包真实手机的显示去重通过，但返回后NUDGE与Test sound无声是实际失败，详见[声音恢复证据](evidence/2026-09-19-ios-safari-sound-resume.md)。

## 当前验证状态（2026-09-19）

| 路径 | 本轮证据 | 未完成项 |
|---|---|---|
| 26.2 Mod | 当前 overlay 包`ee2dbc28`已正常部署、重启并回到原服务器；JAR 的49个 Web 资源与 Flutter root 逐字节一致，HTTPS 取回的关键资源也一致，`main.dart.js`为`57a79829…`。真实 collision 已验证：到期后82ms普通 NUDGE 与随后 ImagineMoreFun NUDGE 均未覆盖提醒，精确可见下界2634ms，decoded=190/errors=0；完整 timer 生命周期亦通过，decoded=308/errors=0；Chrome核心120秒回归8个15秒样本新增969帧/解码错误0，受控断线后的socket=2且无额外重连。Safari真实HTTPS/WSS也通过认证、三次resize、E/ESC、Shift成对释放、完整timer生命周期与前台Pointer Lock，最终decoded=609/errors=0；原生AX点击用于绕过JS语义点击未建socket的自动化差异，Pointer Lock由WebDriver W3C鼠标动作完成。Safari前台有声NUDGE计数从8到9，重复不再增加；此为调用及去重证据。此前`471ff457`倒计时包及`0f0bc8f6` Chrome600秒/4878新帧/0错误结果均保留各自版本边界；新包追加验收见[实时证据](evidence/2026-09-19-flutter-live-26-2.md)。内嵌节点身份保持。 | 本轮追加用户验收：前台两条相同NUDGE只显示/响一次；后台无声由系统日志定位为displayShared共享静音，停止看屏后13有声、14静音、15两份相同NUDGE去重均经用户与系统日志确认通过；后台状态依据用户明确最小化，未直接采样document.hidden。Linux原生x86/联网、Windows、强制中继与跨网络待验 |
| iOS正式原生 | 原369feb4e包实体iPhone已确认静音/有声、倒计时更新取消、锁屏到点一次与游戏自动恢复；园区音频锁屏可听，但回前台中断（失败）。26.5模拟器经LAN真连26.2复现，定位No Sleep保活视频触发detached音轨暂停；单变量对照及修复包锁屏71秒/Home44秒返回无音轨pause、断开后不复活通过。11项JS、12项Dart音频测试及analyze通过；新正常设备Release clean构建50.6秒、逐嵌套验证通过，Runner`06c2a363…`/App`988e6554…`，未安装。见[音频证据](evidence/2026-09-19-ios-audio-resume.md)。 | 修复仍待iOS26.6.2真机可听/锁屏返回最小复验；模拟器引擎状态不替代真机听感。PC/手机自动音频交接未实现，本轮临时隔离不算修复；跨网、冷启动和长时表现待验。后台到点无更新时Live Activity可能保留00:00，见[边界](evidence/2026-09-19-expired-reminder.md)。 |
| iPhone登录页 | 本轮真实注册200；节点34ms、系统open约5.125s，用户约8s；本人授权完成 | 旧30秒真机样本未留阶段日志；切网与冷启动对照待验 |
| Android | 当前4f5a225正式包双ABI/16KB/签名通过，Flutter192项/analyze；当前overlay源码的Release APK`39218eaa…`（83,686,326字节）含双ABI Tailscale库，个人签名、v2和16KiB对齐验证通过，并以`adb install -r`保留数据安装到Android 16/API36 arm64 AVD。该AVD直连真实26.2；通知许可、静音NUDGE通知栏投递、timer A→B单alarm/取消/到期投递、通知栏暂停流后同一MainActivity恢复、4000受控断线恢复和Sneak释放均通过。硬件E打开InventoryScreen，但后续自动化硬件E/ESC未关闭，属部分通过。 | AVD已关闭且未清数据；无可听声音结论，非物理设备。未登录或授权Tailscale；OEM后台策略、连续播放、VPN共存、身份恢复、混合连接与ARMv7实机待验；5554等待本人授权，5556已关闭 |
| 浏览器 | Flutter共享实现：224项VM/widget、analyze通过；含 overlay 修复的73文件候选在普通 archive 中逐文件 SHA 匹配，204项VM/widget（含5项 overlay）与24项真实Chrome通过。当前 overlay 包的真实 collision 与完整 timer 生命周期通过，前者仅证明至少2634ms可见、后者至少2秒可见；Chrome核心120秒8个区间新增969帧/错误0，认证、resize、E/ESC、Shift blur、刷新与4000关闭恢复通过。Safari真实26.2通过认证、三次resize、E/ESC、Shift成对释放、前台Pointer Lock、静音横幅及A→B/取消/到期后至少2秒；有声NUDGE调用使tones8→9，重复不增加。最初五帧截图仍是旧世界，后续截图与MCP才确认InventoryScreen。候选Pages Release另以`/monkeycraft/` loopback静态入口和录像夹具E2E通过，未连接Minecraft。真实26.2 Chrome旧包600秒通过，历史包结果不迁移到当前 overlay 包。 | loopback E2E的无头鼠标锁定和OS通知权限均受环境限制，不能当作前台或系统验收；Safari追加实际前台听感/去重通过；后台无声已定位为displayShared共享静音。停止看屏后的13–15实际有声、静音与去重均通过，系统日志与用户听感一致。iOS Safari与Android真机、公开Pages E2E仍待验。 |
| 26.1 | 当前 overlay JAR`660d0a50`构建、61项JUnit（0 failed/error/skipped）及49资源逐字节核对通过；已在真实ImagineFun完成错误密码、真实H.264、四次resize、E/ESC、Shift blur释放、刷新、受控断线恢复及60秒回归（121/120/133/147帧、0解码错误），随后正常退出并恢复运行26.2。历史独立Web与真实ImagineFun验收结果保留，见[运行证据](evidence/2026-09-19-26-1-runtime.md)。 | helper本人授权未确认、未测远端转发/混合连接；非物理切网或真实手机验收；请求20FPS而实达约10–11FPS |
| 1.21.11 | 当前 overlay JAR`0063d289`构建、61项JUnit（0 failed/error/skipped）及49资源逐字节核对通过；在真实ImagineFun完成七项检查、60秒四样本562新帧、`errors=[]`、0 decoder错误，随后恢复26.2。历史独立Web与十分钟结果保留，见[证据](evidence/2026-09-19-1-21-11-runtime.md)。 | helper本人授权/跨设备/联网长时待验 |
| 1.19 | 当前 overlay JAR`52fa89f6`构建、61项JUnit（0 failed/error/skipped）及49资源逐字节核对通过；在独立测试世界完成七项检查、60秒四样本479新帧、`errors=[]`、0 decoder错误，随后恢复26.2。历史独立Web与独立世界十分钟结果保留，见[证据](evidence/2026-09-19-1-19-runtime.md)。 | helper本人授权/跨设备/联网长时待验；ImagineFun要求1.21+，不接受1.19 |
| 托管入口 | `ace51c9`已推送但未部署，线上仍旧Flutter。Pages工作流已改为共享Flutter；73文件 overlay 候选在普通 archive 中仅应用补丁后，通过依赖锁、analyze、204VM/widget（含5 overlay）、24Chrome、Pages Release与完整性校验；当前 overlay 包Chrome核心120秒真实回归也已通过。 | 未新commit/push/dispatch/deploy；桌面Safari OS通知与可听声音已实际通过；公开Pages入口和移动浏览器仍待验。候选共享Dart范围的发布授权问答仍待回复，须与既有排除原生App/Mod/helper的范围核对；无需域名。 |

PC helper另有[Linux生产后端离线容器证据](evidence/2026-09-19-linux-helper-real-backend-container.md)：amd64二进制在arm64 Docker翻译执行下，初始化/needsLogin/status/stop/EOF通过；不代表原生x86、联网转发或Windows。

详细命令、产物及失败过程见[执行记录](../PRODUCT_ROADMAP_EXECUTION.md)。后面的测试矩阵为目标验收要求，不能理解为全部已经完成。

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
- Android产品测试：固定commit/toolchain生成libtailscale C shared/JNI库，在目标ABI/API矩阵验证`Start → login → dial → close`；已建立API36 ARM64离线原生集成，真实登录、拨号和系统VPN共存仍为发布门槛。

### 3.4 Web/WASM

- Go/WASM unit：登录/IPN 状态转换、peer 映射、dial/read/write/close、WebSocket framing、背压、最大 frame 和取消。
- Flutter/Dart Web unit：浏览器薄适配层、弹窗或权限被阻止、刷新恢复、浏览器存储隔离、设备选择、错误与回退；独立 TypeScript fixture 仅在迁移行为核对时参考。
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
| Android | 双ABI原生构建、Flutter与API36 ARM64模拟器原生集成 | arm64-v8a必测，armeabi-v7a当前仅构建证据 | 原生实现已完成首轮；账户与真机验收待完成 |
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

## 2026-09-19 最终浏览器与四版本资源更新

Android Chrome133/API36是实际浏览器进程但仍属模拟器。静音/非静音系统通知标记、原生通知点击回游戏、Home释放SHIFT、真实旋转与后台30秒不耗重试通过；无音频输出，不把silent=false当作已听到声音。当前浏览器后台socket会断开，恢复前台重连已修，不承诺页面关闭后的实时提醒。

该早期批次四JAR嵌入11个Web资源，校验见[当时清单](evidence/2026-09-19-browser-mod-artifacts.json)；当时26.2的6fabc1包已实际重启并保留内嵌身份，其他三版本仅构建/自动化。后续1.21.11/1.19已有真实运行与十分钟结果，以本页顶部当前状态为准。queued-shutdown测试修正了fixture竞态，四树62/57/57/57项均实际重跑通过。首次失败与修复前构建保留，未覆盖历史证据。


## Flutter 共用浏览器实现（2026-09-19，替代待发布独立客户端）

| 范围 | 本轮结果 | 尚未覆盖 |
| --- | --- | --- |
| Dart / widget | 主checkout219通过，analyze无问题；独立Pages候选199通过 | 不代表原生设备行为 |
| Chrome 定向 | 23 通过，含实际录制 H.264 | OS 声音与手机后台 |
| Flutter release UI / Chrome | 回放登录、视频、resize、拖动、释放、ESC、提醒、倒计时、重连、刷新身份和目标隔离通过 | Pointer Lock 实际捕获、系统通知权限/投递、实时游戏 |
| 桌面 Safari 26.6.2 | 当前`ee2dbc…`在真实HTTPS/WSS认证、连续解码、三次resize、E/ESC、Shift成对释放、timer生命周期与前台Pointer Lock通过，最终609解码/0错误；JS语义Connect点击未建socket后，以原生AX点击实际登录。Pointer Lock由WebDriver W3C鼠标动作取得，未发送CLICK，仅发送一个LOOK_DELTA；坐标CUA会遇自动化玻璃保护提示。前台有声NUDGE使tones8→9、重复不增。最初五新帧截图不作背包视觉证据，后续截图与MCP均确认InventoryScreen。 | 本轮用户已确认前台可听/去重与后台有声、静音、去重。此前无声由displayShared系统共享抑制解释，无看屏13–15对照通过；用户随后确认返回前台画面自动恢复、无需登录，见[听感证据](evidence/2026-09-19-safari-reminder-audibility.md)。document.hidden未直接采样，后台依据用户最小化；实体移动浏览器仍待验 |
| iOS Safari / Android Chrome | iPhone Safari已完成HTTPS入口、配对和休眠界面实际显示；发现倒计时重复，修复包已刷新，真实手机确认休眠显示不再重复。Android真机浏览器未验。 | 最初ride到点声音来源未确认；后续手机Test sound、前台静音NUDGE和有声NUDGE（响一次）已人工通过。返回Safari自动恢复画面、无需重新登录已实际通过（后台时长未采样）；手机显示去重已通过，但返回后提示音无声；音频恢复修复包待真机复测，锁屏仍待验；当前无Web Push，不承诺iOS后台准时提醒。历史独立网页结果不迁移记分 |
| Pages / Mod 资源 | 完整 Flutter 构建、49资源校验及四版JAR逐资源比对通过；26.2共66 tests，其他各61 tests通过 | 真实运行入口及公开部署验收 |

前期回放边界见[Flutter浏览器运行证据](evidence/2026-09-19-flutter-browser-runtime.md)。用户随后已交出26.2并授权必要重启，当前以[真实26.2追加记录](evidence/2026-09-19-flutter-live-26-2.md)为准，勿将前期未部署状态当作现状。

共享代码原生构建：Android Release APK`39218eaa…`双ABI、个人签名、v2和16KiB验证通过，并在Android 16 AVD以`install -r`保留数据完成真实26.2直连、通知与受控恢复；它不是实体设备听感或Tailscale验收。debug APK证据保留。iOS首次直接构建的Simulator平台嵌套framework验证失败并已保留，随后清洁设备Release wrapper逐嵌套验证通过；最新有效包尚未安装，物理机不可发现。详见 [原生编译证据](evidence/2026-09-19-flutter-native-regression.md)。

HTTP生命周期与前期四版打包见[Mod打包证据](evidence/2026-09-19-flutter-mod-packaging.md)。当前共享Flutter包26.2已实际部署；三个旧版当前更新包均完成短时真实运行并恢复26.2，49资源一致；历史旧客户端实时证据不转算。


2026-09-21 Android补充：最终原生APK 23c543a3连续611秒/18次采样保持连接，系统视频实例5904输入帧，应用错误日志为空。Android Chrome133默认模拟器GPU发生实际失败；同AVD显式SwiftShader对照1290解码/0错误，旋转、保存身份、Home后恢复及输入释放、静音系统通知通过，有声只到API调用/选项证据。不能将软件环境结果计为默认图形环境或实体Android手机通过。见[当日完整证据](evidence/2026-09-21-android-acceptance.md)。
