# Android 提醒配额与精确定时修复验收

日期：2026-09-19。机器可读证据见[JSON](2026-09-19-android-notifications-runtime.json)，修复前的正式 GUI 失败见[前序记录](2026-09-19-android-production-lifecycle.md)。

## 改动

Android 即时提醒使用16个固定ID槽，依据本App当前活动通知整理较旧的即时提醒。插件重建后仍读取现有通知，旧版无限递增ID也纳入整理；定时提醒1、倒计时990001、音频990002及带tag的系统分组不参与整理。四项配额策略测试包括50多条遗留通知混入保留ID、重建及连续100条提醒后保留最新16条。

设置页新增 Android 专用 `Exact Ride Reminders`。未授权时说明提醒可能延迟，仅点击 Allow 才打开系统特殊权限页；从设置返回后重新查询，授权从否变为是时重新提交尚未到期的当前提醒。过期提醒不重新响，查询失败、迟到查询和恢复失败有处理。保留原有不精确定时降级，没有增加 `USE_EXACT_ALARM` 或自动授予权限。

Android官方说明此特殊权限在较新系统的新安装默认不授予，排程前需要查询，授权后重新排程；撤销权限可能终止App并取消后续精确闹钟。本轮没有在用户手机修改权限。依据：[闹钟指导](https://developer.android.com/develop/background-work/services/alarms)、[Android 14 新安装行为](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)。

## 构建与自动化

- 完整 Flutter **188项通过**，analyze无问题。日志 `/tmp/monkeycraft-flutter-android-notifications-final.log` 与 `-final-analyze.log`。
- Android原生 **11项通过**：登录门控6、音频租约1、即时提醒配额4。日志 `/tmp/monkeycraft-android-notification-unit.log`。
- 首次Release构建24.8秒失败：生成的插件注册文件引用了不可用的 `integration_test` 插件。保留 `/tmp/monkeycraft-android-notifications-release-build.log`。随后完成全量测试，再顺序执行 clean、pub get、Release构建，**54.0秒成功**，未手改生成文件或绕过错误。
- 新包SHA256 `f8bbc80a5c79843fedd79bed3757f2b9d800d8295befc546ee1b2f7753574f53`，归档于 `outputs/roadmap-2026-09-19-android-notifications/MonkeyCraft-1.4.2-11-release.apk`。双ABI、原生manifest哈希、ARM64 ELF/ZIP16KB对齐和apksigner v2通过；仍是开发签名，不是商店发布。

## 正式 GUI 与真实 26.2

环境为独立API36 ARM64模拟器5556，正式App入口，真实26.2 Mod `097d40…`，LAN密码鉴权，未保存密码。替换安装清空了旧系统通知，因此**旧通知迁移仅有单元证据**，不把此次装机称为现场迁移通过。5554待本人Tailscale登录的实例保持不变。

1. 未授权时，设置页实际显示延迟说明；当前倒计时已存在，系统排程窗口约143秒。点击Allow、在Android页面开启权限、返回App后，显示已开启；同一截止时间变成 `window=0 / exactAllowReason=permission`，仍只有一条待发闹钟，倒计时未重新创建。
2. 从实际聊天链接连接新鲜OpenAudio会话后，以350ms间隔经Mod发送64条静音NUDGE。结束时即时提醒16条、全部活动记录20条（含系统分组），第64条存在；倒计时和音频前台通知均保留。没有停用外部ImagineMoreFun的正常周期提醒。
3. 在正式界面按住Sneak，游戏端keyShift=true；按Home后keyShift=false、游戏socket断开，前台包为系统桌面。此后触摸UP仅作输入清理。返回后自动重连、keyShift仍false。
4. 在桌面等待已安排的本地提醒。系统记录alert ID1的创建时间为截止时间 **+3ms**，倒计时990001已消失、音频990002仍在。返回后该提醒的创建/更新时间不变，没有新增同名提醒；重新打开设置确认音频仍连接。该单次设备时间结果不是普遍延迟保证，且未测试Doze长时间节流。
5. 通知压力之后再次创建新倒计时A→B，显示正常；相同B重复不改变原生记录，取消后倒计时与待发Alarm均清零，音频通知仍在。
6. 通过App退出游戏后音频服务/通知和倒计时均清零。PC音频恢复active/connected、pending=false、音量仍0；游戏无手机控制会话、无测试计时。5556正常关闭，5554未操作。

模拟器无声音输出。本轮不声明有声感知、实际连续音频、真机锁屏、VPN共存、网络切换或Android真实tailnet授权通过。系统可能因自动分组追加SILENT标志，不能仅凭该字段判断声音参数错误。首次UI从设置返回时过快点击曾进入命令弹窗，取消后重新读取界面并进入聊天，未发送该空命令。
