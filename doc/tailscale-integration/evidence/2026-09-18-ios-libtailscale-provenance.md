# iOS libtailscale 既有实现追溯（2026-09-18）

范围：只读核对 Git 全部可达历史、本仓 iOS 依赖目录和既有构建/验证记录；未修改 iOS 工程、第三方依赖、游戏进程或网络配置。

## 可确认的既有实现

现有 iOS 路径确实使用 Go 编译的官方 `libtailscale` C archive，并非 Swift `TailscaleKit.framework`：

| 项目 | 已核实内容 |
| --- | --- |
| 上游源码 | `https://github.com/tailscale/libtailscale.git`，detached commit `80771313ac4127973677c993889fe215abcf1fbd`（上游提交日期 2026-06-08） |
| Go 依赖 | 上游 `go.mod` 为 Go 1.25.5、`tailscale.com v1.94.1`；2026-08-30 的本机构建记录为 Go 1.26.3 / darwin arm64 |
| 设备产物 | `libtailscale_ios.a`，arm64，27,119,712 bytes，SHA-256 `ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9` |
| 模拟器产物 | `libtailscale_ios_sim.a`，x86_64 + arm64，52,911,024 bytes，SHA-256 `41c1b3c0c3f81ccc580989d5d45bc90d94374fd12cfbdd5d5e1dd5ade01f462e` |
| 构建时间 | 现存 `out/MANIFEST.json`：2026-08-30T03:23:48Z；两份 archive 实测哈希与该 manifest、[`IOS_I1_EVIDENCE.md`](../../../flutter/monkeycraft/lib/stream/tailscale/IOS_I1_EVIDENCE.md) 均一致 |
| 链接 | `Link.xcconfig` 对 device 使用 `-force_load libtailscale_ios.a -lresolv`，对 simulator 使用独立 archive；只有对应 archive 存在时定义 `MONKEYCRAFT_HAS_LIBTAILSCALE` |
| 最低系统 | Runner 是 iOS 16.6；未采用需要 iOS 18.1 的 Swift TailscaleKit。C archive 的 clang wrapper 指定 `-mios-version-min=12.0` |

设备构建配方是现有 [`build.sh`](../../../flutter/monkeycraft/ios/third_party/libtailscale/build.sh)：clone/fetch 后 detached checkout 固定 commit，执行上游 `make c-archive-ios`。上游规则实际执行：

```text
GOOS=ios GOARCH=arm64 \
CC=<libtailscale>/swift/script/clangwrap-ios.sh \
go build -v -ldflags -w -tags ios -o libtailscale_ios.a -buildmode=c-archive
```

wrapper 用 Xcode `iphoneos` SDK、`clang -arch arm64` 和 `-mios-version-min=12.0`。模拟器分别构建 arm64、amd64 后 lipo；它没有混入 device archive。

## 原 Swift 调用链

Git HEAD 中的原始实现可在下列文件找到：

- [`TailscaleCBackend.swift`](../../../flutter/monkeycraft/ios/Runner/TailscaleCBackend.swift)：`tailscale_new`、state directory、hostname/control URL、`tailscale_start`，通过 `tailscale_status_json` 读取内存 LocalAPI 状态；交互登录与登出通过 `tailscale_loopback` 建立的 loopback LocalAPI POST；连接桥接使用 `tailscale_dial`。
- [`TailscaleNodeManaging.swift`](../../../flutter/monkeycraft/ios/Runner/TailscaleNodeManaging.swift)：串行状态机、轮询状态、以 `Status.Self.ID` 保存稳定节点身份、仅暴露脱敏的 auth URL host。
- [`TailscaleTransportPlugin.swift`](../../../flutter/monkeycraft/ios/Runner/TailscaleTransportPlugin.swift)：注册 Flutter method/event channel，并仅在编译条件满足时创建 C backend。
- [`TailscaleLoopbackBridge.swift`](../../../flutter/monkeycraft/ios/Runner/TailscaleLoopbackBridge.swift)：只绑定本机、限定选择的 peer 与端口、由 native `dial` 桥接 TCP。

这正是用户所述 Go 自编译 C archive + Swift 调用路径。它不内置或保存可复用 auth key；状态目录位于 App Support 的 MonkeyCraft 专用位置。

## 时间与变更界线

1. Git 全部可达 ref 中，iOS Tailscale Swift 文件最早出现在 `dc26b6642069f5365e8bfddcc5a0e2de75e80522`（2026-09-16）。该提交说明它是“自 2026-08-30 累积”的 Flutter/iOS bridge 快照；其父提交不存在这些文件。
2. 这轮正在修改的工作树相对于 HEAD 的 `TailscaleCBackend.swift` 与 `TailscaleNodeManaging.swift` 是诊断/修复内容（认证 URL 打开完成回调、计时记录、状态去重等）。因此，首轮安装到 iPhone 的 release 包不能被归因于这些随后出现的工作树修改；但也不能据此断言既有实现没有生命周期或环境问题。
3. 本地 `ios/third_party/` 被顶层 `.gitignore` 忽略，`build.sh`、`VERSION.json`、`Link.xcconfig`、LICENSE、manifest 和 archive 都未进入 Git。当前文件与 2026-08-30 记录相符，但 Git 本身不能证明它们在任何历史提交时的字节内容，也不能在新 clone 后自动恢复。
4. 已检查所有可达 refs、reflog 与可见历史；没有找到早于该 Swift 快照的另一套 iOS Tailscale 实现，也没有找到“真机稳定登录”的旧自动化或设备日志。既有 I1 证据只明确了 simulator build，且写明当时未做 device codesign/dyld 或真机验证。

## 可复现性缺口与影响

现有配方能从固定源码 commit 重新构建，也有现存 archive 的 SHA-256 对照；它不是完整可复现供应链：第三方目录及构建脚本被忽略、没有受版本控制的 lock/manifest、没有 CI 重建并核验 iOS archive、也没有历史签名真机产物或登录日志。故可确认“当前库与 2026-08-30 产物一致、原 Swift 路径存在”，但不能仅凭仓库证明“过去曾在某台 iPhone 稳定工作”。
