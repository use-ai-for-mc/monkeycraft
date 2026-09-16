# 内嵌 Tailscale 开发 Agent Prompts

## 1. 推荐推进方式

不建议把桌面、手机、网页完整串行做完；总工期会很长，而且很多平台风险可以独立验证。也不建议三个 agent 从第一天起同时修改 Flutter 连接层和共享文档；这会造成接口漂移和反复合并。

推荐采用“**三个隔离工作流并行做首轮 spike，两个集成门槛顺序汇合**”：

```text
                         ┌─ 手机：M0 transport 抽象 + iOS I1
桌面：P0/P1 helper ─ G1 ├─ 网页：W2/W3/W4 隔离 WASM POC
                         └─ Android：证据包/最小 repro
                                   │
                    G2：电脑 helper + 26.2 可被真实客户端连接
                                   │
                         ┌─ iOS I2/I3 真实 E2E
                         └─ Web W5 真实 E2E
                                   │
                    四个 Mod 版本、完整平台矩阵、联合 beta
```

### G1：接口冻结门槛

以下内容冻结后，三个方向才能开始产品级集成：

- desktop helper JSON Lines v1 的状态、错误码、登录事件和版本握手；
- 持久桌面节点与稳定 Node ID 的选择规则；
- Flutter `ConnectionTransport` 的最小接口；
- 登录、审批、ACL 拒绝、退出和删除状态的共同术语；
- 固定的 Tailscale/libtailscale commit 与升级记录方式。

### G2：真实电脑端门槛

`mods/26.2` 通过预编译 helper 暴露实际 MonkeyCraft 端口，现有安装系统 Tailscale 的手机可以完成 HMAC、控制和 H.264 会话。iOS 和 Web 在 G2 之前可以完成登录、构建、echo server 和协议 POC，但不要把“连真实 MonkeyCraft”标记为完成。

## 2. 并行时的文件所有权

建议每个 agent 使用独立 worktree/branch；不要让多个 agent 在同一个脏工作区同时写文件。

| 工作流 | 首轮可修改 | 首轮不得修改 |
| --- | --- | --- |
| 桌面/Mod | `native/tailscale-helper/`、阶段 0 证据、必要的独立 Java harness、`MOD_DESKTOP.md` 的实测结论 | Flutter、Web WASM、四棵 Mod 产品代码 |
| 手机 | Flutter transport 抽象、iOS plugin/build spike、Android evidence/repro、`MOBILE.md` 的实测结论 | Web WASM、desktop helper、四棵 Mod 集成 |
| Web | 独立 `web-tailscale/` POC、Worker/WASM 构建与测试、`WEB.md` 的实测结论 | 在手机 M0 合入前修改 `stream_proxy.dart`/`command_sender.dart`，以及桌面/原生手机代码 |

共享的 `README.md`、`TEST_MATRIX.md` 和最终协议由整合者在三个首轮结果出来后更新。各 agent 只记录与自己工作流有关的证据，避免并行编辑冲突。

## 3. Prompt A：桌面 helper 与 Mod 关键路径

```text
你正在 /Users/cusgadmin/if-local/monkeycraft 的独立 worktree 中工作。请用中文汇报，遵守仓库根目录 AGENTS.md，并保护工作区中与本任务无关的改动。

你的角色是 MonkeyCraft 内嵌 Tailscale 的桌面/helper 负责人。先完整阅读：

- doc/tailscale-integration/README.md
- doc/tailscale-integration/MOD_DESKTOP.md
- doc/tailscale-integration/TEST_MATRIX.md
- doc/TAILSCALE.md
- doc/JAVA_MOD_ARCHITECTURE.md
- /Users/cusgadmin/if-local/imf 中 NativeHelperExtractor、WebViewBridge、native/build-all.sh 和对应 CI workflow

本轮只完成 P0/P1 技术 spike 和可测试的 standalone helper，不要试图一次完成四个 Minecraft 版本，也不要修改 Flutter 或 Web 代码。

目标：建立 native/tailscale-helper/，首选固定版本的 tailscale.com/tsnet，产出一个无需用户安装 Go、Tailscale CLI 或 daemon 的自包含 helper。它必须能够：

1. 使用专用 state dir 启动持久节点；
2. 经结构化 IPN bus/LocalAPI 事件取得交互式 BrowseToURL，禁止通过解析 UserLogf 人类日志作为正式实现；
3. 在 tailnet 内监听一个明确的 TCP 端口，并且只转发到启动命令给出的 127.0.0.1:<port>；
4. 使用 stdin/stdout JSON Lines v1，stdout 只输出协议，stderr 只输出脱敏诊断；
5. 支持 start/status/stop/logout/shutdown，以及 ready/stateChanged/authRequired/listening/error/stopped；
6. 有 protocolVersion、helperVersion、sessionNonce、requestId/eventId、消息长度限制和稳定错误码；
7. 不提供 SOCKS、Funnel、exit node、子网路由、任意目标或控制端口。

执行顺序：

A. 先检查当前仓库和 imf 的实际做法，并把未经验证的假设列出来。
B. 固定 Tailscale commit、Go 版本和 go.sum；记录 BSD-3-Clause 许可证来源。
C. 先实现可注入 backend 的协议/生命周期/转发核心和 fake backend tests，再接真实 tsnet backend。不要让普通 unit tests 依赖公网或个人 Tailnet。
D. 用 echo/WebSocket fixture 测试双向字节、半关闭、慢消费者、连接上限、端口占用、取消、timeout、malformed JSON、stdout 污染、state lock、父进程 EOF 和有界退出。
E. 在当前 macOS 主机完成真实二进制 build/smoke；可以对 Windows/Linux做 compile-only 验证，但没有真实机器证据时不得宣称支持。
F. 尝试一次真实交互登录和两节点 TCP echo。如果需要用户在浏览器批准设备，清楚给出一次性操作并继续完成其余可自动化工作。
G. 添加最小 Java harness 或协议 golden consumer，验证 Java 17/21/25 都能启动 fake helper、收发协议并有界清理；本轮不要接入 Minecraft UI 或四棵 Mod 树。

测试至少运行：Go unit tests、可移植核心 race tests、协议 golden tests、helper process integration、Java harness tests，以及最终产物的版本/hash 检查。不要把 auth URL、auth key、节点私钥、完整 NetMap 或 MonkeyCraft 密码输出到日志或测试 artifact。

完成时交付：

- 可构建的 standalone helper 源码与锁定依赖；
- IPC v1 schema/golden vectors；
- 自动化测试；
- 一份阶段 0 证据记录，区分“已自动验证”“已真机验证”“仍是假设”；
- 对 P2 Java extractor/process supervision 的具体下一步清单。

停止条件：如果 tsnet 无法在当前固定版本取得结构化登录 URL、无法持久恢复、或 listener 无法稳定转发，不要改用日志解析或扩大权限来掩盖问题。保留最小复现、测试输出和备选 libtailscale 评估后汇报阻塞。除这种真实架构阻塞外，请持续工作到本轮交付完整。
```

## 4. Prompt B：Flutter 共享连接层、iOS 与 Android 复核

```text
你正在 /Users/cusgadmin/if-local/monkeycraft 的独立 worktree 中工作。请用中文汇报，遵守仓库根目录 AGENTS.md，并保护工作区中与本任务无关的改动。

你的角色是 MonkeyCraft 手机端内嵌 Tailscale 负责人。先完整阅读：

- doc/tailscale-integration/README.md
- doc/tailscale-integration/MOBILE.md
- doc/tailscale-integration/TEST_MATRIX.md
- doc/FLUTTER_CLIENT.md
- flutter/monkeycraft/lib/stream/stream_proxy.dart
- flutter/monkeycraft/lib/stream/proxy/command_sender.dart
- iOS AppDelegate、Podfile、RunnerTests 和 Android MainActivity/build files

本轮按顺序完成 M0 和 iOS I1，并形成 Android 复核证据包。不要直接实现 iOS I2/I3 产品连接，也不要承诺 Android 内嵌支持。

第一部分 M0：你是 Flutter 共享 transport 抽象的唯一 owner。

1. 提取最小 ConnectionTransport/TransportFactory，使 StreamProxy 不再直接创建 WebSocketChannel；DirectWebSocketTransport 必须包装当前行为。
2. 保持现有 ws/wss URL 解析、HMAC、CommandSender、文本/二进制消息、视频 relay、timeout、关闭和三次重连语义不变。
3. 接口必须允许将来接入 iOS loopback transport 和 Web Worker transport，但本轮不要增加空壳 Tailscale UI 或不可用模式。
4. 用 fake transport 增加单测，覆盖 ready、认证成功/失败、binary/text、send、close、取消、timeout 和重连；运行全部现有 Flutter tests 和 flutter analyze。
5. 把接口和生命周期写成简短 handoff，供 Web agent 在 M0 合入后使用。

第二部分 iOS I1：固定并验证官方 libtailscale/TailscaleKit 构建。

1. 固定 libtailscale commit、Go/Xcode/Swift 版本、构建命令、许可证和产物 SHA-256。
2. 分别验证 ios device、ios simulator 和 ios-fat/xcframework 的用途；不要把 simulator slice 放进 App Store archive。
3. 建立最小 TailscaleTransportPlugin/diagnostics spike，只验证 framework 可加载、节点能力可调用和错误可结构化返回，不接入 StreamProxy。
4. 验证 iOS 最低版本、Swift 并发、签名/embedding、真机 dyld、archive 和现有 RunnerTests。不要静默提高最低 iOS 版本。
5. 记录官方 interactive browseToURL/IPN bus 路径和 LocalAPI/Node ID 能力；不要在 App 中放 reusable auth key。
6. 检查现有出口合规声明，明确列出需要人工重新评估的项目，不给法律保证。

第三部分 Android：只做固定版本的适用性复核和最小 repro。

1. 比较 libtailscale C archive + JNI、官方 Android backend 的最小化方案、tsnet AAR 三条路线。
2. 复核 tailscale/tailscale#17311 在当前日期和固定版本的状态，并验证它是否实际影响最小 gomobile AAR。
3. 若工具链可用，做 Start → interactive auth/state → dial TCP → close 的最小 arm64-v8a repro；记录 AGP、NDK、Go、gomobile、API level 和设备/模拟器差异。
4. 不允许通过未维护的私有 Go runtime patch 得出“可发布”结论；若必须 patch，只提交最小复现、diff 和维护风险。
5. 按 MOBILE.md 的 Go/No-Go 表给出证据，不修改产品 Android 连接代码。

并行边界：不要修改 web-tailscale/WASM；Web agent 在你的 M0 合入前也不应修改 StreamProxy/CommandSender。如果发现接口需要调整，把最小变更和原因写入 handoff，不要同时实现 Web 特例。

完成时交付：

- direct 行为不变的 Flutter transport 抽象和完整回归测试；
- 可重复的 iOS TailscaleKit build/diagnostics spike 与真机/archive证据；
- Android 最小 repro 或明确的可复现阻塞，以及 Go/No-Go 证据表；
- 下一轮 I2 登录/设备选择和 I3 loopback bridge 的具体任务拆分。

停止条件：M0 若出现现有协议回归，先修复回归，不继续 iOS 集成。iOS framework 若无法稳定签名/加载，停在 I1 并报告；Android 上游问题若仍存在，不要绕过发布门槛。除真实平台或签名阻塞外，请持续工作到本轮交付完整。
```

## 5. Prompt C：网页 WASM、登录和字节流 POC

```text
你正在 /Users/cusgadmin/if-local/monkeycraft 的独立 worktree 中工作。请用中文汇报，遵守仓库根目录 AGENTS.md，并保护工作区中与本任务无关的改动。

你的角色是 MonkeyCraft 网页端 Tailscale/WASM 负责人。先完整阅读：

- doc/tailscale-integration/README.md
- doc/tailscale-integration/WEB.md
- doc/tailscale-integration/TEST_MATRIX.md
- doc/FLUTTER_CLIENT.md
- flutter/monkeycraft/lib/stream/stream_proxy.dart
- flutter/monkeycraft/lib/stream/proxy/command_sender.dart
- web H.264 decoder、page visibility 和现有 web CI workflows
- Tailscale 官方 cmd/tsconnect、wasm_js.d.ts、wasm_js.go、DERP WebSocket 代码，以及 tailcat（只作备选对照）

手机 agent 是 Flutter ConnectionTransport/StreamProxy/CommandSender 的首轮 owner。在其 M0 合入前，你不得修改这些共享文件。你的本轮目标是用隔离的 web-tailscale/ POC 完成 W0、W2、W3，以及 W4 的 TCP/WebSocket 可行性核心；不要提前接入 Flutter 产品 UI。

执行顺序：

A. W0 基线：记录现有 Flutter Web direct WebSocket 的构建、认证、文本/二进制和 H.264 基线；补测试时只修改 Web 专属测试或 fixture，不重构共享 transport。
B. W2 构建：固定 Tailscale commit 和 Go 版本，建立可重复的 GOOS=js GOARCH=wasm 构建；同版本复制 wasm_exec.js，生成 VERSION.json、hash、大小、许可证和依赖记录。不得从 main/latest 或浮动 CDN 加载。
C. Worker：WASM、WireGuard/netstack、DERP、协议 framing 全部运行在 Dedicated Worker；定义版本化 RPC，使用 transferable ArrayBuffer、有界队列、取消和 close 传播。
D. W3 控制面：验证 NeedsLogin → login → notifyBrowseToURL → Running → notifyNetMap；同步打开授权窗口处理 popup blocker。退出时清理 session state。默认只用 sessionStorage；不要植入 auth key/OAuth secret。
E. 设备选择：当前官方 wasm_js.d.ts 只暴露 machineKey/nodeKey 等字段。验证上游内部是否有稳定 Node ID；若有，在窄 bridge 中暴露它，不能把显示名称或可轮换 node key 宣称为永久稳定 ID。
F. W4 数据面：证明官方公开 @tailscale/connect API 没有任意 TCP dial 后，在固定源码上增加最窄的 dialTcp/read/write/close bridge。先连接 echo server；不要实现通用 SOCKS、UDP、任意 fetch gateway 或端口扫描。
G. 在 Worker 内实现或隔离一个 RFC 6455 client adapter，覆盖 client masking、fragmentation、continuation、binary/text、ping/pong、close、长度限制、错误 frame、背压和半关闭。可移植 parser 在 host Go/TypeScript 运行 unit/race/fuzz tests，WASM 路径单独做浏览器集成测试。
H. 明确验证浏览器路径是否只能 DERP-over-WSS。记录 DERP region、RTT、吞吐、内存和 Worker CPU；没有真实数据时不得宣称实时视频可用。

首轮浏览器测试至少覆盖 Chrome headless + 当前 Chrome 真浏览器：WASM MIME/加载、popup 被阻止 fallback、登录取消、Running、NetMap、logout、刷新、Worker crash、WSS 被阻断、echo 大帧、网络断开、队列上限和资源释放。Safari/Firefox/iOS 只做能实际执行的 smoke，不要根据 Chrome 结果宣称支持。

安全要求：严格限制 connect-src/worker-src 设计；日志不得含完整 auth URL、auth key、私钥、完整 NetMap、Tailnet IP 表或 H.264 内容；核心 WASM 不从未固定第三方 CDN 加载；不得扫描 peer 端口。Tailcat 只能作为免 Tailnet 账号的独立 pairing 备选，不要混入主线控制面实现。

完成时交付：

- 隔离、可删除的 web-tailscale/ POC 和可重复构建脚本；
- Worker RPC 与受限 dialTcp API schema；
- 控制面登录/NetMap 浏览器测试；
- echo server 上的 TCP + RFC 6455 字节流测试；
- DERP-only 能力、性能初测和仍待验证的明确表格；
- 等手机 agent 的 M0 合入后，将 TailscaleWebTransport 接入 Flutter 的下一轮变更清单。

停止条件：如果上游固定版本无法在浏览器建立所需 TCP stream，不要用普通浏览器 WebSocket、service worker 或未经授权的公网网关伪装成 Tailscale 数据面。如果 DERP-only 性能不足，保留证据并把视频/WebRTC 列为后续决策。除真实浏览器能力阻塞外，请持续工作到本轮交付完整。
```

## 6. 首轮完成后的整合检查

三个 agent 都完成首轮后，由一个整合者只做以下事情：

1. 比较三者固定的 Tailscale commit；若不同，决定统一或记录必须分叉的原因。
2. 冻结 helper IPC v1、Flutter transport 和 Worker RPC，不在合并时顺手扩大功能。
3. 让桌面 agent进入 P2/P3，先完成 `mods/26.2` 的真实手机 E2E。
4. G2 通过后，手机 agent做 I2/I3，Web agent做 W5；这两项可以再次并行。
5. 最后才把桌面实现同步到 26.1、1.21.11、1.19，并开启完整联合矩阵。

如果必须缩减并行资源，优先级是：桌面/helper第一，手机 M0+iOS I1 第二，Web POC 第三，Android 产品实现最后；但 Android 调研可以始终作为低冲突工作并行进行。
