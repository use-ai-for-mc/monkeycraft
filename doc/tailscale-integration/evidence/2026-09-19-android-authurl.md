# Android 内嵌 Tailscale AuthURL 契约修复（2026-09-19）

## 根因

Dart `TailscaleLoginSheet._bootstrap` 已只调用 `client.start()`，并提示登录页面会自动打开。固定 Android libtailscale 的 `tsnet.Server.Start` 在首次 `NeedsLogin` 时已经设置 `WantRunning` 并调用 `StartLoginInteractive`（固定 v1.94.1 的 `tsnet.go` 747–771），因此不应由 Flutter 或插件再次 POST 登录。

但 Android `TailscaleTransportPlugin.start()` 只启动节点和发送状态；轮询 `queueEmit()` 只把快照交给 EventChannel，不处理随后出现的 AuthURL。系统浏览器仅在 `loginInteractive()` 内打开，所以首次自动登录流程不会弹出页面。该方法还在唯一 IO executor 上 POST `/localapi/v0/login-interactive` 并最多轮询 40 次、每次 250 ms，会阻塞 status、stop、cancel 和 logout。

## 改动

- 每次状态发送读取 AuthURL；仅接受 HTTPS 的 `tailscale.com` 或其子域 URL。
- AuthURL 首次到达时按当前 generation 自动通过 `ACTION_VIEW` 打开一次；相同 URL 和 generation 的轮询不会重复打开。
- 显式 `loginInteractive` 改为只重新打开已经存在的受信任 AuthURL，不再 POST 或轮询；该显式操作允许重新打开同一页。
- `queueEmit()` 捕获提交时的 generation。cancel、stop、logout 和 dispose 已先递增 generation，故过期任务在 UI thread 执行前不会打开迟到页面。
- Flutter 新增离线登录页契约测试：bootstrap 即使获得已有 AuthURL 仍只调用一次 `start`，从不调用 `loginInteractive`；原有测试继续覆盖 AuthURL 出现前不宣称网页已打开、出现后可显式重新打开和快速重复点击只发一个重开请求。

没有新增账户、Auth key、控制面 URL、真实节点、登录请求或模拟器安装行为。

## 验证

| 命令 | 结果 |
| --- | --- |
| `flutter test test/stream/tailscale/tailscale_login_sheet_test.dart test/stream/tailscale/tailscale_models_test.dart` | 11 项通过 |
| `flutter analyze` | 通过，无诊断 |
| `flutter build apk --debug` | 通过 |
| APK 内容检查 | 两 ABI 均包含 `libtailscale_jni.so` 与 `libtailscale_monkeycraft.so` |
| `git diff --check`（本次 Kotlin/Dart 变更） | 通过 |

这是离线编译与契约验证，不能证明真实 Android 账户授权、浏览器 handler、网络、后台恢复或 tailnet ACL 行为。

## 生命周期回归与原生单测

复审发现初版自动打开实现还有两处问题，已在本轮修复：

- `closeNode()` 令 handle 变为负数后仍调用 `emit()`；若 `emit()` 无条件读取 native status，会把正常 stopped 快照错误变成 `status_failed`。现在 handle 不存在时直接发送原有 stopped 快照，不读取 native LocalAPI。
- `start()` 原先在 native start 返回后取“当前” generation；若 start 已排队、随后主线程先收到 cancel/stop，旧 start 会被赋予新 generation 并可能打开 AuthURL。现在 start 接收方法调用时捕获的 generation，开始前和 native start 返回后均核验；已失效时关闭新 handle，不发布状态或打开页面。

`AuthUrlLauncher` 是生产插件实际注入并调用的 UI dispatch 层，接收 generation、dispose、UI runnable 与 Intent opener。它不是平行镜像：`TailscaleTransportPlugin.openAuthUrl` 直接委派给它，主 App 编译验证了该接线。纯 Kotlin 单测延迟执行 UI runnable，覆盖同 generation/URL 自动去重、start 排队后 generation 变化、dispose/stop 的迟到 runnable，以及每次显式重开同一 URL。

| 命令 | 结果 |
| --- | --- |
| `JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew :app:testDebugUnitTest --tests com.chenweikeng.monkeycraft.AuthUrlLaunchGateTest` | 6 项通过 |
| `flutter test test/stream/tailscale/tailscale_login_sheet_test.dart test/stream/tailscale/tailscale_models_test.dart` | 11 项通过 |
| `flutter analyze` | 通过，无诊断 |

原生 unit test 的 CI 命令为 在 `flutter/monkeycraft/android` 执行 `JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="$JAVA_HOME/bin:$PATH" ./gradlew :app:testDebugUnitTest --tests com.chenweikeng.monkeycraft.AuthUrlLaunchGateTest`；本轮未改 workflow。

本次原生单测初版曾有两项 generation 初始化错误，未真正排队 UI runnable；已修正为先设置 generation=10/7、断言 queued runnable 数为 1，再变更 generation 或设置 disposed。最终原生单测为 6 项通过。Intent opener 失败被捕获并转换成 `auth_url_open_failed` 事件快照，不会让主线程崩溃；失败后的同 URL 自动轮询既不重新打开也不清除失败状态，只有显式重开实际成功后才清除。用户仍可通过已有“重新打开登录”操作重试。

`emit()` 的 stopped 分支现在在 IO executor 中捕获 stopped 快照，并以 expected generation 检查后才在 UI thread 投递，避免 UI thread 读取 native status，且不让旧 emit 覆盖 stop/cancel 后的状态。`start()` 以方法调用时的 generation 进入和返回 native start 后二次验证；已取消的 start 关闭刚创建的 handle，不发布旧状态或 AuthURL。

## 失败状态保持

浏览器打开成功的 UI 回调才清除 `authOpenError`。自动轮询先经 URL/generation 去重，因此同 URL 的重复轮询不会清除失败提示；`closeNode()` 和新节点生命周期开始时清除旧提示。新增原生用例按顺序验证：打开失败、重复自动轮询不排队、不改变失败计数、显式重开成功。

## API 36 模拟器接线复验

在保留 AVD 数据、未登录账户的 `MonkeyCraft_Roadmap_Test`（API 36、arm64）上，使用 `-crash-report-mode disabled -no-metrics -no-snapshot -gpu software -no-audio` 启动唯一实例。更新后的 `flutter test integration_test/android_tailscale_native_test.dart -d emulator-5554` 两项通过。

内嵌节点场景在既有 EventChannel 订阅内，stop 后以 5 秒 timeout 等待 `phase=stopped`；任何 stop 后 `phase=failed` 会立即令测试失败，第二次幂等 stop 后还检查本段事件中没有 failed。该运行实际通过，说明本次插件接线发出了 stopped EventChannel 快照，未复现此前 handle 已关闭时误报 `status_failed` 的回归。它仍是模拟器上的离线节点生命周期验证，不代表 Android 真机、浏览器 handler 或真实 tailnet 授权。

测试结束后用 `adb -s emulator-5554 emu kill` 正常关闭，并确认设备已从 adb 列表消失。
