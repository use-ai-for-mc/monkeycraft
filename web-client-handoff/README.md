# MonkeyCraft Flutter Web 开发交接

这份目录是给负责 MonkeyCraft 网页端开发的 AI agent 使用的。目标不是重新开发一套网页客户端，而是让现有 Flutter 客户端增加 Web 这一目标平台。

## 给开发 agent 的首要指令

请先做出可以运行的第一版，再逐步补齐能力。

- 尽量复用 `flutter/monkeycraft/lib/` 中已有的页面、状态管理、协议、WebSocket、设置和输入逻辑。
- 不要新建 React、Vue、原生 JavaScript 或另一套独立网页前端。
- 不要为了适应桌面浏览器而首先重做 UI。第一版继续使用现有 Flutter 页面和控件。
- 优先增加平台抽象、条件导入和 Web 实现，避免复制业务代码。
- 第一版允许暂时关闭二维码、系统通知、Live Activity、OpenAudioMC 和 MCParks 音频等非核心能力。
- 第一版的核心闭环是：打开网页、输入服务器信息、认证、看到实时画面、发送游戏控制、进入聊天并收发消息。
- 当前方案是基于代码阅读和 WebCodecs 规范形成的建议，不是必须逐字遵循的设计。遇到浏览器、Flutter renderer、JCodec 或网络安全限制时，可以调整实现，但应记录原因，并继续朝可运行的第一版推进。
- 除非实验证明现有协议无法使用，否则第一版不要修改三个 Minecraft Mod 树，也不要引入服务器转码。
- 不要被完整的跨浏览器兼容性阻塞。第一目标环境可以是桌面 Chrome/Edge，通过 `localhost` 提供 Flutter Web，并以 `ws://` 连接局域网内的 Mod。

## 推荐阅读顺序

1. [AGENT_TASK.md](AGENT_TASK.md)
2. [DESIGN_AND_ARCHITECTURE.md](DESIGN_AND_ARCHITECTURE.md)
3. [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
4. [H264_WEBCODECS.md](H264_WEBCODECS.md)
5. [ACCEPTANCE_AND_TESTING.md](ACCEPTANCE_AND_TESTING.md)
6. 仓库现有的 `AGENTS.md`
7. `doc/FLUTTER_CLIENT.md`
8. `doc/JAVA_MOD_ARCHITECTURE.md`

## 代码范围

主要工作目录：

```text
flutter/monkeycraft/
```

第一版预计不需要修改：

```text
mods/26.1/
mods/1.21.11/
mods/1.19/
```

如果最终确实需要扩展协议，必须同时考虑三个 Mod 树，并遵循仓库 `AGENTS.md` 中的 capability gating 规则。

## 第一版的明确非目标

- 重新设计 MonkeyCraft 的品牌或信息架构
- 单独制作桌面控制面板
- 完整 PWA 安装体验
- 后台推送通知
- Live Activity
- 浏览器二维码扫描
- OpenAudioMC 和 MCParks 音频完整兼容
- Firefox Android 支持
- 公网托管、证书签发和反向代理自动部署
- 改用 WebRTC
- 将 H.264 封装成 MP4、HLS 或 MPEG-TS

这些能力可以在视频与控制闭环稳定后再评估。

## 完成定义

当 `ACCEPTANCE_AND_TESTING.md` 中的 MVP 验收项满足，并且 `flutter build web`、`flutter analyze` 和现有测试没有新增失败时，第一版即可视为完成。未实现的移动原生能力应以可理解的降级方式处理，而不是阻止网页端启动。
