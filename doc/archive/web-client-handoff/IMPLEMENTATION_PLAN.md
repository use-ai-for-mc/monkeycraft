# 分阶段实现方案

以下顺序用于降低一次性改动风险。每个阶段结束时都应保持工程可分析、可测试，并尽可能可运行。

## 阶段 0：建立基线

1. 阅读仓库根目录 `AGENTS.md`、`doc/FLUTTER_CLIENT.md` 和关键文件。
2. 运行并记录当前结果：

   ```bash
   cd flutter/monkeycraft
   flutter analyze
   flutter test
   ```

3. 记录当前 Git 状态，不覆盖用户已有改动。
4. 确认所用 Flutter SDK 支持 `pubspec.yaml` 中的 Dart SDK 版本。

不要把基线已有警告误当成 Web 改造引入的问题。

## 阶段 1：生成 Web 平台并让登录页编译

目标：`flutter build web` 成功，网页能显示现有登录页。

建议操作：

1. 在 `flutter/monkeycraft/` 中补充 Flutter Web scaffolding。通常可以使用：

   ```bash
   flutter create --platforms=web .
   ```

   执行前后检查 diff，避免工具覆写已有 Android/iOS 或 Dart 文件。

2. 增加 `web` 包，用于浏览器 API 和后续 WebCodecs：

   ```yaml
   dependencies:
     web: ^1.1.1
   ```

   版本应以当前 Flutter/Dart 解析结果为准，不要为了照抄版本破坏依赖解析。

3. 清除 Web 编译路径上的直接 `dart:io` 引用。优先使用条件导入和平台能力对象。
4. 为以下能力提供 Web no-op 或隐藏入口：

   - `TimedNotificationService`
   - `IosTimedNotificationScheduler`
   - `LiveActivityService`
   - `KeyboardPrewarmer`
   - Android 退出按钮
   - 平台专用字体或设置逻辑

5. 阻止 Web 编译路径直接引用不兼容的 Headless WebView 服务。可以先提供同 API 的 Web no-op 服务。
6. 二维码入口可以隐藏；不要删除 `QrScanScreen` 的原生功能。

验收：

```bash
flutter analyze
flutter test
flutter build web
flutter run -d chrome
```

浏览器中应显示现有 `LoginScreen`，设置能加载，控制台没有启动即崩溃。

## 阶段 2：打通 WebSocket、认证和聊天

目标：不显示视频也能连接现有 Mod、完成认证并收发聊天。

1. 为 `VideoRelay` 增加 Web no-op 实现，确保 `StreamProxy.start()` 不尝试创建 `ServerSocket`。
2. 保留当前 `web_socket_channel`、HMAC、HELLO/AUTH/AUTH_OK 和 capability 逻辑。
3. 确认浏览器接收到的 WebSocket binary message 最终进入 `_handleBinaryMessage`。`Uint8List` 应能通过当前 `List<int>` 判断；如果实际 adapter 返回其他类型，仅在代理边界规范化，不复制协议处理。
4. 在视频解码器尚未 ready 时仍发送必要的 ACK，避免 Mod backpressure 停流。
5. 暂时允许 StreamScreen 使用明确的“正在准备 Web 视频”占位，不要让 unsupported-platform 页面阻止导航和聊天。
6. 测试连接断开、认证失败和返回登录页。

建议先使用：

```text
http://localhost:<flutter-port>
ws://<minecraft-lan-ip>:<monkeycraft-port>
```

验收：

- 认证成功。
- `AUTH_OK` capability 正常保存。
- 玩家数、服务器选择或聊天至少有一条非视频协议完成往返。
- 进入和退出聊天不会崩溃。
- 断开后现有重试和返回登录逻辑仍有效。

## 阶段 3：最小 WebCodecs PoC

目标：先在独立的 Web 视频控制器中看到首帧，不急于完善全部状态。

1. 使用 `package:web` 创建：

   - `HTMLCanvasElement`
   - `VideoDecoder`
   - `VideoDecoderConfig`
   - `EncodedVideoChunk`

2. 将 canvas 注册为 Flutter Web platform view。
3. 配置首选 codec：`avc1.420028`。
4. 不传 `VideoDecoderConfig.description`，让输入按 Annex-B 处理。
5. 启动前调用 `VideoDecoder.isConfigSupported()`；失败时把 codec/config/error 清楚显示在诊断信息中。
6. 每条 WebSocket 视频消息已经是一帧 access unit。为每个 access unit 构造一个 chunk：

   - `type`：包含 NAL type 5 时为 `key`，否则为 `delta`。
   - `timestamp`：使用单调递增微秒时间，例如 `frameIndex * 1000000 / fps`。
   - `duration`：可使用 `1000000 / fps`，也可在验证后省略。
   - `data`：`StreamProxy` 去掉 6 字节头后的原始 `Uint8List`。

7. decoder output 回调收到 `VideoFrame` 后：

   - 将 canvas backing size 更新为 frame 的显示尺寸。
   - 将 frame 绘制到 2D canvas。
   - 立即 `frame.close()`。
   - 通知 SessionController 已收到可显示帧。

8. 不要每帧调用 `flush()`。实时流应持续入队并依赖 output 回调。
9. 错误后创建新的 decoder，并忽略 delta，直到收到下一个 IDR。必要时调用现有 `REQUEST_KEYFRAME`。

PoC 成功标准：连续显示至少一分钟画面，没有 decoder closed、内存持续上涨或延迟不断累积。

## 阶段 4：接入现有 StreamScreen 和 MapScreen

目标：用共享 `VideoSurface` 替换页面对原生 Texture 的直接依赖。

1. 提炼原生和 Web 共用的视频控制接口。
2. 保留现有 `HardwareH264Decoder` 的 MethodChannel 和 native texture 行为，不重写 iOS/Android 解码器。
3. 将 `SessionController.decoder` 改为共享接口，或增加一个足够小的适配层。
4. 用 `VideoSurface` 替换：

   - `StreamScreen` 中的两个 `Texture(...)` 使用点。
   - `MapScreen` 中的 `Texture(...)` 使用点。

5. Web canvas 应设置 `pointer-events: none`，让 Flutter 的手势层继续接收输入。
6. 保留现有画面缩放、方向、分辨率 mismatch 和 hibernation overlay。
7. 分辨率改变时等待带 `MC` 头的新 IDR，reset/reconfigure decoder，避免把新序列喂给旧 decoder。

不要为 Web 创建第二个 StreamScreen。

## 阶段 5：低延迟和背压

目标：浏览器短暂卡顿后能恢复到实时画面，而不是越来越延迟。

1. 监控 `VideoDecoder.decodeQueueSize`。
2. 设定很小的队列上限。具体阈值需要实测，可先从 2 到 4 帧开始。
3. 队列过长时优先保实时性：

   - 丢弃新的 delta，直到队列下降；或
   - reset decoder、请求 IDR，并等待 key chunk。

4. 不要任意丢弃关键帧。
5. 每次 decoder error、reset、分辨率改变、浏览器从后台恢复，都应重新等待 key chunk。
6. 页面隐藏时释放输入；是否暂停视频由现有 client status 和浏览器行为共同决定。
7. 记录但不要默认展示诊断数据：

   - received access units
   - decoded frames
   - dropped due to queue
   - decoder errors
   - current decode queue size
   - last frame time

诊断可以通过 debug log 或开发模式入口提供，不要把主游戏页变成监控面板。

## 阶段 6：输入和桌面可用性

目标：第一版在桌面浏览器中可以实际操作。

最低要求：

- 现有 joystick/look pad/button 能通过鼠标或触控工作。
- 控件不会被 HTML canvas 抢走 pointer events。
- 窗口失焦和页面隐藏时释放所有按键。

推荐增强：

- `W/A/S/D` → 现有 INPUT 状态机
- Space → jump
- Shift → sneak
- 数字键 1–9 → hotbar
- 鼠标移动或 drag → 复用 LOOK_DELTA coalescer
- 左/右键 → 现有 CLICK 命令

不要在输入框获得焦点时截获游戏键盘事件。浏览器右键菜单和 pointer lock 可以后续处理；首版可使用 drag look。

## 阶段 7：平台降级和清理

1. 为不支持 WebCodecs/H.264 的浏览器显示可操作的错误：

   - 当前 browser 不支持配置
   - 建议使用受支持的桌面浏览器
   - 保留返回登录和聊天入口

2. 隐藏 Web 不可用的设置项，不显示永远失败的按钮。
3. 保证原生 iOS/Android 行为不回退。
4. 更新 `doc/FLUTTER_CLIENT.md`：

   - Flutter Web 平台
   - WebCodecs 视频路径
   - Web 端暂不支持能力
   - HTTP/HTTPS 与 WS/WSS 约束

5. 只在核心闭环完成后评估音频、通知、PWA 和公网部署。

## 预计会涉及的现有文件

| 文件 | 可能的最小改动 |
|---|---|
| `pubspec.yaml` | 增加 Web 浏览器 API 依赖，处理不支持 Web 的插件 |
| `main.dart` | 平台安全的系统 UI 初始化和服务实例 |
| `auth/login_screen.dart` | 移除直接 `dart:io`，隐藏 Android/QR 专属入口 |
| `stream/stream_proxy.dart` | 使用 Web no-op relay；保留 accessUnits |
| `stream/session_controller.dart` | 使用平台无关 decoder，移除直接 `Platform` 判断 |
| `stream/screens/stream_screen.dart` | 使用 VideoSurface，Web 不再显示 unsupported |
| `map/map_screen.dart` | 使用 VideoSurface |
| `shared/app_settings.dart` | 条件化平台默认值 |
| `shared/keyboard_prewarmer.dart` | Web no-op |
| `notifications/*` | Web no-op 或条件导入 |
| `audio/*` | Web no-op，后续再实现 |

## 实现纪律

- 每完成一个阶段就运行 analyze/test/build web。
- 小步提交或至少保持小步 diff。
- 不删除原生实现来换取 Web 编译成功。
- 不把同一业务逻辑复制成 `*_web_screen.dart`。
- 遇到未知时先写最小实验，再决定抽象。
- 如果偏离此方案，在开发记录中说明观测、决定和影响。
