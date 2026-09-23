# 真实 iPhone 与 26.2 双端内嵌（2026-09-19）

环境：iPhone16e / iOS26.6.2，正式签名Release 1.4.2(11)，保留数据覆盖安装；Minecraft26.2真实ImagineFun实例，macOS arm64 / Java25。当前加载JAR SHA `249a06108fe1b286e37bc4c0630d71afdc98277c45cd6e92563ac7c7f84355c5`，游戏PID18533，helper PID19215。

## 账户与连接

用户亲自授权手机和电脑两个内嵌节点。电脑helper状态running/listening，无鉴权绕过。首先手机选择电脑系统Tailscale节点，游戏端真实socket为系统tailnet地址到手机内嵌地址，证明内嵌→系统路径。手机设备列表只显示名字，用户误把自己的电脑系统节点当成内嵌；随后明确选择`monkeycraft`（手机为`monkeycraft-ios`）。

切换后Java9600连接变为127.0.0.1转发，其对端由helper持有；设备名iPhone、streaming=true，490×960，pendingFrames=0。用户回答“画面正常，可以继续”。前后socket归属核验使用lsof，实际游戏状态由DebugBridge读取。没有将helper的连接计数解释为多个游戏控制者。

## 通知验收中的失败观察

根代理发送`sendNudge(静音测试, …, false)`；发送时game connected/streaming=true。用户回答没有看到提醒，且明确是在MonkeyCraft游戏前台。复测02发送时仍connected=true、pendingFrames=0。权限/横幅/专注模式与客户端路径正在核对，尚无静音或有声通过结论。

## 边界

本证据为真实手机、真实游戏、本人公共tailnet和真实两种连接；不属于模拟器或隔离控制面。尚未证明重启身份、系统→内嵌、Android账户、蜂窝切换、强制中继、锁屏倒计时、园区后台音频或长期稳定性。电脑系统Tailscale原有服务保持运行，不声称已覆盖无系统Tailscale安装环境。

## 通知根因与后续真机结果

用户回读设置为`notification permission not requested yet`。源代码复核：即时NUDGE直接showImmediate，只有定时通知调用ensurePermission；因而首次只用即时提醒的用户从未获得授权机会。发送倒计时A后，用户确认出现权限弹窗并允许、看到测试A。随后授权状态下静音03和A→B更新，用户确认“静音提醒正常，只有测试B”；有声05和取消，用户确认“响了一次，倒计时也已消失”。有声04因发送时连接已经断开，不计为有效样本。

已新增即时权限门控与并发授权共享的源码修复及定向测试，尚未覆盖安装；上述真机成功发生于已授权的当前正式包，不声称新包首次授权已实机通过。90秒锁屏到点测试正在等待用户观察。

90秒锁屏测试结果：用户确认锁屏有倒计时，到点只响一次并显示提醒；解锁返回App自动恢复画面，无需重新登录Tailscale。随后用户主动退出连接，根代理开始电脑重启验收。此时没有正在控制游戏的手机或浏览器。
