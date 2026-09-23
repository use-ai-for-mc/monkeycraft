# 历史快照，不作为待执行清单

2026-09-23用户已改为主要功能验收、取消次要功能测试；当前规则见上级目录现行文档。

# 已发现问题的收尾交接

更新时间：2026-09-23（Safari最新复验见 [真机记录](evidence/2026-09-23-iphone-safari.md)，其他自主收尾见 [收尾记录](evidence/2026-09-21-closeout.md)）。用户要求落盘，供次日或上下文丢失后接续。此页只跟踪已发现问题，不代替完整产品路线和平台支持矩阵。每项完成后更新状态、实际产物、证据和剩余项，不删除失败历史。

## 接手先读

- 主 checkout `/Users/cusgadmin/if-local/monkeycraft`，分支最后核对为 `claude/web-m2-m3`。工作区存在大量已有修改，禁止清理覆盖，不创建 worktree。
- 用户授权优先自主清理本地 Android 模拟器验收，尽量不占用手机。需本人登录、听感或真机行为时留下具体步骤，不将模拟器结果等同真机。
- 不自行 commit、push、PR 或生产部署；Pages 曾有旧范围授权，但新共享 Flutter 候选仍需最终范围确认。
- 历史 Android 自主验收与此次续跑是两批。不要沿用旧 PID 或包身份；接手先探测当前游戏、唯一连接、已安装包。Android 历史系统层结果见 [Android验收](evidence/2026-09-21-android-acceptance.md)，本轮产物与运行结果见 [自主收尾](evidence/2026-09-21-closeout.md)。
- 每次操作前确认唯一控制连接是否空闲，不覆盖用户真实倒计时，不向其他玩家发送测试消息。测试提醒仅使用 MonkeyCraft 本地通知接口。
- 本页第 1、2 项是不同音频问题，不能用其中一项的通过替代另一项。

## 1. iPhone Safari 返回后提示音无声

**状态：已关闭。2026-09-23用户认定Safari完整验收完成、功能正常；提醒功能不再按Minecraft版本重复测试，Android最多简短抽查一次有声/静音。除非静态检查发现具体且重要的风险，不追加本部分测试。**

修复前失败记录：已核对网页JS为26bc49dd；首次Test sound可听，切其他App返回后新有声提醒可听；锁屏返回后“Safari 锁屏返回复测 03”显示但无声。测试02因用户走神不计结果。随后手动Test sound可听，测试04及IMF自然触发的ride完成提醒也可听。目前仅观察到一次本轮锁屏返回失声，不是持续失声或必现；手动测试后的恢复不能视为下次锁屏恢复通过。见 [本次真机记录](evidence/2026-09-23-iphone-safari.md)。

现象：最初 Test sound 和前台有声 NUDGE 可听。切后台返回后画面自动恢复、无需登录，但有声提醒只显示、不响；Test sound 也不响，界面却显示 `Test sound played.`。声音开关保持开启。该文案只证明调用成功，不证明实际输出声音。

用户后来只是退出连接再连接，声音恢复；没有明确刷新整个页面，不能证明加载到修复代码，也不能算修复验收通过。

2026-09-23候选实现：`flutter/monkeycraft/lib/notifications/browser_notification_backend_web.dart` 在页面隐藏时保留已由手势启用的 AudioContext，返回只恢复原实例，不在生命周期事件里新建；300ms检查运行时钟是否停滞，必要时对原实例做suspend/resume，1秒处补一次中断恢复。隐藏/销毁取消待执行恢复；静音偏好仍受尊重，恢复不补播通知。此前直接关闭/重建的实现仍不足以通过本轮真机验收。新候选JS `32617edb`、26.2 JAR `19ea7e9b`，已实际进服并核对HTTPS资源；Chrome33项、analyze、Web Release、26.2 JUnit66项通过，不能替代手机听感。测试位于 `test/browser/browser_reminder_audio_lifecycle_test.dart`。未直接捕获真机失声时的底层状态，Safari 内部根因仍不能表述为已完全证实。

此前部署记录（最新包及共享资源哈希见本轮收尾记录）：26.2 JAR `a56d2814392ef9d9c3b084e3429cbddc1fc2417bfd57cff0c473a281fe0f3927`；Web JS `ca4d7352918dc38fcca37d9338314f159d48b758e12f7308a933dfcf59f5a0c1`。15 项 Chrome 定向测试、4 项真实 AudioContext／合成生命周期检查、analyze、Web build 和 26.2 的 66 项 JUnit 通过。合成生命周期不是 iPhone 真机验收。2026-09-21 三个旧版 Mod 已重建并核对49项资源与 ca4d7352 一致，但新包尚未部署/运行；Pages 候选仍需同步重验。

本轮通过的产物为26.2 JAR `19ea7e9b` / Web JS `32617edb`。用户确认刷新后连接和画面正常、Test sound可听、两次锁屏返回后新提醒可见可听、静音提醒无声、两条相同提醒仅一次且一声、关闭Reminder sounds后sound=true提醒仍无声。手机声音开关最后保持关闭。关闭偏好跨后台未做，不记通过；无需继续要求人工补测。其余三个Mod与Pages的资源同步仍是开发收尾，不将旧包自动记为本候选。

下一项为原生iOS App音频恢复；不再重开本项人工测试。完整证据见 [9月23日真机记录](evidence/2026-09-23-iphone-safari.md)。

证据：[Safari 声音恢复](evidence/2026-09-19-ios-safari-sound-resume.md)；原始输出 `outputs/ios-safari-sound-resume-2026-09-19/`。

## 2. iPhone 原生 App 园区音乐在回前台时中断

**状态：模拟器已定位并验证修复；正常设备修复包未安装、未真机验收。**

现象：OpenAudioMC 前台及锁屏播放正常，解锁回 App 后音乐停，聊天、网络和倒计时正常，设置仍显示 Connected；手动 Refresh 可恢复。故障复现时电脑音频已被临时断开，因此该次不是电脑抢占。

模拟器因果证据：OpenAudioMC 的 `No Sleep` 短视频恢复播放时，实际 detached 音轨被暂停；AudioContext 仍 running。只静音保活视频后通过，恢复视频未静音后再次失败。

实现：`flutter/monkeycraft/lib/audio/openaudiomc_webview_script.dart` 的 iOS 原生文档启动脚本，仅对 `session.openaudiomc.net`、title 为 `No Sleep` 的 VIDEO 在 play 前静音。真实音乐和音量不改，Android／正式网页不注入此兼容代码，不自动刷新网页。

已通过：11 项 JS、12 项 Dart 音频测试、analyze；模拟器修复包锁屏约 71 秒与 Home 后台约 44 秒返回后真实音轨未暂停、时钟推进；显式断开后不复活。这不是修复后的实体手机听感证据。

历史正常设备包归档（本轮新的最终包见 `outputs/closeout-2026-09-21/artifacts/Runner.app`，已验证平台和签名但未装手机）：`outputs/ios-audio-resume-2026-09-19/fixed-device.Runner.app`。Runner SHA `06c2a36381f8a3c8d5bd32e4da3326f49a16b0566b521ef6f96f43aa19c44f7c`，App.framework SHA `988e6554ec1b514601fc2ec642c11ec376388dc1d779cbcbb80bff2a53f6617b`。手机最后记录仍是旧诊断包；接手时重新读回，不能假设正常包已经安装。

下一步：

1. 对照当前源码确认候选包；如重建，使用 `tool/build_ios_device_release.sh`，先归档需要保留的 Android/Web 产物。禁止只凭增量 iOS build 成功认定包有效。
2. 保留数据安装正常包，核对设备包身份；不手动杀手机 App。
3. 临时隔离电脑音频重试并保存原状态，手机使用新鲜 `/audio` 链接经正常 GUI 开始播放。
4. 前台基线 → 锁屏约一分钟 → 解锁返回 → Home 后返回，逐步确认可听，不点 Refresh。
5. 显式 Disconnect 后再前后台切换，不能恢复旧音乐；结束后恢复电脑原音频意图和音量。

通过标准：真实手机正常构建在上述恢复后音乐持续，无需刷新；手动断开有效；正常 GUI 链接入口有效。会话生成失败要单独记录，不误归为回前台修复失败或成功。

证据：[原生音频复现与修复](evidence/2026-09-19-ios-audio-resume.md)；原始输出 `outputs/ios-audio-resume-2026-09-19/`。

## 3. 电脑与手机争抢 OpenAudioMC 会话

**状态：2026-09-21 已实现原生 App → MonkeyCraft INFO → ImagineMoreFun 26.2 自动交接，服务级真实运行通过；物理手机正常 GUI 与异常退出/电脑重启仍待验。**

用户指出 ImagineMoreFun 在电脑打开音频，手机连接后电脑被断开又会重试，可能循环抢占。此前测试调用电脑现有 `disconnectViaCommand()` 暂时关闭连接及重试，测完 `connectViaCommand()` 恢复原意图；原记录电脑音量为 0，但再次操作必须现场读取，不硬编码。

实现已沿用既有 INFO_PACKET API：手机开始导航前报告 active，电脑真正关闭 WebView 并抑制启动和恢复；手机清理后报告 inactive，仅恢复电脑原本的连接意图和音量。传输断线不归还，显式电脑连接可在手机异常退出后收回。连接或刷新失败有释放与再试测试。真实26.2+iOS26.5诊断模拟器约一分钟内电脑不抢占，包含受控断线恢复；手机明确断开后约26秒电脑恢复连接，此后保持稳定。较早一次归还遇服务器结束事件后又恢复，已保留记录，不宣称即时无波动。

下一步：使用本轮归档的正常 iPhone Release，经正常 GUI 和真机听感检查；电脑重启后旧手机会话交互、App异常退出须独立验收。浏览器外部音频不参加所有权协议；旧版电脑音频提供方未自动获得 ImagineMoreFun26.2 的兼容改动。详见 [音频契约](../AudioPlayer.md)。

通过标准：手机音频连接时电脑不会重试抢占；手机明确断开后的电脑行为确定且符合原设置；手机连接失败、网络中断、App 退出、电脑重启不会形成抢占循环或意外复活旧音频。分别记录正常交接与异常恢复。

相关入口：`doc/AudioPlayer.md`、`flutter/monkeycraft/lib/audio/`；证据同上及 [音频 GUI 路径](evidence/2026-09-19-audio-link.md)。本轮已实际接通既有跨 Mod API。

## 4. Android 硬件键盘 E/ESC 关闭背包未通过

**状态：四版库存键修复均已完成真实 Mod 回归；26.2 + Android 模拟器也通过。最新各包和验收轮次见本轮证据，不能混用哈希。**

本轮复现：打开背包后再按 E，`keyInventory.clickCount=1` 积压；按 ESC 后界面被关闭又立即被积压输入重开（队列回到 0）。不是单纯的模拟器注入问题。四版 `InputHandler.java` 已改为打开界面时把库存键直接交给当前界面处理，避免加入 KeyMapping 点击队列，并在统一释放时包含库存键。

26.2 新 Mod `33235b1016b7b60ff08756e9b1b75d23fa22ea7cde6bfc5a1982656772115937` 已部署、重启回 ImagineFun；Android 正式包 `f5326303…` 的 ADB 真实输入通过 E→E 和 E→ESC，桥接读回 screen=null、clickCount=0、inventoryDown=false。按住触控 Sneak 再 Home，桥接读回 shift 从 true 变 false，连接按生命周期释放。下述历史失败保留；后续应记录最终 APK 和更完整回归，而不是再次从未知原因开始。

历史当前 overlay Release APK `39218eaa…` 在 Android 16/API36 ARM64 AVD 经 LAN 真连 26.2，硬件 E 打开 InventoryScreen，但后续自动化 E/ESC 没关闭。Sneak 释放与受控断线恢复另有通过证据，不能替代此项。

下一步：不再重复未知根因排查。最终 Android APK 23c543a3 在横竖屏恢复后已再次通过 E→E；本轮三个旧版已补真实启动、E/ESC、释放、刷新身份和60秒视频回归；发布包哈希及后续补丁分别记录。原失败与修复后状态已保存到 `outputs/android-acceptance-2026-09-21/input-runtime.json`。

通过标准：真实 Mod 端明确观测 E 打开、E 或 ESC 按设计关闭；前后台切换和界面关闭后无卡键。若只能证明模拟器注入受限，保留未覆盖项，不宣称硬件键盘已通过。

相关实现：`flutter/monkeycraft/lib/stream/game_input_controller.dart`、`flutter/monkeycraft/lib/stream/screens/stream_screen.dart`。本轮新增证据写入 `outputs/android-acceptance-2026-09-21/`，完成后补链接。

## 5. iOS Live Activity 到点后可能保留 00:00

**状态：已记录代码边界，尚无本轮最终包真机验证；不等同已复现的新回归。**

应用后台到点且没有新服务端状态时，Live Activity 可能留在 00:00，直到恢复、重连或显式取消。用户确认过锁屏倒计时与到点一次提醒，但没有证明所有情况下 Live Activity 自动消失。

代码核查：Widget 系统计时文本到点停止在00:00；live_activities 2.4.9 的 staleIn 为创建时整分钟，更新不刷新 staleDate。本地通知到点不会执行 App 的 Activity.end，App 被挂起时不能承诺主动结束卡片。已有恢复/过期清理与显式取消测试；不为消除00:00擅自引入 APNs 后端。

下一步：最终包真机分别检查到点、恢复清理、取消和 A→B 更新。到点通知一次与卡片消失分开记录。本轮模拟器缺少可操作的 Simulator.app 且权限对话框未处理，没有新增真实锁屏结果。

通过标准：到点显示行为明确，取消能结束，更新不重复，无过期提醒重播；真实设备证据与平台限制分别写清。记录是否需要保留已完成状态，而不是凭推测强制删除。

证据：[过期提醒修复及 iOS 边界](evidence/2026-09-19-expired-reminder.md)。Android 过期提醒重连不重发已经有历史系统层通过证据，不重新列为未修复缺陷。

## 6. 本轮新增：原生即时通知缺少短时去重

**状态：2026-09-21 Android 模拟器已复现并通过修复后的系统层复验；iOS 最终包回归仍待完成。**

真实 26.2 连续发送两份相同 `MC21 dedupe`，Android 系统产生 ID2008、2009 两条通知，见 `outputs/android-acceptance-2026-09-21/timer-B-repeat.json`。倒计时 B 的重复状态没有重复更新，二者不要混淆。

修复在 `flutter/monkeycraft/lib/notifications/ios_timed_notification_scheduler.dart`，授权后按标题、正文、sound 对一秒内即时提醒去重，最多保留 32 项，投递异常允许重试；相同正文但不同 sound 不合并。此调度层供原生双端及网页共用。新增并发权限返回、窗口过期、不同内容/声音、投递失败可重试测试；相关 20 项定向测试已通过。

本轮新正式 APK `23c543a363a3c5e24b0912c95464a1b6dc45822b499716959ecdf1c5d3448a8d` 已保留数据覆盖安装；两份相同 NUDGE 仅生成 ID2001 一条通知，见 `dedupe-fixed.json`。超过一秒再发送同内容，新增 ID2003，说明正常重复提醒未永久被吞掉，见 `exact-doze-before.json`。完整 Flutter 229 项及 analyze 通过。首次并行运行 Flutter test 与 Release build 导致生成插件注册器含 integration_test 但 Release 依赖不存在；保留失败日志，停止并行后顺序重建通过，不修改生产插件注册文件。

已补权限拒绝/再允许的正式 GUI 验收：拒绝时不投递，随后授权后新 NUDGE 成功投递；Doze 到点后重连不重发也通过。证据见 [2026-09-21 Android验收](evidence/2026-09-21-android-acceptance.md)。下一步：iOS 最终包回归。iOS 原生修复最终包需要一起包含此次改动并回归，不能只安装此前旧归档算最终收尾。

## 7. 本轮新增：Android 模拟器 Chrome GPU 崩溃

**状态：2026-09-21 默认图形环境失败已保存；同AVD的软件渲染对照通过，仍不等于默认环境或真机通过。**

原AVD图形日志显示Apple M2 Ultra OpenGL/Metal转换路径；Chrome133能实际解码共享Flutter网页，但累计出现VideoDecoder错误，系统日志确认Chrome GPU进程退出/重启和大量SharedImage纹理读取错误。原生Android App已独立完成611秒运行，不受此结论替代。

证据 `outputs/android-acceptance-2026-09-21/chrome-gpu-failure.log` 及 [本轮记录](evidence/2026-09-21-android-acceptance.md)。软件对照实际解码1290帧、零解码错误、Chrome GPU失败日志为空；旋转、后台返回、输入释放、系统静音通知投递通过，提醒声音仅调用证据。原模拟器窗口仍有post-worker EGL警告，guest截图和Chrome路径可用。下次本地浏览器测试用 `-gpu swiftshader -no-snapshot-load`，不要重复踩默认图形路径；若要关闭默认环境问题，需要另行更新/验证模拟器驱动。不能用软件渲染通过抹去默认环境失败，真实手机Chrome仍需独立覆盖。

## 8. MCParks真实服务器增量（2026-09-21）

用户提供 `main.mcparks.us` 用于1.19。最终Android Release经正常GUI实际链接连接，Home111.665秒、模拟器熄屏68.471秒及返回、音量恢复50%、单曲停止、Refresh、Disconnect后不复活均有GUI/系统播放器/服务证据。没有真实手机听感结论，不能替代OpenAudioMC故障复验。1.19最终包已在该服通过基础回归；电脑原音频off，未声明此轮验证已有PC音频交接。详见 [本轮收尾](evidence/2026-09-21-closeout.md)。

## 避免重新排查已闭环事项

- iPhone Safari 休眠重复倒计时：修复并经用户刷新后确认不重复，见 [证据](evidence/2026-09-19-hibernation-countdown.md)。按2026-09-23用户要求不再做最终包重复人工回归，资源同步只检查一致性。
- 桌面 Safari 后台有通知但无声：已由系统日志定位到看屏共享触发 `displayShared` 静音；停止 CUA/截图后，有声、静音、去重均经系统日志及用户听感确认。做听感验收时不启用看屏共享，见 [证据](evidence/2026-09-19-safari-reminder-audibility.md)。
- 普通 iPhone Safari 锁屏时无法保证准时提醒是当前产品边界，不把 Web Push/PWA 推送后端作为本轮未经确认的新开发。

## 更新要求

每项追加：日期、设备/系统、构建标识、实际操作、成功或失败证据、下一步。更新本页后同步 `doc/PRODUCT_ROADMAP_EXECUTION.md` 和必要的支持矩阵。历史测试不转算为新包结果；构建成功不等于产品完成。
