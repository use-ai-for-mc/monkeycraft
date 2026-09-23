# iOS v1.94.1 AuthURL 延迟源码分析（2026-09-18）

范围：只读分析固定 `tailscale.com v1.94.1` 及本地 `libtailscale` C archive 源码；未改动 Go module、iOS 工程、设备、游戏或网络配置。

## 已复现的边界

同机、固定 v1.94.1、纯 Go `tsnet.Server` 基线（新临时 state directory；没有 Swift、Flutter、C ABI 或 loopback HTTP）已复现 AuthURL 的不稳定首发延迟：

| run | `Start` | 首次 Status | `StartLoginInteractive` 返回 | `AuthURL` 出现 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 25 ms | 61 ms | 93 ms | 33,770 ms |
| 2 | 20 ms | 56 ms | 90 ms | 8,391 ms |
| 3 | 21 ms | 56 ms | 90 ms | 1,890 ms |

原始脱敏计时：`/tmp/monkeycraft-ios-tsnet-baseline-timings.jsonl`；程序：`/tmp/monkeycraft-ios-tsnet-baseline/main.go`。这已经排除 Swift/Flutter 线程、`UIApplication.open` 和当前 Swift loopback `URLSession` 是 **33 秒首要原因**。它们可能仍影响“收到 AuthURL 后何时弹出网页”，但不能解释该纯 Go 基线。

同轮新 PC helper（v1.102.3）三次登录需要 AuthURL 的样本为 1.1 / 1.4 / 4.2 秒。这是环境与版本组合的对照，不足以单独归因到版本差异。

## 调用链及同步边界

```text
Swift tailscale_start
  → libtailscale TsnetStart
  → tsnet.Server.Start (构建 userspace backend 后返回)
  → LocalBackend / controlclient.Auto 的后台 authRoutine
  → Direct.TryLogin
  → HTTPS GET /key
  → Noise HTTP POST /machine/register
  → Auto.sendStatus(URL)
  → LocalBackend.SetControlClientStatus
  → authURL / ipnstate.Status.AuthURL
  → Swift 1 秒轮询读 status 并调用 presenter
```

| 环节 | 源码位置 | 行为与结论 |
| --- | --- | --- |
| C `start` | `ios/third_party/libtailscale/src/tailscale.go:107-118` | `TsnetStart` 只有 `s.s.Start()`；没有 `Up()`，不会等待控制面登录或 AuthURL。 |
| tsnet 初始化 | `tsnet/tsnet.go:369-375`, `584-797` | `Server.Start` 只运行一次初始化。它创建 netmon/userspace engine/netstack、state store、LocalBackend 和 LocalAPI；`lb.Start` 后立即返回。 |
| 首次登录触发 | `tsnet/tsnet.go:762-771` | 初始状态为 `NeedsLogin` 时已调用 `StartLoginInteractive`，但这是请求后台流程，不等 AuthURL。 |
| Swift 按钮的 LocalAPI | `ipn/localapi/localapi.go:924-939`；`ipn/ipnlocal/local.go:3771-3811` | `/login-interactive` 只锁定 backend、检查已有 URL 或执行 `cc.Login(...)` 后返回。基线 93ms 证实它不是 30 秒同步阻塞。 |
| 后台控制流程 | `control/controlclient/auto.go:305-401` | `authRoutine` 才执行 `TryLogin`/`WaitLoginURL`。AuthURL 产生前实际在此异步流程和网络中等待。 |
| AuthURL 可见点 | `control/controlclient/auto.go:362-385`；`ipn/ipnlocal/local.go:1560-1828,3389-3424` | Register 返回 URL 后，`sendStatus` 入队，由 LocalBackend 设置 `authURL`。只到这一点 `Status.AuthURL` 才非空。 |
| Swift 轮询 | `ios/Runner/TailscaleNodeManaging.swift:240-311,367-375` | 同一串行队列每秒轮询。它只增加 0–1 秒展示量级；不能形成 33 秒。 |

## 有明确时长且可到达的等待点

下表只列入本调用链能触及、且源码给出了时长或 timeout 上界的项目；它们是待用日志判别的候选，不是未经证实的归因。

| 候选 | 源码位置 | 具体时长与触发条件 | 对 33.77 秒的解释力 | 无敏感验证方式 |
| --- | --- | --- | --- | --- |
| 首次系统 DNS | `net/dnscache/dnscache.go:271-318` | 没有缓存时，普通 resolver 最多 **10 秒**；失败/空结果才进入 fallback。iOS/darwin 选择系统 resolver（`dnscache.go:37-43`）。 | 高。首次状态目录与冷 DNS 特别相关；不能单独解释 33 秒。 | 仅记录 `dns-start/dns-result/error class/elapsed`；不输出 host、IP 或 URL。 |
| Bootstrap DNS | `net/dnscache/dnscache.go:309-318`; `net/dnsfallback/dnsfallback.go:91-127` | fallback 外层最多 **30 秒**；最多 6 个 DERP 候选，每个 **3 秒**。普通 DNS 的 10 秒加 fallback 的最多约 18 秒候选循环可构成冷启动的显著部分。 | 高。日志若有 `bootstrapDNS` 连续失败/超时可直接确认。 | 白名单计数每个 candidate 的耗时与成功/失败，不记录 DERP hostname/IP 或 query。 |
| `/key` TLS 请求 | `control/controlclient/direct.go:571-595,1349-1382`；`direct.go:287-306` | 首次无 server key 必发 `GET /key`；`http.Client` 未设总 timeout，request 继承长期 `authCtx`。TLS dial 的握手尝试是 **5 秒**（`dnscache.go:667-695`），但 TCP/系统 resolver 的最终时限由系统和 context 决定。 | 高。此处有无上界的冷网络等待，且发生在 Noise register 前。 | 对 `GET /key` 记录开始/结束/错误类别/elapsed；绝不记录 URL、响应正文、证书或地址。 |
| Noise control dial | `control/ts2021/client.go:194-260` | 无 control dial plan 时，单次 noise dial 的硬上限是 **10 秒**（5 秒默认 dial + 5 秒 handshake）；有 plan 时按服务端候选 delay+timeout，整体钳制到 **5–60 秒**。 | 高。一次 10 秒超时加后续重试足以接近样本。 | 记录 `noise-dial start/end`, context deadline/取消/错误类别和 elapsed；不记录 endpoint。 |
| HTTP 80 → HTTPS 443 | `control/controlhttp/client.go:288-339` | 端口 80 先行；443 在 **500 ms** 后并行。不是 30 秒机制。 | 低，只可能是亚秒增量或由单次 Noise 10 秒 deadline 包住。 | 仅记录 transport 分支（80/443）及耗时桶。 |
| IPv4/IPv6 race | `net/dnscache/dnscache.go:550-645` | 多地址每 **300 ms** 启动下一条；IPv6 优先交替。 | 低，除非所有候选被同一更大的 context/系统连接等待阻塞。 | 仅统计 family 和 attempts 数量，不输出 IP。 |
| authRoutine 失败重试 | `control/controlclient/auto.go:305-401`; `util/backoff/backoff.go:47-80` | 不是“固定 30 秒”：第 n 次连续错误等待 `n² × 10 ms` 再乘 0.5–1.5 抖动，单次最多 **30 秒**。约 20 次快速失败的累计 sleep 已约 28.7 秒（未计抖动）。 | 中。只有日志显示重复快速错误才成立；一次连接超时不会自然给出恰好 30 秒。 | 记录 retry index、sleep 毫秒、错误类别；不记录错误原文。 |
| 控制面注册 | `control/controlclient/direct.go:531-793` | `/key` 成功后才创建 Noise client、POST `/machine/register`。无单独 request timeout，受上面的 Noise client context约束。交互登录强制新 node key（`direct.go:554-614`），本地 keygen 本身没有等待 timer。 | 高。AuthURL 就由此 response 带回。 | 记录 register start/end、是否获得 AuthURL 布尔值、elapsed；不保存 URL、node/machine key 或 body。 |
| 服务端自定义 dial plan | `control/controlhttp/client.go:98-170`; `control/ts2021/client.go:208-240` | 只有收到旧 netmap 的 plan 才有；首次全新节点通常无 plan。若有，服务端可配置每候选的启动延迟/timeout，最大整体 **60 秒**。 | 条件性。全新临时 state directory 首发样本不应把它作为首选。 | 记录有无 plan、候选数、最大配置 timeout，不记录地址。 |
| map long-poll/watchdog | `control/controlclient/direct.go:881-884,1023-1051` | 首次 MapResponse watchdog 是 **120 秒**，但在登录成功后的 map routine；AuthURL 之前不走该路径。 | 排除为这次 AuthURL 首发主因。 | 不需为当前问题开启。 |
| tsnet auth URL print loop | `tsnet/tsnet.go:908-928` | 仅每 **5 秒**打印已存在的 AuthURL；不产生 URL，不影响 status。 | 排除。 | 不需采集。 |

## 细分实证与当前判断

同一固定 v1.94.1 纯 Go 运行的脱敏事件文件 `/tmp/monkeycraft-ios-tsnet-errors.jsonl` 已进一步缩小范围：

| 相对时间 | 事件 | 排除/保留的范围 |
| ---: | --- | --- |
| 537 ms | `/key` 完成 | 本次 32 秒不是首个控制 key 的 DNS、TCP 或 TLS 等待。 |
| 538 ms | 发出 `/machine/register`；创建 Noise client | 请求已开始。此时已生成一次交互登录的新 node key。 |
| 864 ms | Noise 经 HTTP 80 的连接和握手成功 | 不是 IPv6/IPv4、80→443 race、Noise dial 的 10 秒 deadline，也不是 bootstrap 连接。 |
| 32,172 ms | `RegisterReq: got response`；AuthURL 非空 | 期间没有 authRoutine retry。 |
| 32,251 ms | `Status.AuthURL` 出现 | 状态传播与 UI 轮询只占 79 ms。 |

`direct.go:721-734` 还限定了最后的一个边界：该日志在 `httpc.Do(req)` **和** `decode(res, &resp)` 都结束后才写出；而 `decode` 在 `direct.go:1285-1295` 只是最多 1 MiB 的 `io.ReadAll` 再 `json.Unmarshal`。所以已知的 31.634 秒严格落在两项之一：Noise HTTP/2 POST 等待响应头/首字节，或返回 body 的读取（含极不可能但尚未量出的 JSON 解析）。它不是本地 keygen、控制连接、客户端退避重试、AuthURL 状态 timer 或 Swift/Flutter/loopback。

早先三次基线中也有 21.8/19.9 秒的首发样本；其中一例有若干脱敏 generic error，另一例没有中间 retry 仍在 register 阶段等待约 19.3 秒。

随后根代理的串行 AB 记录补齐了一条直接失败原因：`/tmp/monkeycraft-ios-tsnet-ab/old-explicit-443-1.jsonl` 在 1.234–13.658 秒间记录 **14 次** register response `HTTP 502`，响应的脱敏类别为 `backend not found or not available`，并标注 `reqType=noise-register/machine-pubkey`、`saw=43/44`、`tn=0`；第 28.818 秒才收到带 AuthURL 的成功 response。该字段组合是注册控制面/其前置网关对 Noise register 的结构化失败响应，远强于“客户端猜测网络慢”的证据：客户端已经收到了可解析的 HTTP status 和服务端错误 body。

客户端 v1.94.1 对此没有 502 特例。`control/controlclient/direct.go:721-729` 将任意非 200 response（包括最多 200 bytes 的文本）转成 `register request: http 502: ...` error；`control/controlclient/auto.go:346-360` 把它报告给 `authRoutine` 后立即调用 `bo.BackOff`；`util/backoff/backoff.go:47-80` 对第 n 次连续错误睡眠 `n² × 10 ms × (0.5–1.5)`，单项上限 30 秒。仅前 14 次的无抖动和为 10.15 秒、允许抖动范围为 5.075–15.225 秒，和日志中约 12.4 秒的密集失败区间一致。后续直到 28.818 秒的间隔仍须看完整逐次时间戳，不能把它全部归到一个固定 timer。

因此可以确认的根因层级是：**本次可观察的 AuthURL 延迟由控制面 Noise register 的临时 502 后端不可用响应触发，客户端按官方退避策略重试。** 不能从客户端源码或这条响应再推断具体服务端内部故障（容量、部署、路由、限流或某一后端实例），也不能断言 HTTP 80、iOS、Swift、重复点击或 v1.94.1 单独造成该 502。强制 443、auto/explicit 与新版本的余下 AB 样本是区分网络路径和时变服务端可用性的对照，而不是事先成立的结论。

首次调用时 `tsnet.Server.Start` 已在 `tsnet.go:762-766` 自动请求交互登录；随后应用再调用 `/login-interactive` 会经 `Auto.Login` 取消并重启早期 auth context。该运行中取消发生在约 109 ms，只增加了一个尚未完成的早期 `/key`，不构成 32 秒原因。不过 UI 不应把重复点击当作无代价操作：若在 register 已挂起时重新调用，它会取消该次请求并重新开始。

## 官方资料核对（2026-09-18）

仅检查了 Tailscale 官方来源：公开源码、`tailscale/tailscale` 官方 GitHub 以及官方状态和支持文档。官方 GitHub 有一条跨 Android/Linux 的同文本报告 [#16841](https://github.com/tailscale/tailscale/issues/16841)，记录 `502: backend not found or not available`；该 issue 已关闭，但公开页面没有说明根因或客户端修复。没有找到 `reqType=noise-register/machine-pubkey`、`saw` 或 `tn` 的公开语义，故不解释这些字段。官方状态页在本次查询时显示 Coordination service 正常，不能回溯或否定先前的短暂故障。

官方可采取的升级路径是生成并由用户提交 bug report ID；官方文档说明该 ID 只是在客户端诊断日志中标记时间点，只有用户分享给支持团队后才会被用于排查。对 MonkeyCraft 的客户端边界是：保留 Tailscale 的重试和状态轮询、禁止登录按钮在 pending request 中再次触发取消重启、向用户显示“正在连接/可稍后重试”的非归责状态；不应在客户端伪造 AuthURL、无限缩短官方退避、改写控制面 endpoint 或把该 502 当作本地网络配置错误。真机仍需确认收到 AuthURL 后的 URL presenter 与状态恢复；本轮已证的 502 只覆盖纯 Go/本机注册样本。

## 隔离探针结果与下一步

已在根代理许可的错峰窗口跑过一次隔离 v1.94.1 源码拷贝；项目、模块缓存、iOS 工程和网络配置均未改动。该次在创建 Noise client 后直到 harness 的 45 秒 deadline 都没有返回，`httpc.Do` 最终为 `context canceled`。**第一版 harness 当时只保存了日志格式模板，丢弃了所有数值实参；所以它不能作为“没有 `WroteRequest` 或 `GotFirstResponseByte`”的负证据。** 它只证明纯 Go 注册路径可发生超过 45 秒的变长等待，并非上一条“32 秒成功 response”的阶段分离样本。

AB 完成后又获准运行一次已修正数字白名单的探针，安全计时文件为 `/tmp/monkeycraft-ios-tsnet-probe-events-2.jsonl`。这次 `httpc.Do` 在 45 秒 harness context 被取消时返回，`do_ms=44,552`；记录到 `wrote_ms=324`、`first_byte_ms=323`，但没有 HTTP status、content length、body bytes 或 decode 完成事件。

这两个 `httptrace` 时间**不能**标作 outer `/machine/register` 的 TTFB：`control/controlhttp/client.go:504-529` 明确说明父 request context 上的 trace 会被 Noise dial 内部的 HTTP Upgrade request 使用。它们只证明底层 Upgrade 在约 0.324 秒收到了响应，随后外层 `httpc.Do` 仍未返回。因此本次超时位置收敛为“Upgrade 之后的 Noise handshake，或其上 register 请求/响应”；不能从本探针分开两者，也没有获得一次成功慢响应的 header/body/decode 分段。没有继续发起网络测试，避免污染 AB 和真机验证。

若未来需要继续分段，必须在隔离源码中分别给 `controlhttp.dialURL` 的 `cont(ctx, netConn)` 和 outer h2 RoundTrip 加独立、不可继承的 trace，再错峰运行；当前证据已经足以归因临时 502 与客户端退避，没必要为产品修复继续探测。所有记录仍仅包括数值、status/length/bytes 和布尔值，未包含 URL、host、IP、header 值、body、证书、machine/node key、local API credentials 或 AuthURL。
