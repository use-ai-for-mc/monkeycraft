# 给网页端开发 agent 的任务

请在当前 MonkeyCraft 仓库中实现 Flutter Web 第一版。

## 目标

让 `flutter/monkeycraft/` 在保留现有 iOS/Android 客户端的同时，增加浏览器目标平台。第一版应尽快形成以下可运行闭环：

```text
浏览器打开现有登录页
→ 连接现有 Minecraft Mod
→ 完成认证
→ 通过 WebCodecs 显示 H.264 实时画面
→ 使用现有控制发送游戏输入
→ 使用现有聊天页面收发消息
```

## 最重要的约束

- 必须优先复用当前 Flutter 页面、Widget、状态机、协议、WebSocket、认证、设置和输入逻辑。
- 不要建立 React、Vue、原生 JS 或另一套独立网页客户端。
- 不要先重新设计 UI。Web 是现有客户端的第三个平台。
- 不要删除或破坏 iOS/Android 原生能力。
- 第一版可以暂时禁用 QR、原生通知、Live Activity、OpenAudioMC 和 MCParks 音频。
- 第一版先以桌面 Chrome/Edge、`http://localhost` 和现有 Mod 的 `ws://` 为目标。
- 第一版原则上不修改 Minecraft Mod 或 WebSocket 协议。
- 先实现可工作的最小版本，再优化跨浏览器、桌面键盘、移动 Web、PWA、音频和正式部署。

## 方案的约束力

`web-client-handoff/` 中的方案是基于当前代码和规范研究形成的工作建议，不要求严格照抄。WebCodecs、Flutter platform view、renderer、插件和 TLS 可能存在尚未发现的问题。

你可以改变文件结构、接口名称、队列阈值或具体实现，但请遵守核心方向：

- 优先复用现有 Flutter 代码。
- 不平行复制业务页面。
- 不因非核心能力阻塞第一版。
- 用实际实验验证未知问题。
- 偏离方案时记录观察到的问题、采取的替代方案和影响。

## 开工顺序

1. 阅读仓库根目录 `AGENTS.md`。
2. 阅读本目录的 `README.md`、`DESIGN_AND_ARCHITECTURE.md`、`IMPLEMENTATION_PLAN.md`、`H264_WEBCODECS.md` 和 `ACCEPTANCE_AND_TESTING.md`。
3. 检查工作树并保护已有改动。
4. 记录现有 `flutter analyze` 和 `flutter test` 基线。
5. 按 `IMPLEMENTATION_PLAN.md` 小步实现，持续运行 analyze/test/build web。
6. 不要只提交设计或空的 Web scaffolding；持续推进到 MVP 验收闭环，除非出现确实需要用户决策的外部阻塞。

## 技术假设

当前研究表明，Mod 发送的是一条 WebSocket 消息一个 H.264 Annex-B access unit；IDR 中包含 SPS、PPS 和 IDR slice。首选 WebCodecs 配置是 `avc1.420028`，并且不设置 `VideoDecoderConfig.description`。详细依据见 `H264_WEBCODECS.md`。

不要只相信该假设。请在真实浏览器中调用 `VideoDecoder.isConfigSupported()`，连接真实 Mod，并验证首个 access unit。如果失败，先保存有限诊断信息并检查 SPS/PPS/IDR、chunk 边界、timestamp、key/delta 和分辨率，再考虑更改协议或封装格式。

## 交付要求

- 实现代码和必要文档更新。
- `flutter build web` 成功。
- `flutter analyze`、`flutter test` 不新增失败。
- 手工验证登录、认证、视频、核心控制、聊天、重连和平台降级。
- 说明实际测试的浏览器、启动方式、已知限制和未完成的后续项。
- 完成 `ACCEPTANCE_AND_TESTING.md` 的 MVP 项，或清晰列出无法完成的具体阻塞与证据。
