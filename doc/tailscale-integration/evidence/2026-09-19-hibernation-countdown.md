# 2026-09-19 浏览器休眠倒计时重复修复

用户在实体 iPhone Safari 中成功配对，看到休眠界面与两份同一项目倒计时。26.2 现场读回休眠消息为 `Riding Walt Disney’s Enchanted Tiki Room (96%) / 28s left`，timedCountDownText 同为该项目。另一次到点听到声音，但用户无法判断来自手机还是电脑，故不计 iPhone Safari 听感通过。

## 改动

`stream_screen.dart` 中浏览器附加 TimedReminderCountdown 仅在休眠覆盖层未显示时渲染；保留原有休眠文字。通知调度未改变，离开休眠会继续显示仍有效的附加倒计时。原生 App 本就没有该浏览器附加倒计时。

## 本轮检查

- `flutter test test/timed_reminder_countdown_test.dart test/stream/session_controller_test.dart test/browser_reminder_overlay_test.dart`：13 项通过。
- `flutter analyze`：No issues found。
- `FLUTTER_BIN=/Users/cusgadmin/if-local/flutter/bin/flutter MONKEYCRAFT_PAGES_PROVENANCE=0 bash flutter/monkeycraft/tool/build_web_release.sh / build/web`：Release 构建与发布树核验通过。
- 26.2 `JAVA_HOME=$(/usr/libexec/java_home -v 25) ./gradlew --no-daemon build`：通过，66 项 JUnit，0 failures/errors/skipped，格式检查通过；未改 Java。
- Chromium 430×900 回放夹具：同一脚本针对运行中旧 JAR 的 Web 资源断言失败，休眠时附加倒计时数量为 1；新 Release 数量为 0。修复后正常画面倒计时、休眠去重、退出休眠恢复、取消四项检查通过，浏览器错误 0。已逐张查看前后截图，中央休眠倒计时保留、底部重复项消失。此为桌面 Chromium 的窄屏夹具，不是实际 iPhone。
- 初版自动化定位器错误地假定 Flutter 倒计时使用 aria-label 属性、休眠正文暴露为独立语义节点，出现定位超时；改为实际语义文本并截图核对后，上述同脚本前后对照成立。这些超时不归为产品失败或通过。

## 部署与证据

26.2 已正常退出，保留旧 JAR 后原子替换并从原 Prism 实例重启，重新加入原 `mp.imaginefun.net`。新 JAR SHA-256：bc6f919f02384c028f70c3ca0301bcef85328080e6ade3ca2747ad10136a478e；main.dart.js：60cbdf2044caa3a8e2d99d6761ae85f594e7874df78fd4784c0e6c1e0a03c145。49 个嵌入 Web 文件逐字节匹配；从既有 HTTPS 入口取得 index/main/bootstrap/reminder-sw 均与构建一致。

证据目录：`outputs/hibernation-countdown-2026-09-19/`，包含构建日志、artifact.json、deployment.json、https-assets.json、countdown-regression.mjs、before/after-result.json 和前后截图。相关产物已经本地更新，手机尚待刷新后确认；其他三个 Mod 的嵌入 Web 包仍为先前版本，未把旧版/旧包验收自动迁移到当前包。未 commit、push 或部署 Pages。

用户在已刷新的真实iPhone Safari确认测试休眠页面无重复倒计时。随后按测试专用文字匹配取消计时并结束休眠，MCP读回timerCleared=true、hibernationEnded=true、connected=true、hibernating=false；未清除其他真实提醒。此项新包真机显示验收通过，下一步手机网页自身的Test sound，之前来源不明的声音仍不计通过。
