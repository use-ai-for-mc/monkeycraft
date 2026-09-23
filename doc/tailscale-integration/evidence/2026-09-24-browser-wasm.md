# 浏览器 WASM / PC Tailscale 联调

用户先确认线上Pages地址直连成功，随后明确要求继续既有WASM方案的真实联调，以评估“在网页登录自己的Tailscale、选择电脑”这条路径。当前线上Pages仍不包含WASM；本轮只在本地实验入口进行。

## 原实现与本轮修复

- 上游为Tailscale v1.102.3，固定提交53a0d659afa51835dd7a9283873cca44261454f8；基于官方cmd/tsconnect/wasm，在Go侧补出dialTcp/read/write/close及稳定节点ID。
- Go运行在Dedicated Worker中，经RPC把TCP数据交给页面。该JS构建的Tailscale网络使用DERP-over-WSS，不走浏览器原生WebSocket直连游戏IP，也不使用Funnel。
- 初始加载的旧WASM SHA256为65c3ba7321d0ad9363faa44f6e374a9bf8133093706b2d46c70b9cca6703731a，配套wasm_exec.js哈希核对通过。运行中保持该Worker，没有刷新已授权身份。
- 本轮用Go 1.26.6重新编译成功，main.wasm大小36,764,111字节，SHA256为60233fb246bb55f8fdeaa477dbfb61b6ab3313da87457c01e5b9ee953d4f7003；不将运行中的旧二进制记录为重编译产物的执行结果。重新解析的go.mod与原wasm-lock/go.mod无差异。
- 补齐JavaScript的大帧解析：原实现遇到64位长度格式直接拒绝；现在支持受4 MiB上限约束的大视频帧。新增TCP→WebSocket适配，正确保留upgrade响应后一起到达的HELLO，并处理TCP拆包、消息分片、ping/pong和关闭。
- 新增live-probe诊断程序，复用已有录像解码及HMAC工具。它不发送移动、点击、聊天或游戏命令，不属于独立网页产品开发。

## 本轮已取得的证据

| 项目 | 结果 |
|---|---|
| 真实Chrome加载WASM | backend=wasm，进入NeedsLogin；本地已缓存资源启动约1秒内完成，不能等同于公网首次下载 |
| 真实Tailscale登录 | 用户批准monkeycraft-web临时节点后进入Running，取得11个peer及稳定ID |
| 真实tailnet TCP往返 | 浏览器WASM→电脑系统节点上仅绑定tailnet IP的测试端口，10字节echo成功 |
| PC内嵌节点→26.2握手 | WASM连接内嵌节点9600，收到真实HELLO，连接及升级约33毫秒 |
| 真实tailnet承载录像视频 | 20.11秒，HMAC双方校验通过，接收199帧、解码197帧、错误0，2,145,249字节；首帧351毫秒，最大解码帧间隔208毫秒 |
| 网络路径旁证 | 系统Tailscale中的浏览器peer CurAddr为空、Relay=sin，录像期间传输计数增加；测试目标为私网IP和临时tailnet端口，没有配置公网转发 |
| 实际26.2认证 | 浏览器WASM→PC内嵌helper→运行中的Mod，HMAC认证通过，收到HIBERNATING；当前ride主动停止视频，首次20秒没有视频帧，不能记真实画面通过 |
| 新增适配回归 | 180,000字节二进制帧、TCP分段、握手与HELLO合并数据通过；超大或不完整帧拒绝检查通过 |
| 既有定向测试 | Node RPC及WS测试通过；Go internal/wsframe、internal/tcpbridge通过 |

真实游戏随后自然结束ride休眠：连接及升级55.9毫秒、HMAC认证成功；首次二进制帧后观察20秒，接收165帧、解码160帧、错误0，共1,296,596字节，最大消息31,572字节、最大解码帧间隔1,987.9毫秒，最终状态ACTIVE。总探测386.75秒，首个解码帧在368.66秒，其中绝大部分是等待游戏主动结束休眠，不能当作连接延迟或连续视频时长。此结果证明真实链路可用，不宣称公网异地性能或无卡顿。

探测结束后Worker连接数为0、Mod客户端连接为false、玩家仍在服务器中。临时浏览器节点已正常Logout，页面显示Stopped；未关闭游戏或主动解除休眠。原始本地日志和测试备份位于outputs/wasm-joint-2026-09-24/；不提交账户身份、完整设备列表、授权URL或游戏密码。

## 与正式产品的差距

当前Worker身份只在内存Map中，刷新即丢失；仍使用临时节点。正式Flutter接入、持久身份、取消/重连/Worker生命周期及手机Safari上的WASM运行尚未完成。本轮不能宣称这些已经通过，也不重新引入声音、倒计时或其他已取消的功能验收。

## 可复现命令与验收边界

从仓库根目录运行：

```sh
node web-tailscale/js/rpc_test.js
node web-tailscale/js/ws-client_test.js
node web-tailscale/js/tcp-websocket_test.js
(cd web-tailscale && GOMAXPROCS=2 /opt/homebrew/bin/go test ./internal/wsframe ./internal/tcpbridge)
GOMAXPROCS=2 GOFLAGS=-p=2 GO_BIN=/opt/homebrew/bin/go bash web-tailscale/scripts/build-wasm.sh
```

以上为本轮实际执行的定向检查；没有重跑原型完整race/fuzz或其他客户端验收。真实浏览器联调需要已授权节点，通过本地POC中的Worker执行live-probe；真实游戏密码未进入浏览器、日志或提交。录像流和真实游戏流均经过真实Tailscale网络，但两端处于同一台Mac，未证明异地网络质量。没有在iPhone Safari上运行本次WASM。

构建后的dist/VERSION.json对应本轮新产物；LOCK.json的artifacts保留旧基线哈希，并非新产物必须满足的哈希。旧基线实际执行与本轮重编译成功分开记账。

下一步只需将这条传输接入现有Flutter浏览器适配层，补齐浏览器节点身份保存及连接生命周期，再做新链路的一次主要功能验收；不重开已接受的声音、倒计时或跨Mod版本矩阵。
