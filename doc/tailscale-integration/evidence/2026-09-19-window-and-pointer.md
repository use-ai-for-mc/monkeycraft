# 2026-09-19 窗口最小化与 PointerLock 证据

## 1.21.11 修复前基线

旧 JAR `500105bac88d5a50d4e2f20a1e73f2281ebe7d859fc113eb2d48eea73bd07dde` 在请求 10 FPS 时通过两个真实浏览器用例。十分钟共解码 5,364 帧，最终无解码错误；四次尺寸切换令配置计数从 1 增至 5，连接始终为 connected。

独立 GLFW 最小化观测显示：原生图标化状态从 0 变为 1，游戏报告的 `isIconified` 从 false 变为 true，帧率限制从 30 降到 10；恢复后回到 30。1.21.11 的本地反编译证实 `FramerateLimitTracker` 对图标化窗口施加 10 FPS 上限，因此 10 FPS 基线不会必然暴露问题，但 20 FPS 请求会受该原版限制约束。

## WindowMixin 修复后的 1.21.11 实测

新 JAR `d42a65b35cade5019f7a9999a79fc948d74493c2e2f894ae5861c757c5a8a9b3` 已部署。它新增 `WindowMixin`：流媒体或自动释放鼠标期间将 `Window.isIconified()` 报告为 false。

真实最小化时原生图标化状态为 1、报告值为 false；初始观测帧率限制为 120，运行中最小化采样为 30，表明其它原版限帧仍会生效，修复只消除了图标化的 10 FPS 限制。窗口恢复经历异步 pending 状态后确认原生图标化为 0。

请求 20 FPS 的两个真实浏览器用例通过，持续 600,031 ms。最终统计为 `dec 6778`、`err 0`、`cfg 6`，四次尺寸切换后仍为 connected。真实最小化的 140,010 ms 区间解码 1,589 帧，平均 11.349 FPS；该值低于请求值，不能写成 20 FPS 实达。测试结束后游戏 PID 84794 正常退出，连接与 Shift 均为 false，原配置 SHA-256 未变化。

## PointerLock、Pages 与构建回归

PointerLock 最小修复后，两个针对性用例通过：Pointer Lock 失败时回退到拖动视角；迟到的 Pointer Lock 完成在屏幕打开或页面卸载时释放。网页单元测试 160 项全部通过。完整浏览器套件为 Chromium 22 项通过、5 项跳过，WebKit 21 项通过、6 项跳过；跳过项不代表通过。

项目路径 Pages 专用 4191 预览已清理。既有 Pages 用例为 4 项通过、1 项跳过，另两个 PointerLock 用例通过。此结果只覆盖本地项目路径预览，并不代表公开 Pages 已部署。

四个 Mod 树按 `spotlessCheck build` 构建：26.2 为 62 项 JUnit，26.1、1.21.11、1.19 各 57 项，均为 0 failures、0 errors、0 skipped。各 JAR 的 11 个网页资源、四平台 helper、manifest sidecar 和许可证均经清单校验。部署清单显示四个 JAR 均已放入对应实例；26.1 只部署新 JAR，未启动，也没有会话控制授权。

## 版本边界与来源

1.19 的 dd3dd0 包已在既有本地世界完成两个真实用例：十分钟 600,030 ms、四次尺寸变化、最终解码 7,971 帧/错误 0；退出后连接/Shift 为 false、原配置不变。此包先于旧式 void 返回接口的后续修复，详见[1.19 证据](2026-09-19-1-19-runtime.md)。历史文档中本地验收世界名称多写为 `MonkeyCraft acceptance 2026-09-19`；实际 LevelName 与目录为 `MonkeyCraft acceptance 2026-09-1`，以后续该实例结果为准。

来源：

- `outputs/roadmap-2026-09-19-version-soak/1.21.11-baseline-result.json`
- `outputs/roadmap-2026-09-19-version-soak/1.21.11-window-before-fix.json`
- `outputs/roadmap-2026-09-19-version-soak/1.21.11-window-fixed-minimized.json`
- `outputs/roadmap-2026-09-19-version-soak/1.21.11-window-fixed-mid-minimized.json`
- `outputs/roadmap-2026-09-19-version-soak/1.21.11-fixed-result.json`
- `outputs/roadmap-2026-09-19-version-soak/1.21.11-cleanup.json`
- `outputs/roadmap-2026-09-19-version-soak/chromium-browser.log`
- `outputs/roadmap-2026-09-19-version-soak/webkit-browser.log`
- `outputs/roadmap-2026-09-19-version-soak/pages-existing.log`
- `outputs/roadmap-2026-09-19-version-soak/pages-pointer.log`
- `doc/tailscale-integration/evidence/2026-09-19-pointer-mod-artifacts.json`
