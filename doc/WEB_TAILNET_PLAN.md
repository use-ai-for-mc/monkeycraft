# Web 与 tailnet 产品路径

> 2026-09-19 用户最新决定：浏览器改为 Flutter 与 iOS/Android 共用界面和业务逻辑，仅浏览器适配分层。独立 `web/` 停止继续开发验收及发布，保留为行为参考与测试资产。本文后续有关独立重写、Flutter Web 放弃或冻结的描述属于历史，不再作为当前实施指令。当前执行见 `doc/PRODUCT_ROADMAP_EXECUTION.md`。
更新：2026-09-18。产品决定以 [产品路线](PRODUCT_ROADMAP_2026-09.md) 为准，本轮结果见 [执行记录](PRODUCT_ROADMAP_EXECUTION.md)。

## 正式产品线

Flutter iOS / Android 和 `web/` TypeScript / Preact 浏览器客户端均长期维护。App 保留原生通知、锁屏倒计时、园区音频和游戏控制；浏览器提供页面提醒、用户手势启用的提示音，以及平台允许的系统通知。浏览器关闭、锁屏或后台冻结后的实时提醒不作保证。

LAN、系统 Tailscale 永久保留。PC 与移动 App 的可选内嵌 Tailscale 按路线 P2 实施，用户登录自己的账户；允许系统与内嵌混用。Tailscale 可达性不替代 MonkeyCraft 配对/HMAC，仍只允许一个控制会话。

## 当前浏览器连接

- Mod 的同一端口分流 HTTP 静态资源与 WebSocket。页面产物来自 `web/dist/`，不是 Flutter Web。
- WebCodecs 需要安全上下文。裸 LAN HTTP、`http://100.x` 可访问网页，不代表支持视频；localhost 测试不能替代跨设备 HTTPS。
- 已有系统 Tailscale 的设备可经 tailnet HTTPS / Tailscale Serve 使用同源 WSS。Serve 地址仅限 tailnet，不是公网入口，不自动启用 Funnel。
- 不覆盖已有 Serve 配置；先核对可用地址/端口，再测试资源、登录、视频、控制和恢复。
- 26.2 为先行版本；26.1、1.21.11、1.19 按 P3 分别移植、构建和验收，能力以执行矩阵为准。

## 验收顺序

1. 完成 Web lint、类型、单元和浏览器回放测试，验证资源确实进入 JAR。
2. 在真实 26.2 上完成 HTTPS 持续运行至少 10 分钟、缩放/留黑点击、输入释放、重连、通知声音/静音和倒计时更新/取消/去重。
3. 分别验证 iPhone Safari、Android Chrome；桌面 Chromium/WebKit 不能代替真机。App 同时独立回归。
4. 浏览器稳定后进入 P4 `www.monkeycraft.com`，先审阅已有 `web-tailscale/` 探索。WASM、代理或其它架构需据证据选择；涉及架构选择、服务运营、域名或费用时由用户确认。未经授权不生产部署。

本轮验收记录必须区分代码已实现、自动化通过、真实设备通过和被阻塞，历史记录不视为本轮重测。
