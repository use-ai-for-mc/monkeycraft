# Flutter 浏览器运行证据（2026-09-19）

范围：本文件只记录 Flutter Web 当前实现的浏览器运行验证。测试使用本地 H.264 replay WebSocket，未连接真实 Minecraft；用户正在使用真实游戏，本轮未接管该会话。旧独立 TypeScript 客户端的 Safari、Playwright 和真实 Mod 记录仍是历史参考，不能计入本文件的 Flutter Web 结论。

## 当前自动化环境

- 页面：完整的 49 文件 Flutter Web 发行预览，`http://127.0.0.1:4175/monkeycraft/?debug=1`。
- 服务器：`ws://127.0.0.1:9613` replay fixture（`streaming-360x640`、密码 `test`）。
- 浏览器：Playwright headless Chromium。它可验证页面、WebSocket、WebCodecs、语义树和浏览器 API 接线，不能替代实体 Safari、手机浏览器、真人可听声音或真实 Minecraft。
- 命令：在 `flutter/monkeycraft/` 运行：

  ```sh
  FLUTTER_WEB_URL='http://127.0.0.1:4175/monkeycraft/?debug=1' \
  FLUTTER_REPLAY_URL='ws://127.0.0.1:9613' \
  FLUTTER_WEB_EVIDENCE='outputs/flutter-web-feasibility-2026-09-19/ui-smoke-system-agent-2' \
  node tool/browser_smoke.mjs
  ```

最终 JSON：`flutter/monkeycraft/outputs/flutter-web-feasibility-2026-09-19/ui-smoke-system-agent-2/result.json`。截图包含同目录的 `stream.png`、`silent-reminder-immediate.png` 和 `reminder-settings.png`。

## 通过的 Flutter Web 运行检查

最终 smoke 的 `passed=true`、解码错误为 0，完成下列链路：

1. 错误密码被拒绝；随后以正确密码登录，并解码真实 replay H.264 帧。
2. 四次窗口尺寸变化后，现有 decoder 和 WebSocket 保持，视频继续解码。
3. 浏览器鼠标拖动回退路径发送 `LOOK_DELTA`；按住 `W` 后触发窗口 blur，按键释放消息实际送达。
4. replay 发出 `SCREEN_STATE=true` 后，`Escape` 发送 `SCREEN_KEY` 的按下与释放。
5. 设置页启用提醒并测试页面音；静音 NUDGE 不增音调计数，有声 NUDGE 恰增加一次，重复有声 NUDGE 被去重，网页横幅通过语义节点确认。
6. 真实 `SERVER_STATUS` 消息创建计时提醒、更新同一提醒、到点只触发一次；取消后无提醒；过期状态重放两次也无提醒。
7. replay 以合法 WebSocket close code `4000` 关闭连接后，客户端自动重连并恢复新视频帧。
8. 页面刷新后保存的同目标身份可直接重新连接；改为另一个目标后连接会要求重新输入密码，未复用原目标密码。

计时、提醒、重连和身份均通过页面实际 WebSocket 消息触发，而不是仅调用 Dart unit fake。

## Pointer Lock 与通知的环境边界

Pointer Lock 请求在 headless Playwright macOS 环境得到 `WrongDocumentError: The root document of this element is not valid for pointer lock.`。该环境下回退拖动可用，不能把 Pointer Lock 写作通过。原生 Chrome 辅助尝试也只确认了实际视频累计解码 2,039 帧、错误 0；`pointerLockElement` 仍为 null，无法证明得到真实 OS 前台焦点，因此同样不能当作 Pointer Lock 通过。该测试标签已关闭。仍需用户在真实前台 Chrome 中实际点击游戏区域后确认锁定及自由鼠标移动。

`127.0.0.1` 页面实际返回 `isSecureContext=true`，`navigator.serviceWorker` 可用；此前把本地 HTTP 预览写成非安全上下文是错误的。当前 Playwright headless Chromium 的通知权限仍为 `denied`：新上下文权限、`context.grantPermissions` 和 CDP `Browser.grantPermissions` 均未取得 `granted`。因此 smoke JSON 将系统通知部分准确标为跳过：安全上下文可用、headless 权限模拟未授予。若实际前台浏览器取得通知权限，脚本会继续执行隐藏页面、真实 service worker 注册、`getNotifications()`，并检查通知的 title、tag 与 `silent` 字段。

这不等于浏览器系统通知、后台投递、锁屏提醒或真实可听声音已通过。它们仍需获授权的实体桌面 / 手机浏览器验收。

## Safari 边界

本轮已在真实 macOS Safari 26.6.2 运行 Flutter Web 的 localhost replay：`http://127.0.0.1:4175/monkeycraft/?debug=1` 连接 `ws://127.0.0.1:9612`，密码 `test` 接受。Safari 环境为安全上下文，`VideoDecoder`、`Notification` 和 service worker API 均可见，通知权限仍是 `default`。页面诊断记录解码 93、错误 0、接收 109，视频画布为 360×640；replay 服务端记录发送 203 帧、丢失 0，并收到 ACK。证据：`outputs/roadmap-2026-09-19-pages-safari/flutter-safari-replay-acceptance.json`、`flutter-safari-auth-video.png`、`flutter-safari-auth-video-dom.json`。

这只覆盖真实 Safari 与本地 replay 的认证和视频链路，不建立外部 HTTPS、真实 Minecraft、通知投递、提示音、后台或手机浏览器验收。此前独立网页的 Safari 键盘与 NUDGE 记录仍不能转移为 Flutter Web 结果。

另一次隔离的 Safari WebDriver 诊断使用完整 Flutter 发行预览 `http://127.0.0.1:4176/monkeycraft/?debug=1` 和本地 replay `ws://127.0.0.1:9615`。连接成功后原生点击游戏区域，`activeElement` 为 `FLUTTER-VIEW` 且 `document.hasFocus()` 为 `true`。随后 W3C Actions 的 `W` 按下/释放实际产生 `INPUT W=true`、`INPUT W=false`；对 `flutter-view` 的 WebDriver `sendKeys('w')` 也产生第二组相同消息。因此，先前未可靠建立焦点时的 Safari 键盘空记录不能视为产品故障；本轮实际覆盖了 Flutter Web 的 Safari `W` 映射及 keyup，且两条 WebDriver 输入路径都到达协议层。证据为 `outputs/roadmap-2026-09-19-pages-safari/flutter-safari-keyboard-focus-diagnostic.json`。

该诊断同时发现 Safari WebDriver 在文本字段 `sendKeys` 时会给出异常的 DOM `code`（例如 `key=w`、`keyCode=87` 却为 `code=KeyA`；数字也出现 `keyCode=65`）。文档捕获器能记录这些受信任事件；游戏阶段的两条动作没有再进入该 document 捕获器，但协议消息按动作时序到达。因此不能用捕获器的游戏阶段空白来否定已观察到的协议结果，也不能将此结果扩大为 Q/E/F、方向键、Shift、Escape、浏览器失焦或 Pointer Lock 全部通过。Safari 的提醒权限/声音、后台、重连、其他按键与 iOS Safari 仍待单独验收。该诊断的 Safari driver、replay 9615 与 4176 本地预览均已清理。
