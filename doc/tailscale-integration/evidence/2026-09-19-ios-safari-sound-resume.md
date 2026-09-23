# 2026-09-19 iPhone Safari 前台返回后提示音失效

## 真实手机观察

- 初次开启声音后，手机 Test sound 与有声 NUDGE 03 均可听；静音 02 只显示不响。
- Safari 返回前台自动恢复游戏且无需登录，但 04 声音未确认，05 明确只显示一次、无声。
- 用户确认声音开关仍开；再次手动点击 Test sound 也无声，状态文字却为 `Test sound played.`。
- 当前代码仅在 AudioContext.state 为 running 且振荡器调度未抛错时报告该文字；这不能证明扬声器真正发声。本轮没有直接采集该手机 AudioContext 对象/底层音频状态。

## 修复范围与依据

原网页始终复用同一个提示音 AudioContext，页面连接和画面恢复时没有相应音频生命周期处理。现在 visibilitychange 隐藏或 pagehide 时释放旧实例，回到可见页面、pageshow/focus 时按用户声音偏好重新初始化；浏览器仍要求交互时，在 pointerup/click/keydown 继续尝试。恢复不会创建振荡器，不补播过去的提醒，也不改变静音偏好。退出或失效实例的异步 resume 不得重新激活旧实例。此改动只影响网页提示音，不涉及原生园区音频或系统通知权限。

WebKit已有相似报告：[running却无声](https://bugs.webkit.org/show_bug.cgi?id=276687)、[后台返回resume未完成](https://bugs.webkit.org/show_bug.cgi?id=281566)。这些只是相关线索，不将旧系统报告当成本机根因的直接证据；当前手机是否修复仍以更新后的同路径听感为准。

## 本轮验证

- `flutter test --platform chrome test/browser/browser_notification_backend_web_test.dart test/browser/browser_reminder_audio_lifecycle_test.dart`：15项通过，其中4项新增生命周期回归覆盖替换仍标为running的旧实例、关闭声音、异步旧resume和页面缓存恢复/销毁监听器。
- 在 Flutter 项目目录执行 `flutter analyze`：No issues found。
- Chromium窄屏加载新Release、真实AudioContext与回放夹具：主动测试音调度成功；合成pagehide/pageshow后旧实例closed、新实例running且不增加声音次数；后续相同NUDGE两份只增加一次声音调用；禁用声音后恢复不重启音频。4项通过，页面错误0。此为真实浏览器音频API+合成生命周期，不是iPhone物理听感，也不声称已捕获Safari底层故障。
- 初版E2E把Flutter语义标签当成普通文本导致断言失败，改用实际aria-label后通过；保留代码逻辑不受定位器修正影响。
- Flutter Web Release、发布树验证、26.2 Gradle build及格式检查通过；66项JUnit全部通过，49个嵌入Web资源逐字节匹配。

## 本地部署与待验

新JAR：a56d2814392ef9d9c3b084e3429cbddc1fc2417bfd57cff0c473a281fe0f3927；main.dart.js：ca4d7352918dc38fcca37d9338314f159d48b758e12f7308a933dfcf59f5a0c1。26.2已正常退出并原子替换，从同一Prism实例重启回原ImagineFun服务器；HTTPS index/main/bootstrap/reminder-sw均与新构建一致。旧包已保留在本机证据目录。手机还需刷新后先确认Test sound，再切换其他App/返回、复测实际有声去重。未commit、push或发布Pages；其他三个Mod和发布候选尚未更新本轮Web改动。

产物/日志/脚本：`outputs/ios-safari-sound-resume-2026-09-19/`（artifact.json、deployment.json、https-assets.json、analyze.log、web-build.log、mod-build.log、audio-recovery-e2e.mjs、e2e-result.json）。

2026-09-20：用户说明没有刷新Safari页面，而是退出连接后重新进入，此时Test sound可以发声。该观察证明本次声音恢复，但不能确认该页面已加载a56d2814 / ca4d7352的新Web构建，也尚未完成修复后“切后台→返回→提醒”复验。不能把重新连接可听直接计为音频生命周期修复通过。当前明确的证据仍是此前开关开启、Test sound played但实际无声，以及源码缺少音频实例的后台/前台生命周期处理；未直接读取失声时iPhone AudioContext或底层输出状态，具体Safari内部原因仍是有依据的假设。下一步先明确刷新获取新代码，再验证同一页面从后台返回后的新提醒。
