# Live Activity 倒计时串行修复（2026-09-19）

## 发现

本地 `live_activities` 2.4.9 插件将 `createOrUpdateActivity`、`updateActivity`、`endActivity` 和 `endAllActivities` 分别发到独立的 MethodChannel 调用，插件本身不对这些调用排序。原服务同时存在三个可复现风险：初始化未结束时到达的倒计时被直接丢弃；开始路径仅按截止时间去重，导致同一截止时间的标题、正文、声音或倒计时文本更新被上游忽略；create/update/cancel 可并发，让较慢的 create 在 cancel 后重新显示活动。

## 修复

`LiveActivityService` 现在把初始化、create/update 和 cancel 串行排入单一操作链。初始化期间排入的事件会等初始化和旧活动清理完成后执行。活动去重改为完整显示内容签名，只有原生 create 或 update 成功后才保存签名，因此失败的相同请求可以重试。取消清除签名并在队列中位于先前 create 后，避免过期 create 在 cancel 后复活。

`StreamScreen` 的订阅去重也改用同一完整 `TimedNotification` 签名；同一截止时间的标题、正文、声音或倒计时文本变化会重新进入定时通知和 Live Activity 路径，取消仍保留单独处理。

## 验证

执行：

```text
flutter test test/ios_timed_notification_scheduler_test.dart test/timed_notification_coordinator_test.dart test/live_activity_service_test.dart test/notification_models_test.dart
flutter analyze lib/notifications/notification_models.dart lib/notifications/ios_timed_notification_scheduler.dart lib/notifications/live_activity_service_io.dart lib/stream/screens/stream_screen.dart test/ios_timed_notification_scheduler_test.dart test/live_activity_service_test.dart test/notification_models_test.dart
```

结果：19 项通过，静态分析无问题。新增延迟 fake 覆盖初始化期间收到事件、同截止时间内容变化、create 后排队 cancel 不复活、create 失败后同内容重试。通知模型回归确认完整签名在标题、正文、声音和倒计时文本变化时不同。

## 范围

这是服务层和本地插件契约验证，没有操作实体 iPhone、Minecraft、Android 模拟器或真实网络连接。仍需在重新构建的 iPhone Release 上验收锁屏中的 Live Activity 创建、更新和取消。
