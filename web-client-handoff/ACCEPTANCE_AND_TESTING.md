# 验收与测试

## 第一版 MVP 验收

以下项目全部满足时，网页端第一版可以交付。

### 构建

- `flutter analyze` 没有新增错误。
- `flutter test` 没有新增失败。
- `flutter build web` 成功。
- iOS/Android 相关 Dart 代码仍能分析，原生视频实现未被删除。

### 启动与登录

- 桌面 Chrome/Edge 能打开现有 MonkeyCraft 登录页。
- 可以手动输入 host/port/password。
- Web 不显示无法使用的 Android 退出按钮。
- QR 扫描暂不可用时不会导致启动或编译失败。
- 正确密码认证成功，错误密码显示现有错误流程。

### 视频

- 使用现有 Mod，不改协议即可显示第一帧。
- 视频连续播放至少 10 分钟。
- 画面尺寸和方向正确，无明显拉伸。
- 切换现有分辨率预设后能恢复视频。
- hibernation 开始和结束后能恢复视频。
- decoder queue 不持续增长。
- 页面运行期间没有明显 VideoFrame/GPU 内存持续增长。
- decoder error 后可以请求 keyframe 并恢复，或给出明确错误而不是黑屏无反馈。

### 控制

- 现有移动、视角、跳跃、潜行、点击和 hotbar 中的核心操作至少通过鼠标或触控可用。
- HTML canvas 不截获 Flutter 控件的 pointer events。
- 页面失焦、切换路由或断开连接时会释放按下状态，不会让角色持续移动。

### 聊天和状态

- 能进入和退出聊天。
- 能发送和接收聊天消息。
- 玩家数/玩家列表按服务器 capability 正常降级。
- 连接中断后现有重连或返回登录逻辑仍工作。
- hibernation overlay 和 resolution mismatch overlay 仍正常。

### 平台降级

- Web 不调用 Live Activity 或原生通知 MethodChannel。
- 音频暂未实现时不会阻止连接和游戏。
- 不支持 WebCodecs/H.264 时显示明确原因，并允许返回登录或使用聊天。

## 每阶段自动检查

在 `flutter/monkeycraft/` 中运行：

```bash
flutter pub get
flutter analyze
flutter test
flutter build web
```

根据机器环境，再运行原生 smoke check。不要在没有对应 SDK 的情况下把环境缺失误报为代码失败。

## 手工浏览器测试矩阵

第一优先级：

| 环境 | 目的 |
|---|---|
| 最新桌面 Chrome，localhost | 主开发环境和 WebCodecs PoC |
| 最新桌面 Edge，localhost | Chromium 交叉验证 |

第二优先级：

| 环境 | 目的 |
|---|---|
| Safari 16.4+ / 当前 Safari | WebKit H.264 和 platform view |
| Firefox 130+ desktop | Gecko WebCodecs 行为 |
| Chrome Android | 触控与移动 Web |
| Safari iOS | 触控、内存和后台恢复 |

Firefox Android 不作为第一版目标。

## 建议保留的诊断数据

开发期间记录：

- browser user agent
- `VideoDecoder.isConfigSupported()` 返回结果
- codec string
- 首个 SPS/PPS/IDR 的 NAL type 顺序，不记录完整视频 payload
- 首帧耗时
- 当前 FPS 配置
- access unit 接收数量
- decoder 输出帧数量
- queue drop 数量
- decoder error 数量及最近错误
- keyframe request 数量
- 最近一次 resolution header

不要记录用户密码、认证 HMAC、聊天正文或完整视频数据。

## 关键场景

### 首次连接

1. 打开登录页。
2. 连接 Mod。
3. 完成认证。
4. 收到带分辨率 header 的 IDR。
5. configure decoder。
6. 显示首帧。
7. 控制角色并收到后续画面。

### 分辨率切换

1. 修改分辨率设置。
2. 客户端发送新的 `CLIENT_STATUS`。
3. reset 旧 decoder 状态。
4. 等待新分辨率 IDR。
5. 重配 decoder/canvas。
6. mismatch overlay 消失。

### 浏览器落后

1. 人为降低性能或切换后台。
2. 确认 queue 不无限增长。
3. 恢复页面。
4. 丢弃旧 delta 或重置 decoder。
5. 请求并等待 IDR。
6. 回到实时画面，而不是从积压画面慢慢追赶。

### Decoder 不支持

1. 模拟 `isConfigSupported == false`。
2. 页面说明当前浏览器/设备无法解码该配置。
3. 不进入无限重试。
4. 用户可以返回登录或使用仍可工作的聊天功能。

### 断线重连

1. 暂停或关闭 Mod WebSocket。
2. 确认输入全部释放。
3. 恢复服务。
4. 现有重连流程重新认证。
5. 新 decoder 等待 IDR 后恢复画面。

## 回归重点

Web 改造最容易影响原生端的部分：

- 原生 `HardwareH264Decoder` 生命周期
- `Texture` 在 StreamScreen 和 MapScreen 的显示
- iOS/Android 前后台切换
- 原生通知和 Live Activity
- OpenAudioMC/MCParks Headless WebView
- 二维码扫描
- StreamProxy stop/start 与 VideoRelay 清理
- 分辨率切换和 reconnect 后 decoder 重建

平台抽象完成后，应保证这些路径仍由原生实现处理，而不是被 Web no-op 意外替换。

## 第一版交付说明应包含

- 实际支持并测试过的浏览器/版本
- 本地启动命令
- 如何填写 Mod 地址
- 是否要求 `http://localhost`
- 已知不支持功能
- WebCodecs config 和检测结果
- HTTPS/WSS 仍待解决的部署限制
- 与本交接方案不同的关键设计决定及原因
