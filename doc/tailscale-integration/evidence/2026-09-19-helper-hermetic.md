# Go Helper 本机隔离 tailnet 集成记录（2026-09-19）

## 范围

新增 `native/tailscale-helper/internal/engine/hermetic_tailnet_integration_test.go`，以 `integration` build tag 隔离，默认 `go test ./...` 不会启动节点。

测试使用已固定的 `tailscale.com v1.102.3` SDK：`tstest/integration.RunDERPAndSTUN` 在 `127.0.0.1` 创建临时 DERP/STUN，`tstest/integration/testcontrol.Server` 创建临时 loopback 控制面。两个 `tsnet.Server` 的状态目录均位于测试临时目录。测试清空 `TS_AUTHKEY`、`TS_AUTH_KEY`、OAuth/WIF 相关环境变量，并仅在测试进程把 `TS_CONTROL_URL` 设为上述本机控制面；没有读取账户、auth key、系统 Tailscale 节点或真实 tailnet。

## 覆盖

`TestHermeticTailnetHelperForwardRestart` 使用未替换的生产 `backend.NewTsnet()`、生产 `Tsnet.Watch`、`engine.Engine` 和 `forward.Proxy`。第二个独立 tsnet 客户端经同一临时控制面拨入。流程为：

1. 协议 `start` 后生产 Backend 通过 `WatchIPNBus` 到达 `running`，helper 发出带 tailnet IP 与 node ID 的 `listening`。
2. 客户端经该 IP 与监听端口连接，helper 将流量转发至独立的 `127.0.0.1` TCP echo fixture；两轮各自验证完整字节回显。
3. `stop` 关闭监听、watch 与 tsnet；用相同 state directory 重新 `start`，断言 node ID 和 tailnet IP 保持不变，再次字节往返。
4. `shutdown` 取消 helper 生命周期，断言 helper 退出。

首次直接复用生产 Backend 时，Running 通知没有身份字段，导致 `listening.tailnetIp` 与 `listening.nodeId` 为空。修复 `Tsnet.Watch`：仅当 Running 事件缺少任一身份字段时，使用现有 watch context 同步读取一次本地 `StatusWithoutPeers` 并合并状态；读取失败仍传递原通知。该本地 LocalAPI 读取发生在进入监听前，不增加重试、外部请求或产品控制面配置。

这覆盖 production helper、真实 tsnet userspace 节点及 TCP 转发的本机隔离路径；不代表跨设备网络、真实 tailnet ACL、账户登录、移动端权限或生产 DERP 连通性。

## 执行结果

| 命令 | 结果 |
| --- | --- |
| `/opt/homebrew/bin/go test -mod=readonly -tags=integration ./internal/engine -run TestHermeticTailnetHelperForwardRestart -count=1` | 通过，2.119s |
| `/opt/homebrew/bin/go test -mod=readonly -race -tags=integration ./internal/engine -run TestHermeticTailnetHelperForwardRestart -count=1` | 通过，10.366s |
| `/opt/homebrew/bin/go test -mod=readonly ./...` | 通过 |
| `/opt/homebrew/bin/go test -mod=readonly -tags=integration ./...` | 通过 |
| `/opt/homebrew/bin/go vet ./...` | 通过 |
| `git diff --check`（本次 helper 和证据文件） | 通过 |

`hermeticLogBuffer` 以互斥锁包装测试诊断 writer，race 运行没有报告 goroutine、事件通道或诊断缓冲区竞争。

启用该测试标签时，Go 1.26 按 module graph 补齐了 `tstest/integration` 所需的间接依赖，已更新 helper 的 `go.mod` 与 `go.sum`。没有新增产品开关、改动 Serve 配置或引入真实网络凭据。

## 四平台 helper 重建

首次 `scripts/build-all.sh` 未写入产物：PATH 中旧 Go 无法解析 `go 1.26.6`。显式使用 `/opt/homebrew/bin/go` 后重建成功；四个分发目标的哈希均因本次生产 Backend 修复而更新：

| 目标 | SHA-256 | 大小 |
| --- | --- | ---: |
| darwin-amd64 | `f7ca51048fcaeeaaa47e061d56661fb409458ac4c71db4c83f3abb7b73b52a33` | 22113408 |
| darwin-arm64 | `1ea6169659fc3bda71f97fae2baeb06b45aca62ad297521ff757c2dc194029ae` | 20684882 |
| linux-amd64 | `b207a597adc93f5fc77d4d66e2cf222751041a016656a856b632f823a41d8937` | 22286498 |
| windows-amd64 | `ba3d00b3a9424b15eeb3a4f912424fd979ae342d865be7f49bf6862e5486796b` | 22568448 |

本机 arm64 二进制 `-version` 成功，`file` 确认四份产物分别为预期的 Mach-O x86_64、Mach-O arm64、Linux x86-64 ELF 和 Windows x86-64 PE。未改 CI。
