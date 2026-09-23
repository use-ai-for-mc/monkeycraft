# Android 通知与倒计时系统状态取证

日期：2026-09-19

## 范围

本次只验证 Android 原生通知在本地 Android API 36 模拟器中的系统记录。模拟器以 `-no-audio` 启动，因此不能据此验收真实设备的声音播放或锁屏展示。

新增的集成夹具是 `flutter/monkeycraft/integration_test/android_notification_system_test.dart`。它只在测试中通过既有 `monkeycraft/notifications` MethodChannel 发出两条即时通知、启动后更新一次倒计时，并对同一个定时 ID 连续排程两次；它等待 25 秒供 `adb dumpsys` 读取，再取消倒计时和定时通知并等待 20 秒供第二次读取。产品 UI 与原生产品代码没有加入调试入口。

## 代码对应关系

- `NotificationsPlugin.kt` 的 `scheduleTimed` 用通知 ID 作为 `PendingIntent` request code，并使用 `FLAG_UPDATE_CURRENT`；`cancelTimed` 同时取消该 `PendingIntent` 和该 ID 的通知。
- `NotificationSupport.kt` 的倒计时固定使用 ID `990001`，`startCountdown` 与 `updateCountdown` 都通过同一 ID 发布；倒计时通道为 low importance、`sound=null`、关闭振动。
- 即时通知使用 timed 通道。`sound=false` 调用 `setSilent(true)`；`sound=true` 不设置该标记。通道本身为 high importance，并使用系统默认提示音。

## 执行与结果

模拟器以以下参数启动，避免产生可听见的提示音：

```text
-avd MonkeyCraft_Roadmap_Test -crash-report-mode disabled -no-metrics -no-snapshot -gpu software -no-audio
```

测试执行命令：

```text
cd flutter/monkeycraft
/Users/cusgadmin/if-local/flutter/bin/flutter test integration_test/android_notification_system_test.dart -d emulator-5554
```

测试在 47 秒完成，结果为 `All tests passed!`。测试安装后的临时测试实例由本机 `pm grant` 获得 Android 13+ 通知权限，随后使用以下系统快照检查：

```text
adb -s emulator-5554 shell dumpsys notification --noredact
adb -s emulator-5554 shell dumpsys alarm
```

在取消前的通知快照中：

- `fixture-silent`（ID `2001`）的原始 flags 包含 `SILENT`；`fixture-audible`（ID `2002`）的原始 flags 不含 `SILENT`。两者都属于 `monkeycraft_timed`，其有效通道是 high importance 并配置默认系统声音。
- `fixture-countdown-updated` 只出现一个 ID `990001` 的通知；它使用 `monkeycraft_countdown`，记录显示 `sound=null`、`defaults=0`、`ONGOING_EVENT|ONLY_ALERT_ONCE`、`chronometerCountDown=true` 和约五分钟的 timeout。这证明更新覆盖固定 ID 的倒计时记录，未再增加第二条倒计时通知。
- 闹钟快照中只有一个活动的 `RTC_WAKEUP` 条目，tag 为 `com.chenweikeng.monkeycraft/.TimedNotificationReceiver`。夹具在同一 ID `9131` 上连续排程两次，因此该单一活动条目证明第二次排程替换了前一次，而没有增加活动闹钟。

取消后的通知快照不再包含 `fixture-countdown` 或 ID `990001`。取消后的闹钟活动区不再包含 MonkeyCraft 的 `TimedNotificationReceiver`；历史区保留一条 `Reason=alarm_cancelled` 的该 receiver 快照，这是 AlarmManager 的取消历史，不是活动闹钟。

## 限制

Android 可能在前台策略下将最终显示记录附加 `SILENT` 标志，因此本次以原始 flags 验证 `sound` 参数是否传递给 builder，而不把模拟器快照当作实际声音已播放的证明。模拟器明确禁音，也没有验证物理手机的声音、通知权限交互或锁屏呈现。即时通知没有对应的产品取消 API，夹具的取消断言只覆盖定时通知和倒计时。
