# Android 离线 H.264 回放集成（2026-09-19）

## 范围

使用本机 `web/tools/replay-server.ts` 的 `streaming-360x640` 录制夹具，通过 ADB reverse 提供给 API 36 arm64 模拟器。测试密码为回放夹具固定值 `test`，不读取用户凭证，不连接 Minecraft、Tailscale 或任何账户。

集成测试实际使用生产 `StreamProxy` 的直连 WebSocket、`SessionController.handleAccessUnit`、`HardwareH264Decoder`、Android `H264DecoderPlugin` 的 MediaCodec 与生产 `VideoSurface`。最小 MaterialApp 将每轮新 decoder 的 Texture 挂在固定 360×640 容器中，因此不仅验证认证或收到二进制帧。

## 验收

每轮连接均要求原生 stats 的 `decodedFrames` 至少达到 5，然后再次读取并要求该值继续增长；同时验证 `inputAccessUnits`、`width=360`、`height=640` 与 `decoding=true`。主动退出时先卸载 VideoSurface，再取消帧订阅、停止 StreamProxy、释放 decoder，并断言原生 `getStats` 返回空 map。随后同一 StreamProxy 重连、重建 decoder 并重复验证。

Android 实际执行时，夹具文件名还是 `android_stream_h264_replay_test.dart`：

```text
flutter test integration_test/android_stream_h264_replay_test.dart -d emulator-5554
```

结果：1 项通过。该夹具随后更名为跨平台的 `native_stream_h264_replay_test.dart`；没有为纯改名重新运行 Android。当前复现应先在一个终端的仓库根目录启动回放服务并保持运行：

```text
node web/tools/replay-server.ts --port 9601 --fixture streaming-360x640 --password test
```

在另一个终端的仓库根目录连接已启动的测试模拟器，再运行夹具：

```text
adb -s emulator-5554 reverse tcp:9601 tcp:9601
cd flutter/monkeycraft
flutter test integration_test/native_stream_h264_replay_test.dart -d emulator-5554
```

Android 仍保留 `decoding=true` 断言。iOS 的同名字段语义不同，详见 iOS 视频证据；这不改变 Android 的已运行结果。

| 连接 | inputAccessUnits | decodedFrames | droppedAccessUnits | decoding | 尺寸 |
| --- | ---: | ---: | ---: | --- | --- |
| 首次 | 8 | 6 | 1 | true | 360×640 |
| 重连 | 8 | 7 | 0 | true | 360×640 |

首次轮记录到1个access unit丢弃；同时已有6个实际MediaCodec输出帧，并且计数继续增长。重连轮没有记录丢弃。

测试结束后已撤销 `tcp:4173`、`tcp:9601` reverse，正常停止本机 Vite 与 replay-server，并以 `adb -s emulator-5554 emu kill` 关闭唯一模拟器，确认设备从 ADB 列表消失。

## 边界

这是离线录制 H.264 的模拟器验证，证明上述生产 Dart→Texture→MediaCodec 链路和重连释放行为。它不构成完整游戏 UI 操作、物理屏幕视觉质量、真机硬件解码、真实 Minecraft 网络、账户认证或 tailnet 连通性的验收。
