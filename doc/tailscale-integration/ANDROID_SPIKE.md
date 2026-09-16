# Android 内嵌 Tailscale：阶段 A（证据包 / spike）实施方案

状态：**已批准的调研结论 + 待执行的实施计划**。本文件只覆盖 MOBILE.md 第 5 节要求的复核包（阶段 A）。
未过 Go 门槛前，不写产品 JNI、不改 Dart、不改 MainActivity、不改 mods/ 和 iOS Runner。

## 1. 决策记录（调研结论摘要）

### 1.1 路线：libtailscale C API（c-shared）+ JNI，与 iOS 同契约

- 与 iOS 使用**同一个 libtailscale pin**：commit `80771313ac4127973677c993889fe215abcf1fbd`（`tailscale.com v1.94.1`，BSD-3）。
- Android 产物形态为 `-buildmode=c-shared` 的 `.so`（Android 用动态库，iOS 用 c-archive 静态库，C 契约 `tailscale.h` 相同）。
- 版本对齐说明（2026-09 确认）：iOS 钉 `v1.94.1` 是因为这是能复现编出 C archive、且不抬高 iOS 16.6 最低版本的包装层；电脑/Web helper 直接用 `tailscale.com v1.102.3` 的 tsnet。两端版本不一致不影响进同一 tailnet；Android 沿 iOS 的 libtailscale pin，**不为了对齐 v1.102.3 而 fork 升 go.mod**。若未来要对齐，须等上游 libtailscale 升版或 fork 后重编 iOS `.a`，另行决策。

备选（产品化阶段再评估）：自有小 Go 包 + gomobile AAR，bridge 放 Go 内并可复用 `native/tailscale-helper/internal/forward`。本阶段不构建它，但 §3 的 overlay 与真机结论对它同样适用。
排除：从 tailscale-android 整仓拆 backend（围绕 VpnService 设计，维护成本最高），仅将其 Kotlin 侧 `GetInterfacesAsJson` 作 fallback 参考。

### 1.2 #17311 的解法：官方 hook，不是 Go patch

- 根因（源码级确认）：Android SELinux 拒绝 `untrusted_app` 打开 `NETLINK_ROUTE`；Go stdlib `net.Interfaces()` 走 `NetlinkRIB`；`netmon.New()` 在 `tsnet.Start` 内 eager 枚举接口（v1.94.1 `netmon.go` 与 v1.102.3 同位置均未改），error 直接使 `Start` 失败。Issue [#17311](https://github.com/tailscale/tailscale/issues/17311) 至今 open；v1.94.1/v1.102.3 均未修。
- 解法：构建时向 libtailscale 源树**叠加一个自有文件** `android_netmon.go`（`//go:build android`），在 `init()` 中调用公开 API `netmon.RegisterInterfaceGetter(...)`（v1.66.0 起，官方 Android app 同款 hook）。实现策略 stdlib 优先、`EACCES` 时回退 cgo `getifaddrs(3)`（bionic 底层 `ioctl(SIOCGIFCONF)`，`untrusted_app` 允许；上游 PR [#19455](https://github.com/tailscale/tailscale/pull/19455) 同法已在 Pixel 8 Pro / Android 16 实测 tsnet 全链路）。
- 同一 init 中调用 `envknob.SetNoLogsNoSupport()`，关闭 tsnet 默认的 log.tailscale.com 上传（Play Data safety 项，记录进证据包）。
- 边界：不改 tailscale 任何一行代码、不改 Go toolchain、无 replace directive、可复现、全部 SHA 入 manifest。**禁止**采用 #17311 报告者那种编译 Go 源码 + CL 507415 的做法（属任务书定义的 No-Go patch）。
- 退出路径：上游 #19455 合入或 bradfitz 的 tsnet rework（去除启动期接口枚举）落地后，overlay 整体删除；升级 pin 时首先检查此项。

### 1.3 已完成的本机编译验证（2026-09-02，编译级证据，非真机证据）

| 项 | 值 |
| --- | --- |
| 源码 | 本仓 `flutter/monkeycraft/ios/third_party/libtailscale/src` @ `80771313` |
| 工具链 | go1.26.3 darwin/arm64、NDK r27 clang API 24（spike 正式构建改用 NDK 28.2 复测并记录差异） |
| arm64 | `GOOS=android GOARCH=arm64 CGO_ENABLED=1 -buildmode=c-shared` 一次通过；未 strip 31.7 MB，`-ldflags "-s -w"` 后 22.6 MB |
| armeabi-v7a | `GOOS=android GOARCH=arm GOARM=7` 一次通过；未 strip 30.2 MB |
| 导出符号 | `nm -D` 确认 `tailscale_new/start/up/status_json/loopback/dial/listen/accept/close/errmsg/getips/set_*` 共 18 个齐全 |

结论：编译与 ABI 不构成风险；剩余风险全在真机运行时（SELinux、Doze、厂商 ROM 差异）。

## 2. 固定版本与工具链（构建时写入 manifest）

| 项 | 值 | 来源 |
| --- | --- | --- |
| libtailscale commit | `80771313ac4127973677c993889fe215abcf1fbd` | 与 iOS pin 一致 |
| tailscale.com Go module | v1.94.1（libtailscale go.mod 自带，不改） | 同上 |
| Go | 构建机 `go1.26.3`（go.mod 要求 ≥1.25.5） | 实测 |
| NDK | 28.2.13676358（= Flutter 3.41.2 默认，本机已装） | `flutter.ndkVersion` |
| API level | minSdk 24（clang 目标 `*-linux-android24-clang`）/ compileSdk 36 / targetSdk 36 | Flutter 默认 + app build.gradle.kts |
| AGP / Kotlin / Gradle | 8.11.1 / 2.2.20 / 8.14 | settings.gradle.kts、wrapper |
| ABI | arm64-v8a（必须）、armeabi-v7a（app abiFilters 含，必须给结论） | app build.gradle.kts |
| 产物命名 | `libtailscale_monkeycraft.so`（避免与其它 app 的系统库名冲突） | 本计划 |

## 3. 交付物 1：可复现构建脚本

位置：`flutter/monkeycraft/android/third_party/libtailscale/`（新目录，不动 iOS 目录）。

```text
android/third_party/libtailscale/
├── build.sh                  # 本计划 §3
├── overlay/
│   └── android_netmon.go     # 构建时拷入 libtailscale 源树的 additive 文件，§4
├── spike/                    # 最小 repro 独立 Kotlin app，§5
├── VERSION.json              # 格式对齐 ios/.../VERSION.json
├── LICENSE                   # BSD-3（libtailscale 上游许可证副本）
└── out/                      # .gitignore；产物 + MANIFEST.json + .sha256
```

`build.sh` 流程（对齐 `ios/third_party/libtailscale/build.sh` 与 `native/tailscale-helper/scripts/build.sh` 的模式）：

1. clone/fetch libtailscale 并 `checkout --detach 80771313`（与 iOS 同一 pin；`LIBTAILSCALE_SRC` 可覆盖）。
2. 把 `overlay/android_netmon.go` 拷入源树根（package main 同包），记录其 sha256。
3. 逐 ABI 构建：
   - arm64：`GOOS=android GOARCH=arm64 CGO_ENABLED=1 CC=$NDK/.../aarch64-linux-android24-clang go build -buildmode=c-shared -ldflags "-s -w" -trimpath -o out/arm64-v8a/libtailscale_monkeycraft.so .`
   - arm：`GOOS=android GOARCH=arm GOARM=7 ... CC=$NDK/.../armv7a-linux-androideabi24-clang ...`
   - 构建后 `llvm-strip --strip-unneeded`（若 -s -w 已足够可省略，以实测大小为准并记录）。
4. 每产物写 `.sha256`；汇总 `out/MANIFEST.json`（commit、Go/NDK 版本、overlay sha256、每 ABI 的 sha256/bytes/构建时间），格式照 helper 的 manifest.json。
5. 校验导出符号表含 §1.3 的 18 个符号，缺失则构建失败。

产物 `.so` 不进 git（`out/` 忽略）；脚本 + overlay + VERSION.json + MANIFEST 模板进 git。

## 4. 交付物 2：overlay `android_netmon.go` 设计

约 120-150 行，`//go:build android`，`package main`（与 libtailscale 同包编译）：

- `func init()`：
  1. `netmon.RegisterInterfaceGetter(androidSafeInterfaces)`
  2. `envknob.SetNoLogsNoSupport()`
- `androidSafeInterfaces()`：先 `net.Interfaces()`；成功则照 `netmon.netInterfaces` 默认逻辑包装返回；`errors.Is(err, syscall.EACCES)` 时走 `getifaddrsInterfaces()`。
- `getifaddrsInterfaces()`：cgo 调 `getifaddrs(3)`，遍历 `struct ifaddrs`，产出 `[]netmon.Interface`：名称、flags（up/broadcast/loopback/pointtopoint/multicast/running）、AF_INET/AF_INET6 地址与前缀长度（sockaddr → `net.IPNet`，AF_INET6 处理 sin6_scope_id 丢弃 zone）。跳过无地址项，`freeifaddrs` defer。
- 参考实现来源：上游 PR #19455（DCO 签署提交至 tailscale，作者明示可 BSD-3）；我们自行重写并在文件头注明出处与许可证。
- Go 单测（`android_netmon_test.go`，linux 可跑主体逻辑）：sockaddr 转换、flags 映射、stdlib-first/EACCES 分支（注入 fake）。
- 已知缺口（写进证据包）：不实现 Android-safe `DefaultRoute`（上游 android 路径读 `/proc/net/route`，实测可读）；不覆盖接口枚举之外的潜在 netlink 调用（PR #19455 作者未观察到其它调用，真机 logcat 专项盯 `netlinkrib`/`EACCES`）。
- Fallback（仅当真机证明 getifaddrs 信息不足时启用）：Kotlin 侧实现 `GetInterfacesAsJson`（ConnectivityManager/LinkProperties，参考 tailscale-android），JNI 回调注册。启用与否及原因必须记录。

## 5. 交付物 3：最小 repro（spike app）

**独立 Kotlin 裸 app，不走 Flutter、不进 monkeycraft app**，位于 `android/third_party/libtailscale/spike/`（单 activity + 4 按钮 + 滚动日志，约 300 行）。

> 关键约束：`adb shell` 里跑 Go 二进制是 `shell` SELinux context，netlink 不受限，会产生假阳性。**所有结论必须来自 app 进程（untrusted_app）。**

- JNI shim（约 120 行 C，`spike` 内 `externalNativeBuild` 编译）：
  `Java_..._tailscaleNew/Start/SetDir/SetHostname/SetControlUrl/SetLogfd/StatusJson/LoginInteractive/Logout/Dial/Close`，逐一转发 `tailscale_*`；`dial` 返回 fd int。
  （ shim 属 spike 脚手架；产品化阶段再决定保留 JNI 还是换 gomobile。）
- app 流程按钮：`Start`（stateDir=app noBackupFilesDir 下子目录，hostname `monkeycraft-android-spike`，control=官方，logfd=-1）→ 轮询 `status_json` 打印 `BackendState`/`AuthURL`（AuthURL 只打 host）→ 用户手动 `LoginInteractive` + 系统浏览器打开 AuthURL → `Running` 后打印 `Self.ID` 与 peer 摘要（数量、在线数，不打 IP）→ `Dial` 到用户填入的 `<tailnet 主机>:9600` 并做一次 HTTP/裸字节收发断言 → `Close`。
- 生命周期用例：登录中杀进程重启（state 恢复）、`logout` 后 state 目录已删除、Start 前后 logcat 无敏感串。
- 日志：logcat tag `MCTsSpike`；完整原始日志留开发机（不进 git），脱敏摘要进 §7 证据。

## 6. 交付物 4：真机矩阵与通过判据

| 设备 | 目的 | 必过项 |
| --- | --- | --- |
| arm64 / Android 16（或手边最新，untrusted_app） | 覆盖 #17311 场景 | Start 无 `netlinkrib`；登录→Running→dial :9600 字节往返→close |
| arm64 / API 29-33 任一台 | stdlib-first 分支 | 同上 |
| armeabi-v7a 真机（若有） | ABI 结论 | 同上；若无设备，证据中明示缺口与风险评估 |

每项记录：设备/ROM/API、Go/NDK/产物 SHA、登录耗时、DERP 还是 direct、dial RTT 量级、logcat 中 `netlinkrib|EACCES` 出现次数（目标 0）、杀进程恢复、logout 清理。Wi-Fi/蜂窝切换、Doze 各做一次粗测（精确性能数据不属本阶段，留给产品化阶段对照 M0 基线）。

Go 判据（对齐 MOBILE.md §5）：无私有 Go patch；两 ABI 可稳定 Start/Close；交互登录+单端口 dial 通过；无 VpnService/权限新增/流量劫持；构建脚本+SHA+许可证齐全。
任一项失败 → 整理成 No-Go 证据（复现命令、logcat、建议用户路径：装 Tailscale App + 地址栏填 100.x/MagicDNS，或 LAN），停止，不留半成品入口。

## 7. 证据包组织

- 脱敏摘要与决策：追加到本文件 §8（执行后填写）。
- 产物与 hash：`android/third_party/libtailscale/out/MANIFEST.json`（不进 git，git 内由 VERSION.json 记录 pin 与 overlay sha256）。
- 原始 logcat/抓包：开发机受控保存，**不进 git**（TEST_MATRIX.md §9 要求）。
- 文档只写脱敏值：AuthURL 只留 host、不留 tskey/私钥/完整 IP。

## 8. 执行结果（待填）

### 8.1 可复现构建（2026-09-02，编译级，非真机）

命令：`flutter/monkeycraft/android/third_party/libtailscale/build.sh`

| 项 | 值 |
| --- | --- |
| libtailscale | `80771313ac4127973677c993889fe215abcf1fbd` |
| Go | go1.26.3 |
| NDK | 28.2.13676358 |
| overlay sha256 | `a21e82657515f08d480e7531386d1ea1ea5a162485393a3a3126ced6fc36f191` |
| arm64-v8a .so | 22555640 bytes，sha256 `102183163fd37ce6362e8ce5bb9509881e23ccc8124fc07c2d0a4f5942fccc94` |
| armeabi-v7a .so | 21437540 bytes，sha256 `44bdd2b28bc392e75d34e9aec7e301d6aa839a78947a46b841b7a7d6c115c422` |
| overlay unit | `overlay/convert` `go test` 通过 |
| spike APK | `spike/assemble.sh` → `app-debug.apk` 含两 ABI 的 `libtailscale_monkeycraft.so` + `libtailscale_jni.so` |

完整表见 `android/third_party/libtailscale/out/MANIFEST.json`（目录 gitignore，本地构建生成）。

### 8.2 真机（未跑）

未插机。Go/No-Go 仍待 `untrusted_app` 上 Start → 登录 → dial :9600。

插机后：

```text
cd flutter/monkeycraft/android/third_party/libtailscale
./build.sh
cd spike && ./assemble.sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb logcat -s MCTsSpike
```

## 9. 明确不做（本阶段）

- 不改 Dart（`isSupported` 仍 iOS-only）、不加 MainActivity 插件、不动登录 UI；
- 不改 mods/、iOS Runner、共享 README/MOBILE.md；
- 不申请任何新权限、不引入 VpnService/前台服务；
- 不做产品级 Kotlin 状态机/单测（属阶段 B，契约照 iOS `TailscaleTransportPlugin` 的 method/event 集）；
- 不把 `.so` 或 auth key 提交进仓库。
