# Android 正式 App 界面、后台与通知验证

日期：2026-09-19。原始脱敏观测见[JSON](2026-09-19-android-production-lifecycle.json)。本轮使用独立 API36 ARM64 模拟器 `MonkeyCraft_Audio_Test` / `emulator-5556`，保留原 `5554` 待用户 Tailscale 授权的状态。

## 正式 GUI 与实际 Home 生命周期

安装包为正式 Release `e843496ea0501e5d7c0f835a02d81acacc471c425762c3e99201bd0081cc12ab`，不是集成测试入口。实际界面输入 LAN `10.0.2.2:9600` 与本地游戏密码，未选 Remember password；连接当前 `097d40…` 的 26.2 游戏并看到视频。进入后出现 Android 通知权限提示，实际点击 Allow。

临时调用 PC 插件原有音频 disconnect 接口以获得新鲜 `/audio` 链接，在 App 的真实聊天界面点击 `here`，仍停留 MonkeyCraft，重新打开设置显示 `Audio Connection / Connected to OpenAudioMc`。不是直接调用服务方法或旧链接测试。

关闭设置后按 Home，UI 包名确认为 `com.google.android.apps.nexuslauncher`。从首次后台观测至末次观测至少 53.3 秒，`AudioPlaybackService` 保持 foreground、通知 ID990002 存在；游戏 socket 在后台断开。返回 App 后游戏自动重连，重新打开设置仍显示音频已连接。显式退出游戏连接后服务、音频通知与倒计时通知均不存在，回到首页。随后 PC 音频恢复 active/connected=true、pending=false、volume=0，没有改持久设置。

图像保存在 `outputs/roadmap-2026-09-19-audio-link/android-production-stream.png` 和 `android-production-audio-connected.png`。模拟器以 `-no-audio` 运行，PC 原有音量为0；以上不证明实际可听、后台连续播放或真机锁屏。

## 通知更新与现场失败

- 静音 NUDGE 的原生通知存在，ID2023、title `MC Silent GUI A`、`AUTO_CANCEL|SILENT`。请求有声的另一条 ID2045 也存在，但系统记录同样含 SILENT；本轮不作声音通过结论。
- 相同截止时间的倒计时 A→B 更新使用同一个 ID990001；`when` 保持原截止时间，chronometer/countDown=true。重复发送相同 B 后 updateTime 不变且只有一条。取消后倒计时消失。
- 随后新倒计时 C/D 不显示。首次后台计时探针因找不到倒计时停止；进一步查询发现 App 已有 **50 条**活动通知，系统明确报 `Package has already posted or enqueued 50 notifications. Not showing more.`。这是真实失败，不是测试超时或允许跳过项。
- 约每10秒出现的 `ImagineMoreFun / You are not riding!` 来自已安装外部 `imaginemorefun-3.4.2.jar`，每200个客户端 tick 正常发送一次 sound=true NUDGE。不是代理遗留计时器；没有停用该用户功能。App 的即时通知使用无限递增 ID，堆积至系统上限后会阻碍新倒计时和提醒，已安排限额修复。
- POST_NOTIFICATIONS 已授权，但精确闹钟特殊访问仍为 default。实际 AlarmManager 使用不精确 fallback，首个120秒倒计时的允许窗口约98.206秒。界面尚未解释这种延迟或提供授权入口，已安排单独修复；不宣称到点精度通过。

Android 16 的系统自动分组路径可以追加 `FLAG_SILENT`；`groupAlertBehavior=0` 是默认值。源码核查确认 App 的 sound=true 分支没有调用 setSilent，但本轮没有记录足够系统分组状态来断定该次静音标志的来源。不能仅凭最终 dump 的 SILENT 推断应用发错参数，也不能据此宣称可听声。依据：[AOSP Android 16 NotificationManagerService](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/notification/NotificationManagerService.java)。

此模拟器时钟有偏差：同次采样 host epoch约1789761572、设备epoch约1789761561。到点精度必须比较设备时间与提交给AlarmManager的绝对截止时间，不把宿主机与设备间偏差归为闹钟延迟。

检查使用包名限定的 ADB 服务/通知状态、UIAutomator 的 Flutter content-desc，以及 DebugBridge 的已授权真实 Mod API。通知 dump 仅在内存筛选本 App 的测试标题和状态，不归档完整通知中心、密码或园区会话 URL。
