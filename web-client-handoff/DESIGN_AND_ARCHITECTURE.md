# 设计思路与目标架构

## 产品判断

- 页面类型：产品应用，不是营销页面。
- 实际用户：已经运行 MonkeyCraft Fabric Mod，希望通过浏览器远程查看和控制 Minecraft 的玩家。
- 主要任务：连接 Minecraft，持续查看低延迟视频并发送操作。
- 次要任务：聊天、切换服务器、地图、设置画质、执行命令。
- 内容密度：游戏画面为主，控件按需覆盖，设置和聊天保持现有密度。
- 视觉特征：继续使用现有 MonkeyCraft Flutter UI；游戏画面始终是主视觉。
- 第一版拒绝的模式：重新设计全部页面、添加网页仪表盘、添加与功能无关的卡片或状态指标。

## 总体原则

把 Web 视为现有 Flutter App 的第三个平台：

```text
                 现有 Flutter 页面、状态和协议
                              │
                  ┌───────────┴───────────┐
                  │                       │
          iOS / Android 平台层        Web 平台层
          原生 H.264 Texture          WebCodecs + Canvas
          原生通知 / WebView          no-op 或浏览器实现
          本机 TCP video relay        不需要
```

共享层继续负责：

- 登录和页面导航
- `StreamProxy` WebSocket 协议
- HMAC-SHA256 认证
- `SessionController` 状态机和重连
- `GameInputController`
- `StreamSettings`
- 聊天、地图、服务器选择、命令和 hotbar
- 分辨率协商、休眠和 capability gating

平台层只负责：

- H.264 解码和显示
- 平台检测
- 系统通知与 Live Activity
- 二维码扫描
- 内嵌音频网页
- 屏幕方向、系统 UI 和应用退出
- 本机 TCP video relay

## 目标数据流

```text
Minecraft H264Streamer
    │  每帧一条 WebSocket binary message
    │  IDR 首包可带 6 字节 MC + width + height
    ▼
StreamProxy._handleBinaryMessage
    ├── 去掉 6 字节 MonkeyCraft 头
    ├── 发布 serverResolutionEvents
    ├── 发布 accessUnits
    └── 发送 ACK
             │
             ▼
WebH264DecoderController
    ├── 检测 SPS/PPS/IDR
    ├── 建立 EncodedVideoChunk
    ├── 控制 decodeQueueSize
    └── VideoDecoder.decode
             │
             ▼
VideoFrame → HTMLCanvasElement → Flutter HtmlElementView
```

`StreamProxy` 现有的 `accessUnits` 广播已经是合适的 Web 解码入口，不要重新建立第二条 WebSocket 连接。

## 建议的平台抽象

具体命名可以调整，但应尽量把条件代码收敛到少量文件，而不是在所有页面散布 `kIsWeb`。

### 1. 平台能力

建议增加一个小型平台能力对象，例如：

```text
lib/platform/platform_capabilities.dart
lib/platform/platform_capabilities_io.dart
lib/platform/platform_capabilities_web.dart
```

至少提供：

- `isWeb`
- `isIOS`
- `isAndroid`
- `supportsNativeNotifications`
- `supportsLiveActivity`
- `supportsQrScanner`
- `supportsEmbeddedAudioWebView`
- `supportsVideoDecoder`
- `supportsTouchControls`

不要让共享文件直接导入 `dart:io`。使用 `dart.library.io` 和 `dart.library.js_interop` 条件导入。

### 2. 视频解码控制器

建议从当前 `HardwareH264Decoder` 提炼一个共享接口，保留现有原生实现：

```text
lib/stream/video/monkeycraft_video_decoder.dart
lib/stream/video/native_h264_decoder.dart
lib/stream/video/web_h264_decoder.dart
```

接口所需能力大致为：

- 初始化
- 接收 `Uint8List` access unit
- reset
- dispose
- ready 状态
- dropped/decoded 等诊断数据

是否让控制器直接生成 Widget，可以由实现者决定。更容易复用的方式通常是让控制器只管理解码，再由一个共享 `VideoSurface` Widget 根据平台显示原生 `Texture` 或 Web `HtmlElementView`。

### 3. 视频显示组件

建议增加一个所有页面共用的视频组件：

```text
lib/stream/widgets/video_surface.dart
lib/stream/widgets/video_surface_native.dart
lib/stream/widgets/video_surface_web.dart
```

原生版本继续使用 `Texture(textureId: ...)`。Web 版本显示注册过的 `HTMLCanvasElement`。

然后让以下页面使用 `VideoSurface`，不再直接理解 `textureId`：

- `stream/screens/stream_screen.dart`
- `map/map_screen.dart`

这一步是为了消除 UI 对原生 Texture 的绑定，不是为了重写 UI。

### 4. VideoRelay

当前 `StreamProxy.start()` 总会创建 `VideoRelay`，而浏览器不能创建 `ServerSocket`。最小改法是对 `VideoRelay` 使用条件导出：

```text
video_relay_io.dart    保留当前实现
video_relay_web.dart   相同 API 的 no-op 实现
video_relay.dart       条件导出
```

Web no-op 版本可以让 `start`、`stop`、`reset` 和 `onVideoFrame` 安全返回。这样第一版不必大改 `StreamProxy`。

如果实现过程中发现 no-op 让依赖关系不清晰，也可以把 relay 抽象成可注入对象，但不要同时重构协议和 UI。

## Web 视频渲染选择

第一选择：`WebCodecs VideoDecoder` 解码后直接画入 HTML canvas。

原因：

- 现有协议已经传输 H.264 access unit。
- 不需要容器封装和 demux。
- 解码接口允许主动控制队列，适合低延迟画面。
- `package:web` 已经提供 Dart 绑定。
- canvas 可以作为 Flutter Web platform view 嵌入现有 Stack。

不建议第一版使用：

- `video_player`：现有数据不是媒体 URL 或 MP4 文件。
- Media Source Extensions：需要先封装 fragmented MP4，并管理 SourceBuffer。
- MPEG-TS 播放：浏览器原生 `<video>` 通常不能直接消费当前 TCP/MPEG-TS 链路。
- WebRTC：需要显著修改服务器协议和信令。
- WASM H.264 解码器：包体积、CPU 和功耗都不如浏览器原生解码。
- 把每帧复制成 Flutter `ui.Image`：可作为兼容性实验，但不应是第一选择，复制成本较高。

## UI 复用策略

第一版不创建网页专属页面。

- 登录继续用 `LoginScreen`。
- 服务器选择继续用 `ServerPickerScreen`。
- 主游戏继续用 `StreamScreen`。
- 聊天继续用 `ChatScreen`。
- 地图继续用 `MapScreen`。
- 设置继续用 `StreamSettingsScreen`。
- 游戏画面位置和控件层级保持现状。

现有触控控件通常也能接收鼠标 pointer 事件，因此可以先保留。物理键盘支持是很有价值的后续增强，但不应阻塞首帧视频。加入键盘时应复用 `GameInputController` 和现有命令发送器，并在窗口失焦、路由切换和页面隐藏时调用 `releaseAll()`。

## 非核心平台能力的第一版处理

| 能力 | 第一版建议 |
|---|---|
| QR 扫描 | 隐藏入口或显示不支持说明，保留手动输入 |
| Live Activity | Web no-op |
| 原生通知 | Web no-op，已有页面内状态继续显示 |
| Timed notifications | 保留状态逻辑，不调系统通知 |
| OpenAudioMC | 暂时禁用并防止导入原生 WebView 实现 |
| MCParks v1 | 暂时禁用并防止导入原生 WebView 实现 |
| Secure storage | 先评估插件 Web 支持；不能安全实现时不持久化密码 |
| App exit | Web 中隐藏 Android 退出按钮 |
| Orientation | Web no-op；后续可加 Fullscreen API |
| Wake lock | 第一版不要求；后续使用 Screen Wake Lock API |

降级必须保持应用可编译和可使用。不要为了让一个非核心插件支持 Web 而重写核心连接流程。

## 网络与部署边界

本地 PoC 推荐：

```text
Flutter Web 页面：http://localhost:<port>
Minecraft Mod：ws://<LAN-IP>:<port>
浏览器：桌面 Chrome/Edge
```

`localhost` 通常可作为 secure context 使用 WebCodecs。正式 HTTPS 页面不能连接 `ws://`，因为会被 mixed-content 策略拦截，届时需要：

- 为 WebSocket 提供 `wss://`；或
- 使用同源反向代理转发到 Mod；或
- 使用可信隧道/网关统一终止 TLS。

公网部署和 TLS 不属于第一版，但代码应保留现有 `ws://`/`wss://` URL 解析，不要写死 localhost。
