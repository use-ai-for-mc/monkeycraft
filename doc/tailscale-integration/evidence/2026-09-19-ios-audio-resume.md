# iPhone 音频回前台中断：真实设备失败与诊断

## 已复现的用户反馈

- 原有效 Release Runner SHA `369feb4e4f8c918e2d69d22e35fa3be7242a211a98113618d7d7ed67408d44c6` 已覆盖安装。
- 手机已通过通知静音/有声、同截止倒计时更新/取消、锁屏到点一次与解锁恢复；这些通过项不代表音频也通过。
- PC IMF 音频原先 active/connected=true、volume=0。为避免两端抢占，使用其现有 `disconnectViaCommand()` 临时停止电脑连接及重试，持久配置不变。
- 手机第一次 `/audio` 生成会话失败，第二次成功；原因未确认。
- 点击新链接后服务器确认连接，用户听到园区音频。
- 锁屏接近一分钟，用户确认持续播放。
- 解锁回 App 后声音停止；画面显示 hibernation，聊天、倒计时正常，服务器确认手机游戏连接存在。
- 同时 PC IMF active/connected/pending/managesServerAudio 全部 false，因此此次中断不是电脑已抢回音频。
- 手机设置仍显示 `Connected to OpenAudioMc`。点击一次 `Refresh` 后用户确认声音恢复。

结论：锁屏持续播放通过，本次回前台音频恢复失败；手动完整刷新可恢复。尚未证明具体的系统或网页媒体中断原因。

## 已核对的代码事实

`OpenAudioMcService._softRefresh()` 在前台恢复时仅检测音量 range 控件，控件仍存在便不采取恢复操作。周期连接指示也依赖该控件，并不证明音频正在播放。设置页 Refresh 则调用完整 `reconnect()`、重载保存的页面。

`H264DecoderPlugin` 的创建/销毁只处理视频解码与纹理，本地实现未设置 AVAudioSession；不能仅凭时间相近归因为视频解码器。

WebKit 的[媒体恢复 API 定义](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.h)区分媒体暂停与播放恢复；历史[回前台 AudioContext 问题](https://bugs.webkit.org/show_bug.cgi?id=263627)只作为诊断线索，不等同于已确认当前 iPhone 的系统缺陷。

## 诊断包

仅在 `MONKEYCRAFT_AUDIO_DIAGNOSTICS=true` 的构建启用 Dart 采集。记录前台恢复前后和周期媒体状态（paused/ended/time/volume/readyState、媒体流轨道状态），以及原生应用生命周期、AVAudioSession interruption/route change/category/output volume。

本地最多保留160条记录到 `Library/Caches/monkeycraft-audio-diagnostics.json`，不收集音频URL、会话参数、聊天、媒体源URL、设备/轨道名称。正常构建默认不启用。诊断包暂不修改自动恢复行为，不能写成已修复。

构建入口使用 clean 设备包装脚本并透传 dart-define；原有效 Runner、49项Web资源与Pages验证资源已备份到 `outputs/ios-audio-resume-2026-09-19/preserved/`。新增诊断依赖使此前73文件Pages候选与当前工作区不再完全一致，原候选仅保留历史验证，不得直接把旧哈希当当前源码发布。

本轮静态分析通过，现有音频服务/后台租约9项测试通过；诊断Release设备构建47.8秒并逐嵌套验证通过，已覆盖安装、未卸载或清数据；读回1.4.2(11)。Runner SHA `bf0ecae0447c221cfa685cbf61791158a0687d68fa099e0c3551fed2d66598c0`、App.framework SHA `80990bcf989eef4a960d6a22cb19bda9a4c9d0659b05c4a5ae8d35f5029bd168`。此前Web两目录已按空缺恢复；此诊断包不同于此前已通过通知验收的369feb包，新真机音频复现待续。PC音频仍临时关闭，需在手机音频明确断开后恢复电脑原连接意图与原音量0。


## 诊断v1真机复现

用户在诊断包重新连接并使用新鲜链接，确认前台声音正常；锁屏超过30秒仍播放；解锁回App后再次确认音乐停止，未点Refresh。已取回 `foreground-baseline.json`、`locked-baseline.json`、`foreground-interrupted.json`。

- native-active 时间1789815574079；随后17ms开始foreground-before，range=true、connected=true。
- 系统category保持Playback、输出Speaker、音量0.25、leaseActive=true；恢复点没有记录到原生session interruption或route change。
- HTML只有一个短循环media，解锁后paused=false，但这并不代表园区音乐的Web Audio graph。锁屏期间用户仍听到音乐，HTML元素却可显示paused=true，进一步说明单看该元素不足。
- native-interruption在恢复后约21.7秒才出现，不能倒推为恢复瞬间的打断原因。
- PC IMF再次确认active/connected/pending/managesServerAudio全部false，手机游戏连接true。

v1证据可排除已记录的电脑抢占及恢复瞬间类别/路由切换，仍不足以确定Web Audio内部状态。已在显式诊断构建加入弱引用AudioContext观测（保持原构造/实例语义，不自动resume），最多观察8个上下文及12次状态变化。另有固定的一次性诊断动作：只有开发机明确放入App私有Caches的 `monkeycraft-audio-resume-once` 标记才消费并尝试resume暂停/中断的上下文，不重载网页、不自动循环、不读取标记内容；正常构建不启用采集/消费。

测试：Node诊断观察/恢复3项通过，音频Dart9项通过，analyze通过。Node初次拒绝Promise测试过早检查跨realm微任务，改为等事件循环后通过；不是产品代码异常。v2 clean设备构建进行中。

v2诊断包clean构建46.0秒、逐嵌套设备签名验证通过，已覆盖安装并读回1.4.2(11)。Runner SHA `fa069d28ac7f2104cf4b9f907f85d227f3eceef1f311744a251e416c36bbd915`，App.framework SHA `031ab5f250bc1802b143a5b1f705a024f2fc6182e28ecd7924639ca8fc17de68`。无自动恢复，未投放一次恢复标记；需新会话创建时捕获AudioContext，不能复用旧进程对象。主build/Web目录已按空缺恢复，v1包/现场都保留。


## 转入模拟器自主诊断

用户明确要求尽量不用实体手机；后续转到既有 Workbench iPhone 16 / iOS 26.5 模拟器（实体 iPhone 为 26.6.2），通过 `127.0.0.1:9600` 连接真实 26.2。正常 App GUI 配对成功、聊天发送 `/audio` 获得新鲜链接并启动音频；用户确认能听到模拟器声音。PC IMF 再次确认 active/connected/pending/managesServerAudio 全 false，volume=0。没有使用 Tailscale，也未继续操作实体手机。

通用 `flutter build ios --simulator --debug` 在 thinFramework 报 `arm64 x86_64` 架构匹配错误；保留 simulator-build.log。改用指定设备的 `flutter run --debug --no-pub --dart-define=MONKEYCRAFT_AUDIO_DIAGNOSTICS=true` 后构建22.7秒成功，不修改 SDK/架构配置。当前 Xcode 的模拟器由 Device Hub 承载；独立模拟器窗口的 Controls → Lock 能产生 native-inactive/native-background。

模拟器初次运行另发现键盘预热的 `fontSize: 0` 触发 Flutter StrutStyle debug assertion；改为仍在屏幕外透明的字号1，待热重启验证。此缺陷不直接解释已有 Release 音频故障。

模拟器前台采样确认实际捕获到一个 AudioContext，state=running，currentTime持续推进，初始自动启动后没有诊断 resume。HTML短循环元素与 Web Audio 为不同状态来源；采样存 simulator-foreground-baseline.json。下一步锁屏/回前台测试。


## 模拟器已定位：No Sleep 视频在回前台时暂停实际音轨

用户确认模拟器初始有声、第一次锁屏返回后声音停止。AudioContext仍running且时钟推进，原生category/route保持不变。进一步读取 OpenAudioMc 上游源码（只读 clone 到 outputs，未执行其代码）发现实际音乐使用 detached HTMLAudioElement，document.querySelectorAll漏掉它们。经显式诊断脚本捕获play/pause/currentTime，确认两条实际音轨在后台持续推进，解锁同一时刻由浏览器触发pause事件，没有网页JavaScript pause调用；DOM内只有标题No Sleep的1.034秒VIDEO（playsInline=true、muted=false）同时恢复play/playing。此处不是AudioContext suspended。

通过Flutter VM Service连接仅模拟器进程读取对象、安装诊断脚本；未走Tailscale，也未操作实体手机。首次GUI链接的AX文本点击没有触发，独立Device Hub窗口坐标点击成功。原始日志及故障状态均先保存，再刷新网页安装完整观察。

因果对照（同一个模拟器音频会话，不更换网络或登录）：

1. 原条件：`simulator-detached-locked.json`中两条detached音轨paused=false；`simulator-detached-after-unlock.json`均paused=true，pause时间1789817187465，无pause-call。
2. 独立重复：`simulator-causal-paused.json`中音轨2/3暂停。只显式play这两条（未刷新页面、未重建context/会话）后`simulator-causal-resumed.json`中paused=false且时钟推进。可听恢复的用户补充仍待回复。
3. 只把No Sleep视频muted=true：锁屏并返回后`simulator-muted-video-after-unlock.json`中两条真实音轨保持paused=false，未发生新的pause事件。
4. 改回muted=false再锁屏返回：`simulator-unmuted-after-unlock-again.json`中两条音轨再次paused=true。由此形成原条件失败→单变量静音通过→还原条件再失败的证据。

修复收敛为iOS原生OpenAudioMc WebView的文档启动脚本：仅在session.openaudiomc.net、仅标题恰为No Sleep的VIDEO调用play前设muted=true；音频对象及其他视频不改。保留原play返回值/参数/异常；不自动重放音乐、不自动刷新、不修改用户音乐音量。Android与正式Flutter浏览器不注入此兼容代码。正常构建不包含诊断脚本；重新构建的模拟器App验证进行中，实体iPhone尚未复验修复。

Node诊断及兼容脚本11项通过；补齐正常iOS/其他平台/显式诊断脚本组装测试。此前一次新增测试写入因工作目录错误未创建，已更正后执行11项，并未把只跑3项的初次输出当新测试通过。


## 修复包验证与收尾

- 指定模拟器重新构建13.3秒成功，正常App GUI经127.0.0.1使用已保存身份重连26.2，无重新配对。新进程没有键盘预热字号0断言。
- 新构建最初两个GUI音频链接尝试退回Web登录页/30秒超时；之后一条约149秒旧链接直接调用也停在登录页。保留 `fixed-app-start-failed.json`，当时compatibility已安装但没有媒体play调用、没有AudioContext。会话后端原因未确认，不据此推断固定token寿命或声称全部启动尝试成功。
- 最后重新取得服务端刚生成的链接（调用时约22秒），经Flutter调试器调用运行中正式App的同一个 `OpenAudioMcService.connect` 成功。后续回归没有再手工改页面状态或执行恢复。这个步骤走正式服务实现，但不是一次新的GUI点击成功证据；首次改造前GUI入口成功记录单列保留。
- `fixed-app-connected.json`确认兼容脚本存在，保活视频自动muted=true，两条真实音轨muted=false/paused=false。`fixed-app-lifecycle-diagnostics.json`记录native-background→native-active的锁屏间隔71.086秒、Home后台43.151秒（inactive起算44.459秒）；对应 `fixed-app-after-unlock.json`、`fixed-app-after-home.json`的真实音轨均未新增pause事件且时钟推进。
- 从正式设置点击Audio Disconnect，界面音频连接项消失；再次Home/返回后，VM对象字段isActive/isConnected/backgroundSessionHeld全部false，原生foreground-before记录leaseActive=false。没有恢复旧音频。随后正常Disconnect回登录页，服务器clientConnected=false。
- 本轮修复后没有得到新的用户听感回复，因此上述修复包结论为真实模拟器网页音轨/生命周期证据；初始有声与修复前中断有本人听感，实体手机修复后仍未测。
- 模拟器与调试进程已正常停止，保留userdata。原PC IMF调用connectViaCommand后读回active=true/connected=true/pending=false/volume=0，恢复原意图，未改持久设置。26.2继续在原服，无控制端占用。PC/手机自动音频所有权交接仍是独立未完成项。

本轮命令与结果（非历史迁移）：

- `node --test tool/test_audio_context_diagnostics.mjs tool/test_audio_media_diagnostics.mjs tool/test_openaudiomc_ios_compatibility.mjs`：11通过。
- `flutter test test/audio/audio_services_io_test.dart test/audio/audio_background_session_test.dart test/audio/openaudiomc_webview_script_test.dart`：12通过。
- `flutter analyze`：通过，无问题；相关改动git diff --check通过。
- `FLUTTER_BIN=... bash tool/build_ios_device_release.sh`：正常诊断开关关闭的clean Release构建50.6秒，逐嵌套Mach-O平台和签名验证通过，1.4.2(11)。Runner SHA `06c2a36381f8a3c8d5bd32e4da3326f49a16b0566b521ef6f96f43aa19c44f7c`，App.framework SHA `988e6554ec1b514601fc2ec642c11ec376388dc1d779cbcbb80bff2a53f6617b`。归档 `outputs/ios-audio-resume-2026-09-19/fixed-device.Runner.app`，未安装到手机。
- 构建模拟器stdout仍有工具层 `Target native_assets required define SdkRoot` 提示，App已实际运行；通用模拟器构建失败、attach热加载未更新的情况均保留，不把热加载当重建通过。归档模拟器包时一次工作目录错误导致初次ditto失败，随后从已安装模拟器bundle成功归档，未丢失证据。
- 私有URL只曾写入mode0600临时文件，用于同一App连接，已删除这两份临时凭据文件；公开证据不含链接参数/音频源。`evidence-summary.json`对8份采样完成一致性断言，并记录测试、设备包及边界。

本项最短后续真机验收：时间方便时覆盖安装新正常Release，连接音频，锁屏约一分钟后返回，仅确认音乐仍持续；本轮不继续占用用户手机。此前提醒/倒计时通过项不要求全部重做。Pages旧候选仍需随最终共享源码重新选择/验证，未commit、push或发布。
