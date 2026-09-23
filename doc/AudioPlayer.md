# 应用内音频

MonkeyCraft 在 iOS 与 Android 上使用无界面的 `flutter_inappwebview` 播放服务器提供的音频会话。当前支持 OpenAudioMc 和 MCParks v1；桌面和 Web 会使用平台特定实现或空实现，嵌入式 WebView 能力仅在 iOS、Android 上启用。

## 入口与 URL 限制

聊天富文本识别并交给对应服务处理音频链接：

- OpenAudioMc 仅接受 `session.openaudiomc.net` 的 HTTPS 会话链接。
- MCParks v1 仅接受 `mcparks.us` 或其子域名的 HTTPS 链接。

MCParks 页面在文档开始时注入一个仅限页面内的 WebSocket 统计钩子，用于设置页显示活动曲目及停止指定曲目。它不在 Flutter 侧解析或播放服务器音频协议；播放仍由页面内的 Howler 完成。

## 生命周期与串行化

两个 IO 服务都共享相同的生命周期规则：

- `AudioWebView` 把真实 `HeadlessInAppWebView` 封装为可替换接口，测试可用假 WebView 控制 `run`、导航、JavaScript 求值与释放的时序。
- 每个服务各有一个 `AudioOperationQueue`。初始化、连接、监测、刷新、断开和释放依次执行，避免并发导航或重复创建 WebView。
- `initialize` 对已存在的 WebView 无操作；创建失败会清除引用，以便随后同一链接可以重试。
- 活动会话再次收到相同链接不会重载；不同链接先断开旧会话再加载新链接。OpenAudioMc 连接或刷新加载失败会释放 WebView 和后台租约并报告非活动，下一次重试新建页面；MCParks 保留自己的失败恢复策略。
- 定时监测每三秒最多排队一次。监测的 WebView 调用完成后会再次确认会话仍处于活动状态，因此断开或切换会话不会被旧监测重新报告为已连接或重新导航。单次 JavaScript 或平台调用异常只报告非连接状态，不留下未处理的异步异常；下一周期仍可继续检查。只有达到连接超时、OpenAudioMc 重连上限或 MCParks 页面报告错误等终止会话的分支，才会停止定时器、清空会话状态并释放 WebView。

`disconnect` 会立即取消后续定时监测，再排队处理当前操作之后的清理。OpenAudioMc 导航到 `about:blank`；MCParks 会先尽力卸载页面内 Howler 实例，再导航到 `about:blank`。`dispose` 还会释放无界面 WebView 并清除保存的会话链接。

## 连接状态、恢复与控制

服务通过现有 `INFO` 包向已连接的 Mod 报告 `openaudiomc` 或 `mcparks` 的连接状态。该状态只表示页面探测到的会话状态，不是系统级音频播放保证。

### OpenAudioMc 电脑／App 交接

原生 App 的 `openaudiomc` INFO 数据包含独立的 `active` 布尔值：它表示 App 正在持有或建立音频会话，`connected` 则表示页面已经连接。App 在创建／导航页面前报告 active=true，断开导航或释放页面后报告 false；建立或刷新失败也释放所有权。游戏传输重连后再次报告当前状态，避免把暂时断线误认为音频结束。

四个 Mod 将认证后的 INFO 转发给既有 `MonkeycraftApi.INFO_PACKET`。消息限制为 8192 字符、非空且至多 64 字符的字符串 title 和对象 data；主线程分发前再次确认它仍来自当前认证连接。未认证连接不能调用该事件。

本地 ImagineMoreFun 26.2 的可选兼容层订阅 `openaudiomc` 的布尔 active：true 会停止电脑 WebView、启动及重试，保留用户原来的连接意图和音量；false 仅在原本希望连接时恢复电脑会话。传输断开不自动归还，避免手机锁屏或短暂断网时电脑抢占。手机异常退出后可用电脑现有连接操作显式收回；电脑重启后的跨设备恢复尚未完成实际验收。此交接需要同时更新 MonkeyCraft App、Mod 和 ImagineMoreFun，不能只更新 App。

浏览器音频使用外部页面，不能可靠观察外部页面关闭，因此不发送原生所有权声明。旧版 Mod 的 INFO 转发已同步，但其他电脑音频提供方没有因此自动获得此兼容功能。

2026-09-21 的真实 26.2 + iOS 26.5 调试模拟器验证了约一分钟电脑停止重试、受控传输断线仍保持手机所有权，以及明确断开后电脑恢复原连接意图与音量。测试通过调试接口调用服务，模拟器停在系统权限对话框，不能当作正常 GUI、锁屏或真机听感验收。完整证据见 [自主收尾记录](tailscale-integration/evidence/2026-09-21-closeout.md)。

- OpenAudioMc 监测范围输入、启动按钮与会话参数。页面尚未开始时会尝试点击页面的启动按钮；会话丢失后最多重载保存链接三次，连续失败或 30 秒未连接会结束会话并通知界面。
- MCParks 监测页面状态文本，并在可用时写入保存的音量。MCParks 音量保存在应用设置中，范围为 `0.0` 至 `1.0`；服务会在页面可用后重新应用它。
- 应用从后台恢复时，聊天与游戏界面都会调用两个服务的 `softRefresh`。若页面探测结果不健康，服务重新加载保存的会话链接并恢复三秒监测。该机制处理 WebView 在后台被暂停或页面状态丢失的情况；它不保证操作系统持续运行 WebView 或持续播放音频。
- 设置页可断开或重新连接 OpenAudioMc；MCParks 设置页可调整音量、查看页面内追踪到的曲目，并请求停止单个曲目。

## iOS OpenAudioMc 的 No Sleep 兼容

OpenAudioMc 当前页面会创建标题为 `No Sleep` 的短视频用于浏览器保活。iOS WebView 锁屏返回时，这个未静音视频恢复播放会让浏览器暂停实际音乐；音乐通常是未挂载到 DOM 的 HTMLAudioElement，因此仅检查页面 range 控件、AudioContext running 或 DOM 的 audio/video 列表无法发现中断。

原生 iOS 服务通过 `openaudiomc_webview_script.dart` 在文档开始时注入兼容脚本：只对 `session.openaudiomc.net` 中标题恰为 `No Sleep` 的 VIDEO，在调用原生 play 前设为静音。保留真实音乐的音量/静音、play 返回值、参数与异常；不自动重放音轨，也不自动刷新会话。其他原生平台与 Flutter 浏览器不注入此修复。这个选择依赖已验证的第三方保活视频标记，若 OpenAudioMc 更改该实现需重新验收。

`MONKEYCRAFT_AUDIO_DIAGNOSTICS=true` 的诊断构建另外观察 Web Audio、DOM 及 detached 媒体和原生会话事件，使用弱引用、有界历史且不记录媒体源/会话URL。正常构建默认不注入诊断脚本。完整故障、原条件→静音→还原对照及修复包证据见 [iOS 音频恢复](tailscale-integration/evidence/2026-09-19-ios-audio-resume.md)。修复版模拟器已通过锁屏/主屏幕返回及明确断开后不恢复；新正常 iPhone Release 只完成构建与签名验证，尚未安装/真机复验。

## 平台配置与验收边界

当前 iOS `Info.plist` 已声明 `UIBackgroundModes` 的 `audio`。本轮新增原生音频会话接线，在园区会话活跃时使用 `AVAudioSession` 的 `playback` 与 `mixWithOthers`，允许和用户其他声音共存；最后一个园区会话结束时解除激活。该接线不证明每个服务器页面或每台设备都会持续播放。

Android 本轮新增 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 声明和 `mediaPlayback` 前台服务，以用户可见的园区音频通知及媒体会话维持活跃生命周期；最后一个会话结束时停止服务。Dart 两个园区服务共用串行租约，避免一方断开时停止另一方。API 36 ARM64 模拟器已验证连续 `start/start` 后服务为前台、类型为媒体播放、通知 ID `990002` 且仅一条通知；连续 `stop/stop` 后服务与通知均消失。该接线不等于真实 WebView 已连续播放，也不承诺尚未实现的锁屏播放控制。

OpenAudioMc iOS 26.5 模拟器的fresh session已验证连接、调用 `softRefresh` 后仍保持连接及断开后园区音频租约归零；页面检测到一个 HTML 媒体元素且处于 playing。独立 Android API36/ARM64 模拟器5556也在13秒内完成fresh会话连接、调用 `softRefresh` 后保持连接，并在断开后报告 active/connected false、租约归零，且检测到一个 HTML 媒体元素处于 playing。5556使用 `-no-audio`，所以此结果不代表实际声音、背景或锁屏播放。此前两次45秒未连接使用了PC仍持有会话的旧链接；临时让PC断开取得fresh会话后通过，随后PC已恢复 active/connected（音量0，未改持久设置）。该现象不足以推断会话token的精确生命周期，也不构成真机可听、锁屏或后台持续播放的证据。

随后Android正式GUI已补实际Home生命周期：聊天fresh链接留在App内，设置显示已连接；Home至少53.3秒后音频前台服务仍存在，返回时游戏自动重连、重新打开设置仍显示音频连接。最新提醒修复包又验证64条NUDGE压力与Home到点期间音频服务/通知保留，返回后连接文案正常；显式退出后服务和通知清零。见[正式GUI与后台证据](tailscale-integration/evidence/2026-09-19-android-production-lifecycle.md)及[最新包回归](tailscale-integration/evidence/2026-09-19-android-notifications-runtime.md)。这些仍是无声音输出的模拟器结果，不能证明后台连续可听或真机表现。

真机验收仍需分别覆盖：首次页面播放、切换不同会话时旧音频停止、断开后不再恢复旧会话、后台后回到应用的恢复、OpenAudioMc 重连上限、MCParks 音量和单曲停止，以及 iOS/Android 的实际声音、锁屏与省电策略表现。测试中的假 WebView 只能验证调用时序、去重、取消和错误恢复，不替代真实页面与真实设备的音频验收。

## 2026-09-21 MCParks实际服务器补验

用户提供1.19服务器 `main.mcparks.us`。最终Android Release在API36 ARM64模拟器通过正常聊天链接进入MCParks，实际area循环曲目、Home111.665秒、熄屏68.471秒及返回均有GUI和系统播放器/前台服务证据；音量改动后恢复50%、单曲停止清空、Refresh重新连接、明确断开后不复活均通过。声音未由真人确认，模拟器不等于真实手机或iOS，电脑原音频为off不算已有会话交接。详见 [本轮记录](tailscale-integration/evidence/2026-09-21-closeout.md)。
