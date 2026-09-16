# MonkeyCraft 网页端 Tailscale / WASM 方案

## 结论与范围

网页端可以在**不安装 Tailscale 客户端、也不申请浏览器 VPN 权限**的前提下，以 WebAssembly 在页面内运行一个受限的 Tailscale userspace 节点；用户可在浏览器中完成自己的 Tailscale 登录、查看可见 Tailnet 设备并选择运行 MonkeyCraft 的电脑。Tailscale 官方的 `tsconnect` 正是此模式，浏览器节点会作为 Tailnet 的临时（ephemeral）设备出现；若 Tailnet 开启设备审批，仍需管理员批准。[Tailscale browser client](https://tailscale.com/docs/privileged-access-management/how-to/access-ssh/remote-ssh)

这不是浏览器中的“完整 VPN”：浏览器没有 TUN、任意 UDP socket 或让原生 `WebSocket` 走自定义网络栈的权限。浏览器版数据面只能经 WebSocket-DERP 访问中继，不能使用 Tailscale 的 UDP 直连。对 MonkeyCraft 而言，目标是让**本页面的一条 MonkeyCraft 数据连接**经 Tailscale 发送；不影响同浏览器的其他标签页或设备的系统网络。

本文件把“用户登录自己的 Tailnet 并选择设备”作为主线。`tailcat` 配对方案是可选的第二条产品路线，不能混同为 Tailscale Tailnet 登录。

## 已有代码与改造边界

当前 Web 构建已具备两个有利条件：

- [Web H.264 解码器](../../flutter/monkeycraft/lib/stream/video/web_h264_decoder.dart) 使用 `WebCodecs`、硬件解码偏好和队列丢帧策略；目前已经明确提示只支持较新的 Chrome/Edge。
- [页面可见性处理](../../flutter/monkeycraft/lib/platform/page_visibility_web.dart) 与 [前台帧保活](../../flutter/monkeycraft/lib/platform/web_frame_keep_alive_web.dart) 已处理一部分页面失焦情形，可复用于连接恢复提示，但不能绕过浏览器后台冻结。
- CI 已执行 `flutter analyze`、`flutter test` 和 `flutter build web --release`，并发布到 GitHub Pages；目前没有 Web 端到端浏览器测试。[build workflow](../../.github/workflows/build.yml)、[Pages workflow](../../.github/workflows/pages.yml)

主要缺口在 [StreamProxy](../../flutter/monkeycraft/lib/stream/stream_proxy.dart)：它在 `start()` 中直接调用 `WebSocketChannel.connect(wsUrl)`，而 [CommandSender](../../flutter/monkeycraft/lib/stream/proxy/command_sender.dart) 也直接依赖 `WebSocketChannel`。这意味着不能把 Tailnet 地址原样交给浏览器原生 WebSocket，也不能仅给 URL 加一个代理参数。先抽象传输层是前置工作，不能在现有连接路径上叠加特殊判断。

建议的新边界（名称仅为建议）如下：

```text
StreamProxy / CommandSender
        │  MonkeycraftTransport（ready、inbound、send、close、状态）
        ├─ DirectWebSocketTransport（现有 ws/wss 行为）
        └─ TailscaleWebTransport（仅 Web）
                 │ MessageChannel，二进制 ArrayBuffer 可转移
                 ▼
            Dedicated Web Worker
                 │  WASM userspace WireGuard + gVisor netstack
                 │  WebSocket-DERP
                 ▼
       目标电脑 Tailnet 地址:MonkeyCraft WebSocket 端口
```

`TailscaleWebTransport` 应在 Worker 内完成目标 WebSocket 的 RFC 6455 client handshake、掩码帧写入、文本/二进制帧解析、ping/pong 与 close。Worker 向 Dart 暴露的应是与 `WebSocketChannel` 等价的消息流，不应把裸 TCP 字节或 WebSocket 分帧细节泄漏给 `StreamProxy`。这样现有认证、H.264 二进制帧、输入命令、心跳和断线重试语义可以保留。

必须先用单独的 TCP byte-stream adapter 验证帧解析：Tailscale 的原生浏览器 `IPN` API 目前公开的是 `login/logout`、状态/NetMap 回调、SSH 与 `fetch`，而非任意 TCP `dial` 或可注入的浏览器 WebSocket transport。[接口定义](https://github.com/tailscale/tailscale/blob/main/cmd/tsconnect/src/types/wasm_js.d.ts) 因此不能把 `@tailscale/connect` 当作开箱即用的 WebSocket SDK。生产实现需二选一：

1. 固定并审计 Tailscale 源码版本，基于 `cmd/tsconnect/wasm` 增加窄接口 `dialTcp(host, port)`，再在 Worker 实现 WebSocket adapter。这是本方案的主路线。
2. 另建受控的 HTTP/WebSocket 网关，只使用现成 `fetch()`。这会引入额外服务、鉴权和视频转发成本，不应作为“纯前端直连”的默认实现。

不要把浏览器原生 WebSocket 通过 SOCKS 或普通 service worker 代理；浏览器 API 不支持这一注入模型。

## 技术依据与能力边界

`tsconnect` 的 WASM 实现使用 userspace WireGuard engine 和 gVisor netstack，并把所有 IP 的 TCP/UDP dial 导向该 netstack；其状态回调有 `notifyState`、`notifyNetMap`、`notifyBrowseToURL`，登录调用 `StartLoginInteractive`。[WASM 实现](https://github.com/tailscale/tailscale/blob/main/cmd/tsconnect/wasm/wasm_js.go)

浏览器内 DERP 客户端在 `GOOS=js` 时使用 WebSocket，并以 `derp` 子协议传输二进制消息。供浏览器使用的 DERP 服务必须开启 WebSocket-DERP 包装；服务端还会关闭 WebSocket 压缩。[DERP client](https://github.com/tailscale/tailscale/blob/main/derp/derphttp/websocket.go)、[DERP server](https://github.com/tailscale/tailscale/blob/main/derp/derpserver/websocket.go)

因此首个版本的真实链路是：

```text
Flutter Web UI → Worker → userspace TCP/IP → WireGuard → DERP-over-WSS
           → 电脑上的 Tailscale 节点 → MonkeyCraft Mod WebSocket 服务
```

DERP 中继不会解密 WireGuard 内容，但它是 TCP/WSS 上承载再一层 TCP/WebSocket 的路径。出现丢包或拥塞时，可能有显著的队头阻塞和时延波动；不能把它描述为与原生 UDP 直连相同的游戏体验。视频最多 20 FPS 的现有约束降低了风险，但是否可接受必须以真实 H.264 码率、RTT、抖动和丢帧测试决定。

## 主线：Tailnet 登录、选机与连接

### 用户流程

1. 用户在“连接方式”选择“使用 Tailscale”。首次点击时同步打开一个空白授权窗口，避免浏览器将异步弹窗拦截。
2. 主线程请求 Worker 初始化 WASM。Worker 状态为 `NeedsLogin` 时把 `notifyBrowseToURL` 返回的 URL 交给该窗口；若弹窗不可用，显示可点击链接与二维码/复制链接入口。
3. 用户在 Tailscale 页面完成 SSO/MFA。原页面不解析 OAuth callback；WASM 持续与控制平面同步，收到 `Running` 后通过 `notifyNetMap` 获得自身和 peer 列表。
4. UI 只把在线设备置顶，并显示设备名、Tailnet IP/MagicDNS、在线状态和“尚待审批/无权限”的可解释状态。优先保存 NetMap 暴露的稳定 Node ID；node key 可能轮换，显示名称也不是 ID。若固定版本的 WASM bridge 没有暴露 Node ID，W3 必须增加该窄字段或记录受限恢复策略。
5. 用户选中电脑后，客户端用该节点的 Tailnet IP 或经验证的 MagicDNS 名称与 MonkeyCraft 端口建立 `TailscaleWebTransport`。成功完成既有 MonkeyCraft 密码/挑战握手后才记忆最近选择。

NetMap 中的 peer 只表示可见设备，并不证明其中运行 MonkeyCraft。首版不要扫描用户全部设备端口。可采用以下安全且可解释的筛选顺序：由窄 bridge 暴露并保存的 Node ID、用户显式选择、与 MonkeyCraft WebSocket 握手成功；未来若 Mod/桌面辅助端增加签名过的服务登记，再显示“已发现 MonkeyCraft”标志。

### 节点状态与存储

默认使用会话级状态存储：浏览器标签关闭即丢弃浏览器节点身份，符合 browser client 的 ephemeral 预期；`tsconnect` 开发实现也使用 `sessionStorage` 并在关标签后丢失。[tsconnect README](https://github.com/tailscale/tailscale/blob/main/cmd/tsconnect/README.md)

如果产品需要刷新后保留会话，可为 Worker 提供 `IPNStateStorage` bridge，并将加密材料存入 IndexedDB；它必须是用户明确选择“在此浏览器保持登录”的 opt-in。IndexedDB 不是抵御 XSS 的密钥库：同源恶意脚本仍可读出状态。要求：严格 CSP、无第三方脚本、依赖完整性审计、退出时调用 `logout()` 并删除对应 state、提供“清除本机 Tailscale 登录”按钮。不要在网页、WASM、URL、日志或分析事件中植入 reusable auth key/OAuth secret。

页面在隐藏、Worker 被终止、WSS/DERP 断开、网络切换或电脑离线时进入 `reconnecting`；恢复前台后重新取 NetMap、重新拨号并复用现有 StreamProxy 重连策略。浏览器后台冻结不可被 `setInterval` 或现有帧保活可靠避免，UI 应明确提示“切回页面后自动重连”。

### 授权、ACL 与隐私

用户登录的是其自己的 Tailnet，浏览器节点仍受 Tailnet ACL、设备审批和目标设备的 shields-up 等策略约束。不能以 MonkeyCraft 前端绕过这些规则。页面应只显示必要的设备元数据，不上传完整 NetMap；诊断日志仅采集经用户同意的错误类别、DERP 区域和性能聚合，不能上传节点密钥、Tailnet IP 全表或登录 URL。

## 可选路线：Tailcat 配对，不是 Tailnet 登录

[Tailcat](https://github.com/tailscale/tailcat) 复用 Tailscale data plane（WireGuard、magicsock、DERP、netstack），但**不使用 Tailscale 控制平面**。电脑 helper 创建 listener 并产生 `tc…` 连接 token；网页 WASM 以 token 和目标端口拨号。它不要求 Tailscale 账号、也没有 Tailnet 设备选择界面。官方网页 demo 仍标为 experimental，浏览器流量明确是 DERP-only，WebRTC 直连仍在跟踪中。[Tailcat README](https://github.com/tailscale/tailcat/blob/main/README.md)、[WebRTC tracking issue](https://github.com/tailscale/tailcat/issues/4)

它适合作为“扫描/输入 MonkeyCraft 配对码”的独立入口：

```text
电脑 helper 生成短时、单用途 token → QR/手输 → 浏览器 tailcatDial → 指定 TCP 端口
```

不可把 token 当密码或长期地址：它是 capability。首版必须设置短过期、单会话/单客户端公钥允许列表、电脑端撤销与显示已连接客户端；不要默认持久化 token。应使用自有/受控 DERP，不能依赖免费限流 DERP 承载视频。Tailcat 仍需要同样的 Worker、TCP→WebSocket adapter、视频性能测试；它并不会省去这些实现工作。

## 构建、固定版本与交付

### 推荐供应链

不要在发布时从 `main`、CDN 的浮动 URL 或未锁定 npm 版本加载网络核心。建立一个独立的 `web-tailscale/` 构建组件（实现阶段再创建），其输入必须固定为：

- Tailscale 上游 Git tag/commit、对应源码 tarball SHA-256、许可证（上游代码为 BSD-3-Clause）与 Go 精确版本；
- MonkeyCraft 对 `cmd/tsconnect/wasm` 的小型补丁集（只增加经过评审的 TCP bridge），每次升级要求 rebase、diff 审阅和安全测试；
- `wasm_exec.js` 必须来自同一 Go 工具链；它与 WASM 不能跨版本混用；
- 生成 `VERSION.json`：上游 commit、Go 版本、补丁 SHA-256、WASM 原始/压缩字节数和构建时间；CI 校验其与锁文件一致。

官方 `tsconnect` 的构建目标是 `GOOS=js GOARCH=wasm`，并可构建 NPM 包；Tailcat 的构建工具展示了可重复 tags、`-s -w`、gzip/zstd 预压缩的实际模式。[tsconnect build instructions](https://github.com/tailscale/tailscale/blob/main/cmd/tsconnect/README.md)、[tailcat WASM build](https://github.com/tailscale/tailcat/blob/main/internal/wasmbuild/wasmbuild.go)

建议产物放在 Flutter `web/` 的版本化路径，例如 `assets/tailscale/<content-hash>/main.wasm`、`wasm_exec.js` 和 `bridge-worker.js`。Worker 用显式、相对 base-href 的 URL 加载，避免 GitHub Pages 的 `/monkeycraft/` 子路径错误。部署服务器应提供：

- `Content-Type: application/wasm`；
- Brotli 或 gzip 预压缩版本及 `Content-Encoding`、`Vary: Accept-Encoding`；若 GitHub Pages 无法配置响应头，先提供未压缩正确 MIME 的功能验证，正式生产改由可配置 CDN/静态托管；
- content-hash 长缓存、HTML/manifest 短缓存；不要用 service worker 缓存覆盖安全升级；
- CSP：`worker-src 'self'`、`script-src 'self'`，`connect-src` 仅放行应用源、Tailscale control URL 和批准的 DERP 域名。动态 DERP map 的域名集合需在产品安全评审中确定。

WASM 解压、Go runtime 和视频解码都可能占用主线程。WASM、WireGuard、netstack、DERP 读写与 WebSocket framing 必须运行在 Dedicated Web Worker；使用 `postMessage` 的 transferable `ArrayBuffer`，限制队列，视频积压时优先丢弃非关键帧并向 Mod 请求关键帧，复用现有 `DecodeQueuePolicy` 的语义。

## 分阶段开发与测试计划

每一阶段都先以可独立删除/关闭的 feature flag 落地，不修改默认直连路径。后续阶段未满足退出条件前，不进入下一阶段或对用户开放。

| 阶段 | 交付物 | 自动化验证 | 退出/准入标准 |
|---|---|---|---|
| W0：基线 | 记录现有 Web 直连端到端指标；补足 `StreamProxy`/`CommandSender` 单测覆盖 | `flutter analyze`、`flutter test`、Chrome 直连 smoke | 现有 `ws/wss` 行为和全部协议测试无回归；记录分辨率、FPS、RTT、码率、解码丢帧基线 |
| W1：传输抽象 | `MonkeycraftTransport`、Direct adapter、fake transport；不含 Tailscale | Dart 单测：ready、send、binary/text、close、超时、重连、命令认证门控 | Direct adapter 与当前 `WebSocketChannel` 互换后，通过现有认证和视频二进制消息测试 |
| W2：WASM 可重复构建 | 锁文件、源码校验、WASM/worker 资产、版本清单与本地开发命令 | CI 重建比对 hash；WASM MIME/压缩资产检查；许可证/依赖扫描 | 固定 commit/Go 版本可由干净 runner 重建；发布包不引用浮动远程脚本 |
| W3：控制面 POC | Worker 内 `tsconnect`、状态机、登录窗口、会话存储、NetMap 列表；暂不拨 MonkeyCraft | mock JS bridge 单测；Playwright/Chrome：NeedsLogin、popup 被拦截 fallback、Running、logout、审批/ACL 错误渲染 | 真实测试 Tailnet 中可登录、列出设备、退出后状态确实清除；不持久化 auth key |
| W4：数据面 POC | 上游 WASM 的受限 `dialTcp` patch；Worker TCP→WebSocket adapter；连接一台测试 echo/WebSocket 服务 | 可移植核心的 host-Go 单测/race；WASM 集成测试；RFC 6455 向量（分片、mask、ping/pong、close、非法长度）；Chrome headless 与真实浏览器测试 | TLS/WSS 不被假设；目标端断开、DERP 重连和网络切换都不会泄漏 worker/句柄或无限缓存 |
| W5：MonkeyCraft 集成 | Tailscale 设备选择、现有认证、视频/输入/聊天、恢复状态；功能 flag 仅对测试用户开放 | Dart integration test + 真 Mod 测试矩阵：密码错误、能力降级、断线重连、休眠、分辨率切换、H.264 keyframe | 在独立 Tailnet、ACL 拒绝及正常 ACL 三种场景得到可解释结果；直接连接未回归 |
| W6：跨浏览器与负载 | 性能仪表盘、容量与兼容性结论 | Playwright Chrome/Edge/Firefox/Safari 技术预览（若可）；真实 macOS Safari、iOS Safari、Android Chrome；网络限速/丢包/切网 | 只将实测通过的浏览器列为支持；WebCodecs/WASM/worker 不支持时给出明确 fallback，不静默失败 |
| W7：发布决策 | 安全评审、隐私文案、运行手册、回滚开关 | 依赖升级演练、CSP/XSS review、worker 崩溃/DERP 故障演练、staging canary | 达到下述体验阈值后才进入 beta；否则保持实验功能或转向 WebRTC 方案 |

### 必测故障与安全清单

- Tailnet 设备审批、ACL 拒绝、目标离线、目标端口未监听、MagicDNS 失败、DERP map 失败、DERP WebSocket 被公司代理阻断、控制平面超时。
- 首次登录、登录取消、弹窗拦截、多个页面并发、退出/清缓存、密钥状态损坏、浏览器刷新、标签后台冻结、Worker 被浏览器回收。
- 目标 WebSocket 的 fragmented frame、64 KiB 以上 H.264 帧、关键帧、关闭握手、心跳超时、网络从 Wi-Fi 切到蜂窝/反向切换、电脑睡眠/恢复。
- 所有日志和 analytics 断言：不得包含 auth URL、auth key、私钥、完整 NetMap、配对 token 或 H.264 内容。CSP/XSS 检查、依赖 SBOM、WASM/worker 完整性和发布资产 hash 校验为发布门槛。

### 性能准入与 WebRTC 决策

W5 起连续采集：端到端输入 RTT（p50/p95/p99）、连接建立时间、DERP region、视频有效 FPS、码率、关键帧等待、解码队列深度/丢帧、主线程长任务、Worker/WASM 内存、断线恢复时间。对每种网络至少各跑 30 分钟：低延迟宽带、跨区宽带、受限 Wi-Fi、4G/5G 和受控 1–3% 丢包。

在试验期先由团队根据 W0 基线批准量化门槛。可供校准的候选 beta 起点是：连接成功率 >= 99%（受支持浏览器/网络样本）、连续 30 分钟无内存持续增长、p95 输入 RTT 相对直接基线的增量 <= 150 ms、有效视频 >= 15 FPS 且没有连续 5 秒不可恢复卡顿；这些数字不是发布承诺，W0 数据若显示设备或地区差异过大，应在 ADR 中调整并说明理由。若 DERP-only 在目标地区无法稳定达到最终门槛，或 TCP-over-TCP 导致体验不可接受，停止扩大 Tailnet-WASM 发布：控制/聊天可保留，视频与实时输入转入 WebRTC（H.264/RTP + DataChannel）可行性项目。WebRTC 是后续架构决策，不是本计划隐含已拥有的能力。

## Flutter Web 接入（W5，2026-08-31）

`StreamProxy` 现已通过 `TransportFactory` 注入。Web 在 `kIsWeb` 下启用 `TailscaleEmbeddedClient`（`tailscale_embedded_web.dart`）：Dedicated Worker 加载 `web/tailscale/main.wasm`，`openBridge` 返回 `ws://<peer-ip>:9600`，`gameTransportFactory` 在 Dart 侧做 RFC 6455，HMAC / H.264 AU / `WebH264Decoder` 不变。登录页对 Web 显示「Connect with Tailscale」。iOS 仍走 loopback + `DirectWebSocketTransport`；Android 无入口。`web/tailscale/main.wasm` gitignore，用 `flutter/monkeycraft/scripts/sync_web_tailscale.sh` 从 `web-tailscale/dist` 同步。DERP 上的真实 H.264 仍待浏览器实测。

## 首轮 Web POC 实测结论（2026-08-30）

隔离目录 `web-tailscale/`（可删除）。**未修改** Flutter `stream_proxy.dart` / `command_sender.dart`。

已自动验证：RFC 6455 可移植解析（掩码、分片、续帧、ping/pong、close、非法长度/opcode、UTF-8）、RPC v1 schema、fake 控制面（NeedsLogin / popup fallback / Running / logout 清 state）、单连接 echo、Chrome 151 headless。固定上游 **tailscale v1.102.3** (`53a0d659afa51835dd7a9283873cca44261454f8`)。公开 `@tailscale/connect` **没有** 任意 TCP dial；内部 `UserDial` 存在。`tailcfg.Node.StableID` 是应持久化的 ID，官方 JS NetMap 未暴露，需窄补丁。浏览器数据面只能 DERP-over-WSS。

仍是假设：真实登录、DERP RTT/吞吐、H.264 可用性、Safari/Firefox/iOS、Pages WASM MIME。无真实数据前 **不** 宣称实时视频可用。细节见 `web-tailscale/docs/EVIDENCE.md`。

## 不应承诺的事项

- 不承诺浏览器版具备原生 Tailscale 的 UDP 直连、后台常驻、系统 VPN、全应用代理或完整 subnet/exit-node 行为。
- 不承诺所有 Tailnet、企业代理、Safari/Firefox、移动浏览器或 GitHub Pages 部署均可用；只有 W6 的实测矩阵可定义支持范围。
- 不使用用户的 reusable auth key，也不将任意消费者加入 MonkeyCraft 维护的共享 Tailnet。
- 不把 Tailcat 的 capability 配对、或实验性官方 demo，描述为已生产可用的免账号网络服务。
