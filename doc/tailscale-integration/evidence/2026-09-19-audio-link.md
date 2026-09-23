# OpenAudioMc 真实聊天链接回归

日期：2026-09-19。保留此前原生后台通道、假 WebView 和真机声音验收的独立边界。

## 真实输入与修复

从运行中的 26.2 `ImagineFun Add-Ons` 读取了最近 71 条聊天。三条音频点击事件指向同一个 `session.openaudiomc.net` HTTPS 会话，域名后直接接 fragment，没有 `/`。仅记录链接形态，没有保存实际会话标识。聊天还显示游戏侧音频已连接、音量为 0%；没有替用户调节音量。

Flutter 的旧判断要求字符串以 `https://session.openaudiomc.net/` 开头，因此真实链接未被识别为 App 内音频，而是落入外部浏览器路径。新增共享 URI 判断，IO 与 stub 均接受准确 HTTPS 主机、默认或显式 443、无 userinfo 的地址，不依赖可选的 `/`。会话 URL 原样传给服务，不重写 fragment 或 query。Web 的通用 HTTPS 分支已能打开该链接，本次没有修改 Web。

## 自动化

- URL 正反例覆盖无斜杠 fragment、有斜杠、显式 443、非 HTTPS、其他端口、userinfo 和相似主机；IO 与 stub 使用同一判断。
- `ChatRichText` 实际点击测试确认原始链接进入 `OpenAudioMcService.connect`。
- `flutter test --reporter expanded`：完整 179 项通过，日志 `/tmp/monkeycraft-flutter-audio-url-full.log`。
- `flutter analyze`：无问题，日志 `/tmp/monkeycraft-flutter-audio-url-full-analyze.log`。

## 真实网页夹具

`integration_test/live_openaudiomc_test.dart` 默认跳过；显式提供 `liveAudioConfigUrl` 才会运行。配置由随机路径的一次性本机 HTTP 服务提供，实际会话内容不进入 dart define。测试使用生产 `OpenAudioMcService`、真实隐藏 WebView 和原生后台租约，仅增加观测包装。关闭插件调试日志，输出限于连接事件数、媒体元素数与 Howler 可用性；JavaScript 观测失败会报错，不用零值掩盖。

测试依次等待生产服务连接、调用 `softRefresh` 后复验，并在断开后检查活跃状态和后台租约清零。方法调用不等同于真实切后台或锁屏。页面没有 Howler 时记录不可用；WebAudio 不一定对应 DOM 媒体元素，零元素也不等于没有播放。

运行环境：Workbench iPhone 16、iOS 26.5 模拟器。首轮与诊断轮均在45秒内未检测到连接，不作为通过。首轮日志 `/tmp/monkeycraft-ios-live-audio-first-failure.log`；诊断日志 `/tmp/monkeycraft-ios-live-audio-diagnostic-failure.log`。

诊断轮页面 `readyState=complete`、正文长度396、3个按钮、0个range输入，预期主机匹配，无 `session` query；未发现已知开始按钮或invalid/expired/error文字，服务报告timeout。对照官方匿名页面为398字符、3按钮、0个range。该相似性只是线索，不能据此认定具体失败原因。

同一游戏运行态的PC插件音频为active/connected=true、volume=0。显式执行官方页面提示的 `/audio` 后，服务器回复已连接网页客户端，未生成新链接。现阶段正在隔离既有PC音频会话对新鲜链接验收的影响；没有更改持久音频设置。


## 新鲜会话复测通过

读取实际加载的 `imaginemorefun-3.4.2.jar` 后确认：`OpenAudioMcService.disconnectViaCommand()` 等价于插件 `/oa disconnect`，会取消自动恢复并设为不期望连接；后续聊天链接不会被PC自动消费。临时执行后确认active/connected/pending/manageServerEvents均为false，再请求 `/audio`，服务器生成了与旧链接不同的新会话。没有修改 `enableOpenAudioMc` 或任何持久配置。

iOS 26.5模拟器使用新链接后，真实WebView专项 **1项通过**，测试7秒（另有17.7秒构建）：

- 服务报告连接，INFO connected事件1次，原生后台租约为1。
- 页面DOM媒体元素1个、报告playing的元素1个；Howler不可用，因此未伪造Howler播放计数。
- 调用softRefresh后仍连接，媒体计数保持1/1。
- disconnect后active=false、connected=false、后台租约0。

日志：`/tmp/monkeycraft-ios-live-audio.log`。这证明真实园区页面在模拟器上的连接、刷新方法和释放路径；DOM播放标志不能证明园区曲目确实可听，更不代表真机锁屏、实际后台或音频焦点验收。旧链接两次失败保留，不归因于网络或修改生产超时。复测后调用插件原有 `connectViaCommand()` 恢复电脑音频，音量保持0%。

## 可复用模拟器运行器

`tool/run_live_openaudiomc.py` 仅接受已启动的 iOS 模拟器或 `emulator-*` Android 模拟器，不接受真机。配置文件必须为 `0600` 且只含 `sessionUrl`；运行器只接受准确 HTTPS `session.openaudiomc.net`、无 userinfo、默认或显式 443 的会话地址。会话内容仅经随机的一次性 loopback JSON 路由传递，dart define 只含该本机路由；Android 会创建并在结束时删除自身的 `adb reverse` 映射。

```bash
chmod 600 /private/path/openaudiomc-session.json
python3 tool/run_live_openaudiomc.py \
  --config-path /private/path/openaudiomc-session.json \
  --device <booted-ios-simulator-udid-or-emulator-serial>
```


## Android独立模拟器复测

为保留 `emulator-5554` 的正式App和待用户授权的Chrome登录页，创建了独立 `MonkeyCraft_Audio_Test`（API36、Google Play、ARM64、2GB RAM、软件GPU、无音频输出、不用快照），端口5556。iOS模拟器已关闭，机器64GiB物理内存且未见swap in/out；本次调整先前由代理自行采用的单VM资源策略，不是解除用户限制。

临时通过PC音频既有disconnect接口取得另一个新鲜链接后，Android真实WebView专项 **1项通过**：测试13秒，构建24.1秒。INFO connected事件1次、HTML媒体1/playing1；调用softRefresh后仍连接；断开后active/connected=false、后台租约0。日志 `/tmp/monkeycraft-android-live-audio.log`。同样不等于可听见曲目、真实后台/锁屏或真机；没有登录Tailscale账户。

随后安装了正式归档APK `e843496ea0501e5d7c0f835a02d81acacc471c425762c3e99201bd0081cc12ab`，冷启动1.852秒，uiautomator经Flutter的content-desc确认主页和Connect with Tailscale入口。最初仅检查XML text属性没有匹配；补读语义content-desc后确认，是采集字段遗漏，不作为App启动失败。没有点击新AVD上的Tailscale按钮，也没有新建Tailscale节点。

一次性配置已删除，ADB reverse确认清空。PC音频已恢复active/connected=true、pending=false、音量0。测试AVD已正常关闭，数据保留供后续隔离回归；原5554未修改。启动日志 `/tmp/monkeycraft-audio-avd-5556.log`，正式包安装与冷启动日志分别为 `/tmp/monkeycraft-android-audio-link-install.log`、`/tmp/monkeycraft-android-audio-link-launch.log`。
