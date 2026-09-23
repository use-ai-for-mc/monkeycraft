# iOS 正式 libtailscale 构建与原生回归记录

日期：2026-09-19。

## 本轮范围

本记录只覆盖正式 iOS C archive 的供应链安全收口和已存在原生状态机的离线回归准备。没有更改 Dart、Android、Tailscale 版本、认证重试或网络超时；诊断 archive 和数值 register hook 不会进入正式构建。

## 正式构建安全覆盖层

- 构建固定 `libtailscale` commit `80771313ac4127973677c993889fe215abcf1fbd`、`tailscale.com v1.94.1` 和 Go `1.26.3 darwin/arm64`。
- 受跟踪的 `ios/third_party/libtailscale/product-userlog-discard.patch` 在临时、干净的源码副本中应用。它把 `tsnet.Server.UserLogf` 设为 `logger.Discard`。
- 这解决了旧 archive 的 `UserLogf=nil` 会回退到 `log.Printf`、使 `printAuthURLLoop` 将完整认证 URL 写到系统控制台的问题。Swift 的 `tailscale_set_logfd(handle, -1)` 仍负责丢弃 backend `Logf`；两者覆盖不同日志通道。
- 构建脚本先清理隔离副本，避免已存在的 `.a` 被 `make` 当作最新产物。它记录 patch SHA、Go 版本与产物 SHA，并在第一次替换前保留旧设备 archive 为 `libtailscale_ios.pre-userlog-discard.a`。该备份和所有二进制仍受忽略规则保护，不进入 Git。
- 脚本在 `fetch` 或 `checkout` 前检查本地源码是否干净，拒绝覆盖人工修改。它运行 `go mod verify`，并把完整模块清单、`go.mod`、`go.sum` 和 BSD-3-Clause 许可证的哈希写入 manifest；这为后续依赖许可证审查提供锁定输入，但不替代发布前的人工许可证核验。

## 指定 Go 工具链

脚本只接受精确的 `go1.26.3 darwin/arm64`。默认使用 `PATH` 中的 `go`，若版本已升级则会失败而不会静默替换。构建机可用 Go 官方下载包装器获得精确版本：

```bash
go install golang.org/dl/go1.26.3@latest
"$(go env GOPATH)/bin/go1.26.3" download
export LIBTAILSCALE_GO="$("$(go env GOPATH)/bin/go1.26.3" env GOROOT)/bin/go"
```

随后运行 `ios/third_party/libtailscale/build.sh ios` 或 `ios-sim`。本机旧 Homebrew Cellar 路径 `/opt/homebrew/Cellar/go/1.26.3/bin/go` 可作为显式 `LIBTAILSCALE_GO`，但不能假定另一台机器也存在；当前 `go@1.26` Homebrew formula 提供的是更高补丁版本，不满足这个固定构建。

## 构建结果

| 产物 | SHA-256 | 说明 |
| --- | --- | --- |
| 旧设备 archive 备份 | `ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9` | 2026-08-30 原始 archive |
| 新设备 archive | `e7ec1d6a54264ab6d1f1f987e236329c952049866648eeb984e11ff86c0b570f` | arm64，来自全新源码目录的最终重建，已应用安全覆盖层 |
| 新模拟器 archive | `290b5195a0922a6c2aa442cf80eb75996c6cd003f475b6c4d4788c8ac135c01e` | x86_64 + arm64，已应用安全覆盖层 |

已检查 device archive 的 arm64 架构和 Runner 所需 C 符号，包括 `TsnetNewServer`、`TsnetStart`、`TsnetStatusJSON`、`TsnetLoopback`、`TsnetDial`、`TsnetSetLogFD` 与 `TsnetClose`。

## 验证边界

- `build.sh link-config` 保持原有链接配置接口，供诊断签名脚本使用。
- 在全新临时源码目录，使用显式 Go 1.26.3 重建 device archive；`go mod verify` 通过。另以含未跟踪文件的临时源码目录验证脚本会在 fetch / checkout 前拒绝覆盖。
- 正常 Release device 构建在独立 DerivedData 中完成，完整 `Runner.app` 的 `codesign --verify --deep --strict` 通过。签名标识为 `com.chenweikeng.monkeycraft`，团队为 `PC7AFJ7S4P`。
- Workbench iPhone 16（iOS Simulator 26.5）上的 `RunnerTests` 为 18 通过、0 失败、1 跳过。跳过项 `testNativeLoginRequestTiming` 要求显式测试开关且会发起真实 Tailscale 登录；本轮不启用。状态机取消、失败重试、注销、认证 URL / key 脱敏和 loopback bridge 的离线测试均在通过项中。
- 模拟器已关机且保留数据。
- 未安装到真实 iPhone，未进行账户登录、网络注册或生产发布。真实账户、前后台网络恢复、身份恢复和完整 Mod 端到端仍待单独验收。

## 设备包 native asset 隔离与预检

- 03:01 的正式 `Runner.app` 未能安装到真实设备：`objective_c.framework` 为 ad-hoc 签名、没有 TeamIdentifier，且同时带有 x86_64 与 arm64 的 simulator (`LC_BUILD_VERSION platform 7`) slice。它与共享的 `build/native_assets/ios/objective_c.framework` 字节一致；其余嵌套 framework 均为 device arm64 且由 `PC7AFJ7S4P` 签名。
- SDK 源码事实是 `nativeAssetsBuildUri` 只按 OS 写入 `build/native_assets/ios/`，不按 simulator/device 或架构隔离；iOS installer 会把当次 hook 输出的多个架构用 `lipo` 合为同一 framework。02:47 的生成记录恰好为 `ios_arm64` 与 `ios_x64`，最终包保留该时间戳。故串行执行本身不能避免已有 simulator 产物被后续未重新安装 native asset 的 device 打包复用。
- 本地独立诊断 Release 的同一 framework 是反例：仅 arm64、platform 2 (iOS device)、并已由开发证书签名，证明 package 可正确生成 device framework。现有错误包不能用补签名修复，因为 simulator slice/platform 仍然错误。
- 最小可重复 release 前置清理是 `flutter clean`（本地 SDK 的实现会删除项目 `build/`、`.dart_tool/` 并清理 Xcode workspace），然后在没有 simulator 构建的窗口重新生成 device Release。若发行脚本需要窄清理，至少必须同时移除 `build/native_assets/ios` 与 `.dart_tool/flutter_build`，以避免 installer stamp 跳过目标重建。
- 新增 `tool/verify_ios_app.py <Runner.app>`，在归档后、安装前拒绝任一 Mach-O 的非 arm64 或非 platform 2 slice，并对 `.app`、`.appex`、`.framework`、`.xpc` 的严格签名与 TeamIdentifier 一致性逐项检查。解析器 fixture 已覆盖 device arm64 与含 simulator x86_64 的 fat binary。它对这次错误 archive 预期失败，对本地独立诊断 device Release 通过。
