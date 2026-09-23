# Android 模拟器自主验收与修复（2026-09-21）

本轮在主 checkout 执行，用户要求睡眠期间尽量完成不需本人参与的验收，并先落盘已发现问题。交接见 [KNOWN_ISSUES_HANDOFF](../KNOWN_ISSUES_HANDOFF.md)。本页为本轮结果，不迁移历史测试记分。

## 环境和产物

- macOS Apple Silicon，本机 Android SDK；`MonkeyCraft_Roadmap_Test`，Android 16 / API36 ARM64，`emulator-5554`，内存 2048MB，保留 userdata、冷启动，不操作实体手机。
- Flutter SDK `/Users/cusgadmin/if-local/flutter/bin/flutter`；正式 Release APK，初始当前源码包 `f532630344bb73b42e0db283b1811fbe7bf258f048da21b99fe633fb0ad8369f`，最终含即时去重包 `23c543a363a3c5e24b0912c95464a1b6dc45822b499716959ecdf1c5d3448a8d`，均 `adb install -r` 保留数据安装。已从设备拉取 base.apk，与最终归档 SHA 完全匹配。
- 原 firstInstallTime 仍为 2026-09-19 03:12:19；升级后 LAN 地址与已保存的凭据仍可用，GUI Connect 无需重新输入或配对。凭据未输出到证据。
- Minecraft 最初未启动，经原 Prism 实例 `ImagineFun Add-Ons` 启动，真实加入原服务器 `mp.imaginefun.net`。没有新服务器、聊天广播或角色移动测试。
- Mod 原包 `a56d2814…`；输入修复后 26.2 为 `33235b1016b7b60ff08756e9b1b75d23fa22ea7cde6bfc5a1982656772115937`，已备份旧包、原子替换、正常退出并重启回原服。
- 四版新构建均包含 49 项相同 root Web 资源，逐文件核验零差异；`main.dart.js` 仍为 `ca4d7352…`。这是已构建的网页音频恢复产物，尚未重新编入本轮后来新增的共享即时通知调度层去重。其浏览器 backend 原本已有一秒去重。26.1、1.21.11、1.19 新包只构建，未部署/启动，不能记作新包运行通过。

## 两项实际问题与修复

### 库存按键积压

旧 Mod 在 Android 正式 GUI 中，E 打开 `InventoryScreen`；再次 E 后读回 `keyInventory.clickCount=1`，屏幕仍打开。ESC 后队列归零但仍显示库存：ESC 关闭后积压的 E 又打开它。初始单独 E→ESC 可以通过，故不是 ESC 总失效。

四版 `InputHandler.java` 现在在界面已打开时将库存绑定键直接交给该界面的 keyPressed/keyReleased，不再调用 KeyMapping.click 排队；统一 releaseAll 也释放库存键。26.2 修复包通过 ADB 注入 E→E、E→ESC，均桥接读回 screen=null、clickCount=0、inventoryDown=false；后续最终 APK 横竖屏恢复后 E→E 再验通过。无需用户操作物理键盘。

### 原生即时提醒未去重

真实 Mod 连续两份相同静音 `MC21 dedupe` 在初始 APK 生成两条系统通知 ID2008/2009（`timer-B-repeat.json`）。定时提醒的去重原本正常，两者不是同一故障。

共享 `IosTimedNotificationScheduler.showImmediate` 在授权后按 title/body/sound 对一秒内相同提醒去重，保留最多32项；失败可重试、不同 sound 不合并、一秒后允许再次投递。新增并发授权返回和失败重试回归。最终 APK 两份相同 NUDGE 只生成 ID2001 一条；超过一秒再次投递，新增 ID2003。证据 `dedupe-fixed.json`、`exact-doze-before.json`。共享改动同样涉及 iOS，实体 iPhone 最终包必须纳入并回归；不能把 Android 结果当 iOS 听感。

## 已完成的正式 GUI / 系统层检查

| 项目 | 结果与边界 |
|---|---|
| 保留数据升级、冷进程启动 | 两次覆盖安装成功；地址/已保存凭据保留，firstInstallTime 未变，正常 GUI 可连真实游戏 |
| E/ESC、库存状态 | 原问题复现、修复后真实 Mod 状态通过；库存键无积压/按住残留 |
| 输入释放 | 触控按住 Sneak，桥接 shift=true；按 Home 后连接按设计暂停、shift=false、inventoryDown=false；返回同进程恢复 |
| 受控断线 | 实际 server socket close(4000)，GUI 恢复视频，桥接 connected/streaming=true，无重新输入凭据 |
| 横竖屏 | 真实 GUI Rotate：1080×2400 → 2400×1080 → 1080×2400；服务端请求尺寸 470×960 → 960×398 → 470×960，连接保持 |
| 静音／有声参数 | 静音系统通知带 SILENT；有声初始记录 AUTO_CANCEL、随后系统自动分组出现 SILENT。只记投递/参数，不记实际可听 |
| 即时去重 | 修复后连续重复仅一条，一秒后相同提醒可再次投递 |
| 通知上限 | 30 条不同测试 NUDGE、约550ms间隔，最后即时 ID 数为16，加系统自动分组共17条；未达历史50条上限；后续倒计时仍能创建 |
| 通知权限 | 仅对本测试 AVD 撤销并清除用户决定标记。NUDGE 触发系统弹窗，拒绝后该提醒未投递；另有外部 IMF 提醒随后再次触发弹窗，允许后正常恢复，新的 `MC21 permission allowed` 投递成功。期间无连接的发送尝试明确不计投递 |
| 精确闹钟入口 | 原权限 default，设置明确显示可能延迟；从 App 的 Allow 进入系统页，打开后 App 显示已启用，appops=allow |
| 未授权的延迟边界 | 原不精确闹钟窗口约33.877秒，到点时仍排队；其后实际提醒约晚33.885秒。不是准时通过，保留对照，不绕过失败 |
| 精确提醒深度 Doze | 最终 APK，deadline=1789925648061；强制深度 IDLE 时系统通知创建=1789925648075，+14ms；倒计时已消失、活动闹钟已结束 |
| 到点后恢复与重连 | 相同通知 created/updated 均保持1789925648075；前台恢复、GUI退出重连没有重播。显式取消后清除；Doze/电池测试覆盖已恢复 |
| Tailscale 未登录启动／取消 | GUI 内嵌入口经过 Preparing，自动打开系统 Chrome 的 Tailscale 登录页；返回 App 提示完成登录，Cancel 回首页，随后 LAN 可正常连接。未代用户授权，未证明登录身份保持或混合连接 |

A/B 更新和重复／取消的初始 APK 快照为 `timer-A.json`、`timer-B-settled.json`、`timer-B-repeat.json`、`timer-cancelled.json`：同 ID990001、截止不变；B重复后 updateTime 不变。最终 APK 在通知上限测试后也已追加 A/B 与取消复验，最终 APK 的 `final-timer-B-settled` 与 `final-timer-B-repeat` 完全相同；`final-timer-cancelled` 中 ID990001 和活动闹钟消失，断言见 `notification-assertions.json`。个别发送后立即采样包含旧 active 与新 enqueued 两条同ID过渡记录；不将这种瞬时快照当作稳定重复显示，使用 settled 快照作判断。

## 自动化与构建

原始日志统一在 `outputs/android-acceptance-2026-09-21/`。

- `flutter test test/ios_timed_notification_scheduler_test.dart test/timed_notification_coordinator_test.dart test/browser_keyboard_input_test.dart`：20通过。
- `flutter test`：229通过；`flutter analyze`：No issues found。
- `python3 tool/run_browser_tests.py --flutter /Users/cusgadmin/if-local/flutter/bin/flutter`：28 Chrome 测试通过，包括实际录像 H.264 解码、重置和通知生命周期。这不是 Android Chrome 或真实手机 Safari 证明。
- Android `./gradlew :app:testReleaseUnitTest`：11通过（登录URL去重、通知限额、音频后台服务租约）。
- 四版 `./gradlew spotlessJavaApply build`：26.2 66项、其他各61项 JUnit，无失败/错误/跳过。
- 最终 APK `android/third_party/libtailscale/verify_apk.py`、apksigner、zipalign 通过：固定 Tailscale 库哈希、双ABI、arm64 PT_LOAD/ZIP 16KB对齐、v2签名。签名和构建不能替代功能验收。
- 首次同时跑 Flutter test 与 Release build 时，生成的插件注册器引用 integration_test，而 Release 依赖没有该类，构建失败。保留 `release-dedupe-build.log`；停止并行后顺序重建成功（`release-dedupe-retry-build.log`），未修改生成文件或依赖来绕过。后续共享 Flutter 构建串行。

## 尚未完成及交接

最终 APK 连续观察 611.051 秒，18 次桥接采样均 connected/streaming=true、hibernating=false，进程保持5348，应用 AndroidRuntime/Flutter 错误日志为空。结束前截图有真实游戏画面，正常 GUI Disconnect 后连接释放。系统媒体记录本解码实例 lifetimeMs=641848、video.input.frames=5904、latency.n=5903，尺寸470×960；配置10FPS，不把输入/系统延迟配对计数冒充 Flutter 内部精确解码统计，也不声称20FPS。证据 `native-soak.json`、`native-soak-summary.json`、`native-codec-metrics.txt`、`soak-end.png`。

Android 本人 Tailscale 登录、授权后身份持久化、系统/内嵌混合路径、物理设备音频听感、OEM后台策略、真实蜂窝切网仍未覆盖。iPhone Safari 音频恢复和 iOS 原生园区音频修复真机验收保持待办。此轮不提交、不推送、不发布。


## Android Chrome 追加验收：当前保留失败

同一 AVD 的 Chrome133，ADB reverse仅在本地映射9600，使 `http://127.0.0.1:9600/` 成为 loopback安全上下文；不代表远端LAN HTTP具备相同安全上下文，也不是公开Pages。共享 Flutter root `ca4d7352…`，真实26.2 Mod `33235b10…`。

首次正常配对并显示游戏，返回登录页后使用已保存身份重新 Connect 成功、无需再次配对。系统Chrome网站通知权限和Android Chrome通知权限分别通过原生Allow授予。前台连续两条相同有声NUDGE，振荡器start次数7→8，横幅一次；这不是可听证据。静音样本被外部IMF提醒覆盖，不将初次样本记为静音通过。Home之后延迟读回document.hidden=true，Service Worker getNotifications能读到静音测试且silent=true，但稍后Android通知服务未找到该标题，不能据API记录宣称系统实际投递完成。

该轮观察到一次VideoDecoder错误，随后帧计数继续；之后系统日志捕获Chrome GPU进程退出、GPU重启，以及大量SharedImage/GL_INVALID_OPERATION/glCopySubTexture错误，保留 `chrome-gpu-failure.log`。首次返回方式使用VIEW Intent打开了新的测试标签，故其mc21不存在是夹具选择错误，不计为原页恢复失败；关闭新增标签8、激活原标签7后原页decoded649→719且无重新配对。原始短时解码错误仍未闭环，不将浏览器整体验收标通过。

为单变量环境对照，已正常关闭原模拟器并保留数据，以 `-gpu swiftshader -no-snapshot-load -no-snapshot-save` 重启同一AVD；没有改生产浏览器解码策略或隐藏旧失败。软件渲染对照结果待补。Flutter移动端语义启用需在占位元素中心点击，直接.click没有启用；按本地Flutter引擎实现改正夹具，未改产品。另出现Gboard手写笔教程，已用其Cancel关闭，非产品弹窗。


### 软件渲染对照结果与清理

同一Chrome133、同一AVD userdata、同一生产网页/Mod，改用显式SwiftShader后：实际解码1290帧、decoderErrors=0、errorDetails为空，读取的Chrome GPU/SharedImage相关失败日志为空。横竖屏经稳定等待后实际解码尺寸504×960→960×338→504×960，socket保持1。触控Sneak在桥接上为true，Home后false；确认document.hidden=true再投递静音提醒，SW记录silent=true，Android通知服务也存在对应Chrome记录。随后有声请求的SW记录silent=false，但未采集该条Android系统投递和听感，不外推。回原Chrome Activity（不发新VIEW Intent）hidden=false、帧数750→775、socket仍1；返回后重复两条有声NUDGE使振荡器12→13，仅一次调用，截图实际显示测试横幅。此为API调用证据，不是真人听到一声。

软件对照支持模拟器GPU路径是原崩溃的重要因素，未证明所有真实Android手机不受影响，也未修复默认模拟器驱动。原进程/图形失败及软件对照均保留。SwiftShader启动日志还有模拟器窗口post-worker EGL警告；guest截图可见正常游戏和横幅、Chrome侧未再报原GPU失败，不能将整个模拟器宣称完全无错误。下次本地Android浏览器验收优先显式 `-gpu swiftshader -no-snapshot-load`，不修改生产网页为强制软件解码。

最终证据：`chrome-sw-summary.json`、`chrome-sw-final.json`、`chrome-landscape-settled.json`、`chrome-portrait-restored.json`、`chrome-sw-background-notifications.json`、`chrome-sw-system-notification.json`、`chrome-sw-returned.json`、`chrome-sw-tone-before/after.json`、`chrome-sw-stream.png`。初次隐藏快照在Home动画尚未结束时为false，不计作后台；使用后续真实hidden=true样本。最后explicit Disconnect回登录页，关闭本轮新建的本地测试标签；归还旋转设置（accelerometer_rotation=1/user_rotation=0），移除自建9229/9600映射，关闭模拟器且保留userdata。

游戏关闭前桥接确认connected=false、无待发计时、Shift/Inventory均false、screen=null；本轮自行启动的26.2随后正常退出，DebugBridge端口和游戏进程退出确认成功。没有操作实体手机、提交、推送、PR或部署。下次真机验收需先启动原26.2实例，不能假设HTTPS后端仍运行。
