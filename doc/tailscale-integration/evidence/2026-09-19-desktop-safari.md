# 2026-09-19 桌面 Safari 验收

环境为实体 Mac 上的 Safari / safaridriver 26.6.2 (21624.5.1.11.3)，不是 Playwright WebKit 或 iPhone。用户手动启用 Remote Automation 后，新会话创建成功；未关闭证书校验、未启用 alwaysAllowAutoplay。

## 首轮结果与中断

- 实际 HTTPS 页面报告安全上下文、WebCodecs VideoDecoder、Notification 和 Service Worker 可用。
- 错误密码被真实26.2拒绝；输入实例配置中的正确密码后，连接状态为connected。密码只在进程内使用，未记录到证据。
- 当时服务器处于 Haunted Mansion 乘坐中的HIBERNATING状态，Safari正确显示暂停、设施进度和倒计时。没有新视频是服务器主动暂停，首轮未将其计作视频验收或解码故障，也未中断用户乘坐。
- WebDriver鼠标点击没有产生DOM点击事件；原生WebDriver Enter可提交表单并操作设置。后续仍需单独验证鼠标路径，不把键盘成功替代鼠标结果。
- 点击Enable reminders后出现真实Safari系统权限面板，后续Notification.permission读回granted，页面显示声音和通知已启用。未得到听觉反馈、未完成系统通知投递或提示音验收。
- 原生面板交互后WebDriver命令不再响应。仅终止自有driver进程；重建会话被Safari以“already paired with another WebDriver session”拒绝，原测试窗口仍保持连接。已请用户只关闭这个测试窗口，以便重新建立独立会话。

Apple说明自动化窗口与普通用户浏览隔离，人工操作自动化窗口可能打断其玻璃罩及会话；这是本轮中断的相关机制，尚不能仅据此断言所有无效鼠标操作的根因。依据：[Safari WebDriver](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari)。

原始环境、首次连接状态、截图和限制记录在`outputs/roadmap-2026-09-19-pages-safari/`。截至本节，视频、背包、持续运行、可听声音与系统通知投递均未算作通过。

## 第二会话恢复后的真实结果

用户关闭首轮 MonkeyCraft 测试窗口后，Safari 允许重新创建自有 WebDriver 会话。以下均来自同一实体 Mac 的 Safari 26.6.2 与真实26.2服务器；不以 Playwright WebKit 或模拟器替代。

- 页面为安全上下文，`VideoDecoder`、`Notification` 与 Service Worker 均可用；`safari-initial.json`记录首次采样为解码21帧、错误0，背包关闭后为解码28帧、错误0。后续实时计数达到解码259帧、错误0。服务器处于普通画面时已有真实解码证据。
- 以 E 打开、Esc 关闭游戏屏幕。视频暂停后的截图没有可靠展示背包，故不把截图作为背包画面验收；Minecraft 原生屏幕检查确认实际为`InventoryScreen`/`InventoryMenu`，因此键盘协议和游戏端状态变更通过。
- `Notification.permission` 为`granted`。设置页“Test sound played.”使页面中受控 Web Audio 振荡器启动计数为1；随后真实 Mod 的静音 NUDGE 显示横幅且计数保持1；有声 NUDGE 显示横幅且计数恰增至2。对应证据为`safari-reminder-permission.json`、`safari-silent-nudge.json`和`safari-audible-nudge-api.json`。
- 此结果证明网页正确区分静音/有声并调用浏览器音频 API，但没有人工确认实际听到声音；没有把它标为可听声音、锁屏/后台系统通知或系统通知投递通过。
- 自动乘坐继续使 Mod 进入 HIBERNATING，视频自然暂停。为避免干预用户园区状态，未强行结束乘坐；因此十分钟连续视频、真实后台标签系统通知、输入释放后的重连均仍待测。

首轮会话中断仍保留为历史：原生权限面板交互后旧 WebDriver 超时，关闭该测试窗口后第二会话已恢复。该历史不再要求用户重复关闭窗口。

## 暂停与清理

用户已确认 Flutter Web 作为 App/Browser 共享 UI/业务代码的正式方向，浏览器只保留薄适配层；旧独立 TypeScript 页面保留参考。因此后续独立页面 Safari 验证与 Pages 发布停止，等待 Flutter Web 实现和验收；这不代表旧实现已删除。自动化已返回登录页，成功删除第二会话并只终止自有driver（PID 99607）。Minecraft 保持运行，复核时`connected=false`、`shift=false`、`hibernating=true`。清理证据为`safari-paused-for-flutter-review.json`。
