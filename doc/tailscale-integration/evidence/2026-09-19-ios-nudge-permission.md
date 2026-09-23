# iOS 即时 NUDGE 通知权限修复（2026-09-19）

## 实机触发条件

物理 iPhone 上的 Release `1.4.2 (11)` 已建立双端内嵌连接并正常显示画面。服务器发送静音 `NUDGE` 时，服务端连接、流状态和发送队列均正常，但前台没有系统横幅。用户在应用内通知状态确认看到 `Notification permission not requested yet`。

该状态与代码一致：即时 `NUDGE` 过去直接调用 `showImmediate`，只有定时 `TIMED` 的协调器会请求系统通知授权。纯即时 NUDGE 会在未请求授权的状态下提交 iOS 本地通知，但系统不会显示它。`sound=false` 仅使 iOS 内容不设置声音；前台 delegate 仍请求 banner 和列表展示，静音不是横幅缺失的原因。

## 修复

`IosTimedNotificationScheduler` 现在以一个共享的在途授权 Future 同时服务即时 NUDGE 和定时通知。即时 `showImmediate` 先等待授权成功，拒绝时返回而不提交本地通知。Future 完成后即清除，不缓存 `false`，所以用户随后在系统设置授予权限时，下一次 NUDGE 或定时通知会重新读取系统授权结果。

`StreamScreen` 等待即时通知操作并吸收平台调用异常，避免权限拒绝或原生提交失败形成未处理异步异常。没有添加新的通知表面；系统通知仍是唯一表面。

## 验证

执行：

```text
flutter test test/ios_timed_notification_scheduler_test.dart test/timed_notification_coordinator_test.dart
flutter analyze lib/notifications/ios_timed_notification_scheduler.dart lib/stream/screens/stream_screen.dart test/ios_timed_notification_scheduler_test.dart
```

结果：9 项测试通过，静态分析无问题。新增测试确认两个并发调用共享一次未完成的授权请求，首次返回拒绝后下一次调用再次请求并可返回授权；不支持原生通知的平台不发起请求。现有定时通知协调器的 7 项排程、去重、取消和串行测试继续通过。

## 仍待验收

本次没有操作实体 iPhone 或 Minecraft。根代理重新构建并安装后，需在 iPhone 上触发一次前台即时 NUDGE，确认系统授权弹窗、授权后静音横幅显示，以及用户拒绝或以后在设置中授权的行为。
