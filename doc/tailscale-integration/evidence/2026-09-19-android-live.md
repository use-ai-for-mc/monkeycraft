# Android 模拟器连接真实 Minecraft（2026-09-19）

环境：API36 ARM64 Android Emulator `emulator-5554`；实际 Minecraft 26.2 / ImagineFun Add-Ons，Mod SHA `837404d20f7dd7d8f8428a811fffde0c0d7c58c2d3d8142da1d8b60200724d26`。不是 Android 真机，也不是视频文件回放。

使用 `tool/run_live_native_stream.py` 启动 `integration_test/live_native_stream_lan_test.dart`，连接 `ws://10.0.2.2:9600`，启用 reconnect。密码只存在0600临时JSON和一次性随机loopback路由，不写进dart-define或日志；运行后删除配置和本轮adb reverse映射。

结果：1项通过，约9秒（不含23.2秒构建和安装）。生产 StreamProxy/HMAC、SessionController、Android MediaCodec/Texture链路首次input13/decoded8，重连input10/decoded9，均360×640，输出计数继续增长；退出并释放后native stats为空。日志 `/tmp/monkeycraft-android-live-final.log`。

已考虑实际园区乘车的HIBERNATING状态：休眠结束后才运行视频断言，未将0帧休眠误报为网络故障。

这证明模拟器到真实Mod的生产视频链路与重连，不证明真实手机硬解、完整游戏UI操作、后台音频、VPN共存、Android内嵌账户授权或跨网络远程连接。

随后安装正式Release APK并冷启动，系统返回Status ok/4.396秒，首页可显示。UI检查发现“Connect with Tailscale”仍被旧的iOS-only条件隐藏；已记录为产品入口缺陷并继续修复，不能把原生组件测试通过视为Android产品路径已完成。


## 正式Android内嵌入口修复及实际点击

已将LoginScreen入口条件改为iOS或Android，新增widget测试实际点击入口并验证生产TailscaleLoginSheet及client diagnostics/start路径。完整Flutter176项、完整analyze通过；新正式Release APK SHA `eca32d4d158b45e2ac0c285d011384a8a68a2b05e055216a0f7e6c109c2f253d` 的签名/双ABI/哈希/16KB对齐通过。

ADB覆盖安装后冷启动成功（1.650秒），UI层级中确认首页“Connect with Tailscale”可见；实际点击该按钮后前台切至Chrome，地址栏仅提取host为`login.tailscale.com`，页面可见Sign in/Sign in with Google。证明正式release原生组件确实可加载并产生可打开的登录地址；没有选择账户或执行授权。没有记录AuthURL路径、query、账户或密钥。`uiautomator dump /dev/tty`首次工具提取为空，改用设备临时XML后只输出host/固定标签并立即删除临时文件；这属于UI采集方式问题，非App崩溃。

Android本人账户登录、内嵌到系统/内嵌PC的真实拨号、身份恢复和已有VPN共存仍待用户协助。当前模拟器浏览器停在官方登录页；后续若链接到期，可回App重新打开一次。
