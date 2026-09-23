# Android 过期定时提醒重连取证与修复

日期：2026-09-19

## 范围

本记录覆盖 Android 正式旧 f8 包在强制 Doze、恢复和生产 GUI 断开重连后的系统通知状态、随后对 Flutter 定时通知协调器的最小修复，以及新 APK 的同路径现场复验。现场文件只记录 Android 系统中的静音通知和闹钟状态，不能证明设备播放了可听声音。

## 旧包现场证据

倒计时截止时间为 `1789766527465`。

- `outputs/roadmap-2026-09-19-android-doze/forced-idle.json` 显示设备处于强制 idle，ID `990001` 的倒计时仍在，`TimedNotificationReceiver` 的 `RTC_WAKEUP` 精确闹钟目标为 `1789766527465`。
- `outputs/roadmap-2026-09-19-android-doze/idle-after-deadline.json` 显示强制 idle 未解除时，ID `1` 的定时通知已创建，`mCreationTimeMs=1789766527481`，比截止时间晚 `16 ms`；活动闹钟已经清空。这证明闹钟在 Doze 中按截止时间触发到了系统通知层。
- `outputs/roadmap-2026-09-19-android-doze/resumed-immediate.json` 与 `resumed-after-10s.json` 中，该通知的 `mCreationTimeMs` 和 `mUpdateTimeMs` 均保持 `1789766527481`。普通恢复前台没有再次更新通知。
- `outputs/roadmap-2026-09-19-android-doze/old-apk-reconnected.json` 显示，通过生产 GUI 断开并重新连接后，同一 ID `1` 的 `mCreationTimeMs` 仍为 `1789766527481`，但 `mUpdateTimeMs` 变为 `1789766655221`，通知 `when` 也变为 `1789766655220`。这证明旧 f8 包重连时确实重新提交了已经过期的提醒，而非普通前台恢复造成的更新。

上述通知均带 `SILENT`，模拟器也没有提供可听声音证据。因此结论限定为“系统通知记录被创建或更新”，不外推为“用户听到了第二次声音”。

## 最小修复

修复只涉及：

- `flutter/monkeycraft/lib/notifications/timed_notification_coordinator.dart`
- `flutter/monkeycraft/test/timed_notification_coordinator_test.dart`

协调器现在使用可注入的毫秒时钟，并在请求通知权限前、权限异步返回后各检查一次截止时间。冷实例收到已过期状态时，只记录用于去重的 signature，不请求权限、不重新排程，也不取消已经显示的提醒。

用于去重的 signature 与“当前实例确实成功安排的未来提醒”分开记录。只有当前实例确实安排过提醒，且该旧提醒在处理过期更新时仍未到期，才调用现有取消接口清除它。冷实例连续收到不同的过期状态不会取消；由当前实例安排的提醒已经到点后，再收到不同的过期状态也不会取消。服务端后续明确发送空定时状态时，原有显式取消语义保持不变。

操作继续通过串行队列执行，重复状态去重、未来提醒更新、权限拒绝、取消后重新安排，以及取消排在进行中的安排之后等既有语义均保留。

## 自动验证

定向测试：

```text
/Users/cusgadmin/if-local/flutter/bin/flutter test test/timed_notification_coordinator_test.dart
```

结果为 `12/12` 通过。新增回归覆盖：

- 冷协调器收到相同及不同的过期状态时均不安排、不取消，随后显式空状态仍取消一次；
- 已安排提醒 A 到点后收到不同的过期 B，不取消已显示提醒，随后显式空状态仍取消；
- 权限请求等待期间到达截止时间，不在权限返回后立即安排；
- 仍未到期的未来 A 被过期 B 覆盖时会取消 A，之后的新未来提醒和显式取消仍正常。

完整 Flutter 测试记录位于 `outputs/roadmap-2026-09-19-android-doze/flutter-test.log`，结果为 `192` 项全部通过。静态分析记录位于 `outputs/roadmap-2026-09-19-android-doze/flutter-analyze.log`，结果为 `No issues found!`。两个修改文件的格式化和 diff 空白检查也通过。

## 新 APK 产物验证

归档目录为 `outputs/roadmap-2026-09-19-expired-reminder`，APK 为 `MonkeyCraft-1.4.2-11-release.apk`：

- SHA-256 为 `4f5a225b9d7a01b087fa573f6305a93de34aefbdf5a83c4fca6a88270cd355a7`，见 `android-artifact.json`；
- `android-verify.log` 记录 APK 原生校验通过。校验覆盖 APK 只包含 `arm64-v8a` 与 `armeabi-v7a` 两个 ABI、两者的固定 Tailscale 库与清单哈希相符，以及全部 arm64 原生库的 `PT_LOAD` 对齐不低于 16 KB；
- `android-zipalign.log` 记录 ZIP 对齐验证成功；
- `android-signature.log` 记录 APK Signature Scheme v2 验证通过且签名者为一个；
- `android-install.log` 记录 `install -r` 覆盖安装成功并保留应用数据。安装后从设备读取的 APK SHA 记录在 `android-installed-sha.txt`，与归档 SHA 完全一致。

## 新 APK 现场复验

服务端仍保留旧截止时间 `1789766527465` 时，覆盖安装会清除旧通知，因此第一阶段只验证“新 GUI 连接不会重发旧提醒”，不能用来证明旧通知在安装过程中得到保留：

- `new-apk-before-connect.json` 中没有通知或活动闹钟；
- 通过生产 GUI 连接后，`new-apk-reconnected.json` 仍没有通知或活动闹钟；
- 继续等待后，`new-apk-reconnected-after-10s.json` 仍为空。

随后安排新的未来截止时间 `1789767038139`，完成了独立的端到端验证：

- `new-apk-before-idle.json` 与 `new-apk-forced-idle.json` 显示 ID `990001` 的倒计时和目标为 `1789767038139` 的精确 `RTC_WAKEUP`；强制后的设备状态为 `mState=IDLE mLightState=OVERRIDE`。
- `new-apk-idle-deadline-check.json` 显示深度 idle 中距截止约 9 秒时，原闹钟仍在且尚无到点通知。
- `new-apk-idle-after-deadline.json` 显示设备仍在深度 idle 时，ID `1` 的静音通知已生成，`mCreationTimeMs=1789767038148`，比截止时间晚 `9 ms`；活动闹钟已清空。
- `new-apk-resumed.json` 中该通知的创建和更新时间仍为 `1789767038148`，恢复前台没有重发。
- 生产 GUI 断开再连接后的 `new-apk-after-second-reconnect.json` 中时间仍为 `1789767038148`；约 14 秒后的 `new-apk-second-reconnect-after-10s.json` 仍未变化，也没有活动闹钟。这证明新包不会因重连重新提交已经到点的提醒。
- 显式取消后的 `new-apk-explicit-cancel.json` 中通知和活动闹钟均为空。

采集脚本最初在“零通知”场景中遇到解析失败：系统输出没有 `Notification List` 标题，而临时 probe 把该标题当成必需字段。修正空列表解析后取得了上述快照；这是取证脚本问题，不是产品通知失败。

以上 Android 现场结果均来自静音系统记录。测试模拟器 `5556` 已结束；本轮没有触碰保留中的 `5554` 实例。

## iOS 只读审查边界

iOS 新包随后已完成 clean Release 构建（Xcode 48.5 秒）、全部嵌套组件的平台/架构/签名验证，并通过 devicectl 覆盖安装；读回为 1.4.2 (11)。未手动终止或启动手机 App。本节代码审查不能替代新包的 iOS 感知验收；产物与安装记录见 [iOS 清单](2026-09-19-ios-formal-release.json)。

当前协调器在 iOS 成功完成原生排程后才记录实际未来截止时间；提醒到点后收到不同的过期 payload 时不会调用会删除已送达通知的原生取消接口；显式空状态仍会取消待处理和已送达通知，并独立结束 Live Activity；通知权限等待跨过截止时间后也不会进入 Swift 的最短一秒触发路径。Live Activity 使用独立串行队列，因此本次协调器状态变化未改变其创建、更新或显式结束顺序。

仍存在三个未由本次修复引入的边界：应用在后台到点且没有新服务端状态时，Live Activity 可能停留在 `00:00`，直到恢复、重连或显式取消；权限异步结果为拒绝时，过期 payload 不会写入去重 signature，可能重复查询权限；当前抽象无法区分已经送达的通知与被 iOS 延迟的待处理请求，因此选择保护已送达通知时，极端延迟请求仍可能稍后出现。这些边界尚未经过本轮 iOS 新包设备验证。

## 结论

旧 f8 包的过期提醒重发已由系统更新时间复现。新 APK 在新的未来提醒上完成强制深度 idle 到点、恢复、生产 GUI 断开重连、额外等待和显式取消的完整验证：到点误差为 `+9 ms`，重连后通知时间不变且没有新闹钟，显式取消后全部清除。结合 12 项定向测试、192 项完整 Flutter 测试和静态分析结果，Android 过期提醒重放修复已通过源码与现场两层验证。
