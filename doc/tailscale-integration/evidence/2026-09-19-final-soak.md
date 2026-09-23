# 26.2 最终浏览器持续回归

本记录对应 JAR SHA-256 `6fabc18716455b4e5cc7c9fe965d89c2c360995a894dc5a0ad2498c98fa10b09`。环境为 macOS ARM64 上的实际 ImagineFun Add-Ons 实例、既有系统 Tailscale HTTPS/WSS 与 Playwright Chromium。

## 通过的重试

`outputs/roadmap-2026-09-19-final-soak/live-retry.log` 显示两个用例通过：连接并绘制视频用例，以及持续十分钟并进行尺寸切换的用例。总结果为 `2 passed`。

持续用例运行到 600032 ms。期间进行了四次尺寸切换，最后恢复为 1000×700；最终采样为 `dec 4786`、`err 0`、`cfg 5`，链路状态为 connected。采样中配置计数依次从 1 增至 5，解码计数在各尺寸阶段持续增长，没有记录解码错误。

工具确认 MC PID 46058 和 helper PID 46362 均已正常退出。退出前状态为 `connected=false`、`shift=false`，identity 为 `1148163683`。本记录不将该次退出解释为额外的游戏或网络功能验收。

## 保留的首次失败

首次持续尝试在约 3.4 分钟后因浏览器页面、context 或 browser 已关闭而结束；原始日志仍保留在 `outputs/roadmap-2026-09-19-final-soak/live-browser-closed-attempt.log` 与 `live.log`。该尝试不计入通过的持续回归，也没有证据表明它是产品崩溃。

当时可能有并行清理 PID 49448 导致浏览器被停止，但日志无法证明其归属或因果关系。因此该次只记录为未完成的浏览器关闭事件，不能作为产品通过或产品崩溃的结论。

详细的时间点、viewport 和调试计数见 [JSON 证据](2026-09-19-final-soak.json) 与 `outputs/roadmap-2026-09-19-final-soak/result.json`。
