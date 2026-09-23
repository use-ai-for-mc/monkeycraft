# 2026-09-19 真实 Safari 提醒听感与后台声音调查

环境为实体 Mac 的普通 Safari，访问既有 HTTPS 入口并连接真实 26.2；没有用 Playwright WebKit 代替。当前 Mod 与嵌入 Flutter 包沿用 `ee2dbc28…` / `57a79829…`。本轮未修改应用代码。

最终结果：用户已确认前台有声与去重、后台有声、静音与去重均通过。此前后台无声由看屏/共享触发的 macOS `displayShared` 通知抑制解释；停止看屏后，系统播放日志与用户听感一致。验收期间系统提示音输出为用户授权的 USB AUDIO。

## 人工反馈

| 测试 | 操作和结果 |
| --- | --- |
| 01、02 | 前台有声提醒，用户未听到。随后设置页实查 Reminder sounds=off；此前漏查了前置设置。 |
| 03 | 正常设置开启声音后，用户确认听到。 |
| 04 | 最小化操作后的有声提醒，用户报告听到且看到系统通知；当时未采样 document.hidden。 |
| 05 | 用户未观察，不作结论。 |
| 06 | 后台静音提醒，用户确认有通知、没有声音。 |
| 07 | 27ms 内两份相同有声提醒，用户看到系统通知但未听到；通知数量未确认，不计去重通过。 |
| 08 | 用户明确将 Safari 放到前台；35ms 内两份相同提醒，用户确认只显示一次、响一次。前台去重通过。 |
| 09 | 用户明确最小化后发送，但未观察，不作结论。 |
| 10 | 后台单条有声提醒，用户确认有通知、无声。 |
| 11 | 仅把系统提示音输出改为 USB AUDIO 后发送，用户仍未听到。 |
| 系统 Boop | 用户确认 macOS 声音设置自带测试音可以听到。 |
| 12 | 全新 tag 的诊断通知出现但无声；发送时 document.hidden=false，且系统 displayShared 静音，不计后台验收。 |
| 13 | 停止看屏，用户明确最小化 Safari；系统记录实际播放，用户确认通知出现、响一次。 |
| 14 | 同样无看屏，用户确认一个通知、无声；系统 isMuted=false、hasSound=false，确认由通知自身静音。 |
| 15 | 无看屏，20ms 内两份相同有声提醒；系统记录一次播放，用户确认一个通知、一声。后台去重通过。 |

04 的一次可听反馈不能覆盖 07、10、11 的失败；这些历史结果保留。根因定位后，以无共享抑制条件下的 13–15 完成后台验收。

## 环境与运行证据

- 网站的 Allow Notifications、Play sound for notification 均 on。
- 系统 Alert volume=100%，Play user interface sound effects=on。
- 原系统提示音输出为 Mac Studio Speakers，而媒体输出为 USB AUDIO（33%，未静音）。用户明确允许将提示音改为 USB AUDIO；改后 AX 读回确认，未改音量。
- 改输出后 11 仍无声，但系统 Boop 可听，因此路由差异不足以解释问题。
- Safari Inspector 实际读回 Notification.permission=granted、`'renotify' in Notification.prototype=false`。
- `getNotifications()` 返回第 11 条，tag 为 `monkeycraft-immediate`、silent=false。后台代码只投递系统通知，不同时播放网页音调。

## 调查过程中的假设与边界

源码为所有即时提醒复用同一 tag，且没有请求 renotify。通知替换是独立于应用去重的行为：[WHATWG Notifications](https://notifications.spec.whatwg.org/)。WebKit 当前 [NotificationOptions.idl](https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/Modules/notifications/NotificationOptions.idl) 尚未启用 renotify；真实 Safari 也未暴露该属性。因此不能假设只加 renotify 就能解决 Safari。

当时计划在同一页面使用新 tag 作对照，保持输出设备、权限与 silent=false 不变。首次自动输入因窗口最小化后键盘焦点未恢复而未执行：控制台没有出现新 tag 发送日志。用户期间报告听到一声，但来源未能对应，不计该对照通过。当时请求用户恢复 Safari 前台以继续检查；后续实际执行结果见 12 和系统日志。

本轮无构建或代码回归测试，因为尚未改应用代码；不会将浏览器调用成功或系统设置开启等同于可听验证。

## 系统静音原因已定位

新tag12后续实际执行，控制台记录发送成功，但当时document.hidden=false，不能计后台通过。用户看到系统通知且无声。macOS NotificationCenter日志对该站点明确记录 `hasSound: true, isMuted: true`；donotdisturbd给出 `reason: display shared`，随后为 `muted by display state (displayShared)`。Do Not Disturb本身为false。故当前捕屏/共享环境触发了系统通知抑制，路由或tag不能作为已证实根因。不得通过在网页后台另播声音来绕过该系统静音策略。接下来停止看屏，再以游戏MCP接口复验；仍待用户听感。筛选后的本站点日志见 `outputs/safari-notification-sound-2026-09-19/system-suppression.log`。

## 停止看屏后的对照13

用户明确最小化Safari后，代理仅通过游戏MCP发送单条NUDGE，未调用CUA或截图。21:04:43系统记录 `outcome: allowed; reason: disabled; interruptionSuppression: none`，紧接 `Playing notification sound`。这与此前 `displayShared` / `Not playing sound` 形成系统级对照；生产代码未改变。此阶段尚待听感确认，随后用户已确认通过。原始证据为 `outputs/safari-notification-sound-2026-09-19/test13-system-events.json`。

用户随后明确确认13的系统通知出现、提示音响一声。后台单条有声已通过；声音中断原因由共享抑制日志及停止看屏后通过的对照证实。继续在无看屏条件复测静音14，以排除先前06受系统整体静音影响的混淆。

用户确认静音14“看到一个通知，但是没声音”。对应21:05:44系统日志为 `Not playing sound` 且 `isMuted:false, hasSound:false`，在无共享静音干扰的环境下静音通过；证据保存于 outputs/safari-notification-sound-2026-09-19/test14-system-events.json。随后同样不调用CUA，20ms内发送两份相同的 `Safari 后台去重确认 15`（sound=true，sentAtMs=1789823327864），等待用户确认通知与声音均只有一次。

用户确认后台去重15“看到了一个通知和听到一次声音”。两份NUDGE的发送间隔合计20ms；21:08:47.993系统仅记录一次 `Playing notification sound`，本站点20条事件见 `outputs/safari-notification-sound-2026-09-19/test15-system-events.json`。本轮前台/后台有声、静音和去重人工验收完成；未采样document.hidden以避免看屏干扰，后台状态依据用户明确最小化及系统通知日志。没有修改通知tag或绕过系统静音规则。

用户随后恢复Safari到前台，确认“画面正常恢复，无需登录”。本轮后台提醒验收结束后，真实Safari画面恢复与会话保留也通过；此时Safari仍占用唯一控制连接，尚未释放。下一项拟补真实手机浏览器验收，先关闭桌面测试标签释放连接。
