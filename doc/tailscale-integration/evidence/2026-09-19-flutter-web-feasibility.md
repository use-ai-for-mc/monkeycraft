# Flutter Web 实施与可行性证据（2026-09-19）

范围：Flutter Web 作为正式浏览器客户端的本轮实现与自动化核对。浏览器与 iOS / Android 共用 Flutter UI、协议、认证、会话、输入控制器和通知协调器；浏览器差异以条件导入的薄适配层实现。独立 TypeScript / Preact `web/` 只保留为行为和测试参考，过去的 Pages、Safari、Playwright 结果不是本节 Flutter Web 的验收结果。

## 当前结论

Flutter Web 已从“仅编译可行”进入实施和定向自动化阶段。共享层继续使用 App 的登录、凭证、会话、H.264 解码、游戏界面、输入状态机及倒计时协调语义；浏览器层新增通知/声音、页面可见性、键盘与 Pointer Lock / 全屏等适配。没有删除独立实现，也没有触发 Pages 部署。

生产 Flutter UI smoke 已通过，桌面 Safari 已用 Flutter 页面连接录制视频回放；详见 [运行证据](2026-09-19-flutter-browser-runtime.md)。用户仍在玩真实 Minecraft，本阶段未接管角色或重启游戏。这些结果不推断真实 Minecraft、手机浏览器、实体手机声音、锁屏或后台系统通知已经通过。

## 本轮自动化与构建证据

所有 Flutter 命令在 `flutter/monkeycraft/` 运行，原始日志及 release 产物位于 `outputs/flutter-web-feasibility-2026-09-19/`。

| 检查 | 结果 | 证据边界 |
|---|---|---|
| `flutter analyze` | 无问题 | `flutter-analyze-release.log`；静态检查不等于浏览器行为通过。 |
| `flutter test` | 215 项通过 | `flutter-tests-final.log`；完整 Dart / widget 回归，不把它换算为设备或浏览器 E2E。 |
| `flutter build web --release --base-href /monkeycraft/` | 最终完整 Pages 产物成功，25.3 秒；Mod 根路径产物成功，25.4 秒 | `flutter-pages-verified-final.log`、`flutter-mod-verified-final.log` 与 `current-build/`；是 release 编译证据，未构建或验收生产 Wasm。 |
| Chrome 视频定向测试 | 2 项通过 | 实际解码仓库录制的 H.264 access units，覆盖重置及异步释放；不含本轮实时 Mod 视频。 |
| 浏览器通知定向测试 | 11 项通过 | 覆盖浏览器通知/声音适配与协调语义；无浏览器权限、人工听感、后台系统投递结论。 |
| 浏览器输入定向测试 | Chrome 5 项通过；VM 20 项通过 | Chrome 覆盖 Pointer Lock 异步拒绝、成功后到达的 DOM 锁定事件、晚到锁定释放及自由鼠标增量；VM 覆盖键盘、触控控件与输入状态机。不是生产 UI 或真实 Minecraft 输入验收。 |
| 托管目标与认证定向测试 | 25 项通过 | 覆盖浏览器目标/凭证相关逻辑；不代表 GitHub Pages 上实际登录、跨域或持久化已验证。 |
| 浏览器完整定向套件 | 23 项通过 | `browser-suite-23.log`；包括音频 5、通知 11、输入 5、视频 2；复用下列定向测试，不重复累计。 |
| Node 来源核对 | 6 项通过 | 用于发布来源/产物辅助核对，不能作为 Flutter 产品功能测试累计。 |

表内定向套件与完整 215 项可能重叠，故不相加为新的总数。

## 共享层与薄适配层

| 范围 | 当前实现方向 | 验收状态 |
|---|---|---|
| 共享 Flutter 层 | App 与浏览器共用认证、会话、WebSocket 协议、视频 UI / 解码选择、`GameInputController`、触控控件和倒计时协调。 | 已进入上述静态、单元与 widget 回归；生产 UI 与 Safari 回放通过，真实游戏仍待测。 |
| 浏览器通知 | 条件导入浏览器 notification backend，保留 App 的通知去重、更新、取消语义，并为网页提示音提供浏览器实现。 | 11 项定向测试及生产 UI 的静音/有声计数、横幅去重、倒计时更新/取消/过期通过；人工听感与后台系统投递仍待测。 |
| 浏览器输入 | 浏览器键盘映射、页面失焦/隐藏释放、Pointer Lock 与全屏能力由 browser input 适配器提供；触控拖动仍复用 `LookPad`。 | Chrome / VM 定向测试通过；生产 UI 拖动回退、失焦释放和 ESC 通过，Pointer Lock 实际捕获仍待人工验收。 |
| 托管与身份 | 浏览器目标、凭证和 Pages 子路径行为由 Flutter 实现，避免把页面自身 origin 当作唯一游戏服务器。 | 25 项定向测试通过；本地生产 UI 刷新身份恢复、切换目标清除自动填充通过；公开 Pages、跨域 WSS 仍待 E2E。 |
| App 专属能力 | iOS / Android 原生通知、锁屏倒计时和园区音频继续保留。 | 浏览器不以删除或降级原生能力换取统一 UI。 |

浏览器当前正式网络边界仍是 LAN / 系统 Tailscale。内嵌 Web Tailscale / WASM 仅为探索资产，不作为 Flutter Web 上线依赖或正式支持结论。

## 仍需完成的验证

1. 继续真实浏览器 Pointer Lock、系统通知投递及配对验收；已有本地生产 UI 通过项见运行证据，不重复记为待测。
2. 在真实 Minecraft 上分别验证 Chrome、桌面 Safari、iOS Safari 与 Android Chrome：错误登录、视频连续性、重连、尺寸变化、输入释放和凭证持久化。
3. 在授权后的真实浏览器验证通知权限、`sound=false`、用户可听声音、倒计时更新/取消/去重，以及浏览器允许范围内的后台系统通知；页面关闭和手机锁屏后的可靠实时提醒不作承诺。
4. 将 Flutter release 产物接入 Pages 工作流后，才运行项目路径、HTTPS / WSS、公开入口和回滚路径验收。`ace51c9` 的独立网页发布准备及其历史 Safari 结果不替代这些步骤。

## 历史独立实现的边界

独立 `web/` 曾有 TypeScript、Biome、Pages、Playwright、真实 Safari 与真实 Mod 的记录。它们可帮助选择迁移行为或 fixture，但自用户确认 Flutter Web 后不再继续作为待发布客户端验收，也不得标为本轮 Flutter Web 的通过证据。Pages 当前公开地址仍是旧 Flutter 网页，尚未发布本轮 Flutter Web 产物。

## 构建完整性修复与证据边界

- 发现同一 SDK 在不同 `--output` 目录间切换后出现返回成功但仅 21 文件的产物，缺失 assets、字体、vendor 和 reminder service worker。该不完整包未部署。旧预览目录合并复制会掩盖缺失，故改成只用 Flutter 默认 `build/web`，从全新完整目录创建发布包。
- 发布工具验证所有必需资源非空、准确 base href、本地 jsQR 及许可证、JSON，拒绝符号链接与内嵌 Tailscale 实验目录。复制到同父临时目录并验证后替换目标；失败恢复旧发行目录。完整 Pages 为 49 个被追踪资源，另加 provenance manifest；已逐项复算 hash。
- 加入项目 bootstrap，避免默认 Flutter loader 再注册旧 Flutter service worker，与浏览器提醒 service worker 争用同一 scope。新完整预览执行了刷新身份与重连 smoke。
- 本地 dirty 构建 manifest 明确为 `dirty=true, commit=null`，不冒充已提交源代码；没有公开 Pages 发布。
- Mod 的慢 HTTP 下载原先会阻塞 WebSocket selector 并可能提前截断大型 CanvasKit。26.2 首轮隔离下载线程测试解决阻塞后，独立审核补齐有界执行、60秒截止、服务停止清理及关闭竞态；移植使用 Java17 兼容实现。四版本最终构建与测试均通过，尚未部署。详见 [Mod 打包证据](2026-09-19-flutter-mod-packaging.md)。

最终构建重跑后，`outputs/flutter-web-feasibility-2026-09-19/ui-smoke-release/result.json` 再次 `passed=true`、`errors=[]`；前述10条生产 UI 检查均完成。系统通知分支保留 `secure=true`、`permission=denied` 的跳过原因；不将总 smoke 通过解释为该分支通过。`final-flutter-artifacts.json` 记录 Pages manifest/main 的 SHA 与全部49资源逐项比对结果。

Safari 补测追加：三次窗口 resize 后画面和连接持续；明确建立 Flutter 视图焦点后，两种原生 WebDriver 键盘路径均向回放发送 W 按下/释放。首轮脚本无输入消息的记录保留，不能算产品失败或凭空归为驱动限制。Esc、通知和后台仍待验。细节见浏览器运行证据。
