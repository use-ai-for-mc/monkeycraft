# H.264 与 WebCodecs 技术依据

## 结论

现有 MonkeyCraft H.264 payload 很可能可以原样送入浏览器 `VideoDecoder`。不需要先包装成 MP4、MPEG-TS、HLS 或 WebRTC。

仍然必须用真实浏览器和真实 Mod 做 PoC，因为 WebCodecs 是否支持某个 H.264 profile 取决于浏览器、操作系统、硬件和构建方式。

## 当前服务器输出

三个 Mod 树都使用 JCodec 0.2.5 的 `H264Encoder`。关键实现：

```text
mods/<mc>/src/main/java/com/chenweikeng/monkeycraft/server/H264Streamer.java
```

已确认的行为：

- `encodeFrame` 每次生成一个视频帧的 access unit。
- 每个 access unit 作为单独一条 WebSocket binary message 发送。
- 输出使用 Annex-B start code。
- IDR access unit 内含 SPS、PPS、IDR slice。
- 首个需要通知分辨率的 IDR 会额外带 6 字节 MonkeyCraft header：

  ```text
  0x4D 0x43 widthHi widthLo heightHi heightLo
  ```

- Flutter `StreamProxy` 已经剥离该 header，再发布 H.264 access unit。

用项目实际依赖的 JCodec 0.2.5 生成样本，开头为：

```text
00 00 00 01 67 42 00 28 ...   SPS
00 00 00 01 68 ...            PPS
00 00 00 01 65 ...            IDR
```

由 SPS 的 `42 00 28` 可得当前 codec string：

```text
avc1.420028
```

对应 H.264 Baseline Profile、Level 4.0。

更稳健的实现可以从首个 SPS 读取 profile、constraint 和 level 字节，动态生成 codec string，但第一版可以先验证固定的 `avc1.420028`。

## WebCodecs 对 Annex-B 的要求

W3C H.264 WebCodecs registration 规定：

- `EncodedVideoChunk` 的数据应是一个 access unit。
- `VideoDecoderConfig.description` 缺失时，输入按 Annex-B 处理。
- Annex-B 的 key chunk 应包含 IDR picture 和解码所需的 parameter sets。

MonkeyCraft 当前格式与这三个条件匹配。

参考：

- <https://w3c.github.io/webcodecs/avc_codec_registration.html>
- <https://w3c.github.io/webcodecs/>
- <https://developer.mozilla.org/en-US/docs/Web/API/WebCodecs_API/Using_the_WebCodecs_API>

## 建议配置

概念配置如下，最终使用 `package:web` 的 Dart API 表达：

```javascript
const config = {
  codec: "avc1.420028",
  optimizeForLatency: true,
  hardwareAcceleration: "no-preference"
};
```

注意：

- 不提供 `description`。
- `codedWidth` 和 `codedHeight` 可以先省略，让 decoder 从 SPS 获取。JCodec 对非 16 倍数尺寸可能使用编码尺寸加 cropping；直接把 MonkeyCraft 的显示尺寸当 coded size 可能不准确。
- 如果后续发现特定浏览器要求尺寸，可以解析 SPS，或用向上取整到 16 的 coded size，同时保持正确显示尺寸。
- 初始化前调用 `VideoDecoder.isConfigSupported(config)`。

## Chunk 构造

每条 `accessUnits` 事件对应一个 chunk：

```javascript
new EncodedVideoChunk({
  type: containsIdr ? "key" : "delta",
  timestamp: frameIndex * 1000000 / fps,
  duration: 1000000 / fps,
  data: accessUnit
});
```

关键要求：

- timestamp 单位为微秒且必须单调递增。
- `type: key` 只用于包含 IDR 的 access unit。
- 当前 `h264_nal.dart` 已经能识别 3 字节和 4 字节 start code 后的 NAL type 5。
- decoder reset 或 error 后必须等待 key chunk。
- 不要把 SPS、PPS、slice 拆成三个 `EncodedVideoChunk`；它们共同构成一个 access unit。

## 渲染

decoder output 返回 `VideoFrame`。第一版建议：

1. 创建 `HTMLCanvasElement`。
2. 从 canvas 获取 2D context。
3. `drawImage(videoFrame, ...)`。
4. 立即调用 `videoFrame.close()`。
5. 通过 `HtmlElementView` 将 canvas 嵌入 Flutter Widget tree。

canvas 的 CSS size 由 Flutter layout 控制，backing width/height 与视频帧尺寸一致。为避免抢占控制手势，设置：

```css
pointer-events: none;
```

如果 platform view 与 Flutter overlay 在特定 renderer 上出现层级问题，可以分别验证 CanvasKit 和 skwasm，但不要在没有复现前重写为像素复制管线。

## 背压与恢复

WebCodecs 是异步队列。低延迟应用不能无限调用 `decode()`。

建议策略：

- 观察 `decodeQueueSize`。
- 队列在小范围内正常入队。
- 队列持续超限时，优先丢弃 delta，而不是积累播放延迟。
- 严重落后时 reset decoder、发送 `REQUEST_KEYFRAME`、等待 IDR。
- decoder error 后不能继续使用 closed 实例，应新建实例。
- 浏览器切后台后恢复时也应允许重新请求 IDR。
- 每个 output frame 必须 close，否则会耗尽 decoder/GPU 资源。

现有 Mod 已有 `REQUEST_KEYFRAME`，现有客户端已有 `proxy.requestKeyframe()`，无需增加协议。

## 浏览器范围

截至本方案整理时，MDN compatibility data 标记：

- Chrome：94+
- Chrome Android：跟随 Chrome
- Edge：跟随 Chromium
- Safari/macOS：16.4+
- Safari/iOS：跟随 Safari
- Firefox desktop：130+
- Firefox Android：不支持

参考：

- <https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/VideoDecoder.json>
- <https://webkit.org/blog/14787/webkit-features-in-safari-17-2/>

这个表只表示 `VideoDecoder` API，不保证具体设备支持 `avc1.420028`。功能检测必须保留。

## 安全上下文与 WebSocket

`VideoDecoder` 需要 secure context。开发时 `localhost` 通常被视作可信来源。正式部署时：

- 页面使用 HTTPS。
- HTTPS 页面不能连接普通 `ws://`。
- WebSocket 必须改为 `wss://`，或经由同源 TLS 代理连接 Mod。
- 自签名证书常会在浏览器中造成额外阻断。

第一版应先证明本地链路，不要把 TLS 网关与视频 PoC 捆绑为同一个任务。

## 失败时的备选顺序

若原样 Annex-B 解码失败，按以下顺序排查：

1. 保存首个完整 IDR access unit，检查 SPS/PPS/IDR start code 和 codec string。
2. 检查每条 WebSocket binary message 是否仍是单个 access unit。
3. 检查 `type` 和 timestamp。
4. 检查 decoder 是否在 delta 开始前收到 key。
5. 尝试动态从 SPS 构建 codec string。
6. 检查 coded/display dimensions 和 cropping。
7. 对比 Chrome、Safari 或另一台有硬件 H.264 的设备。
8. 最后才考虑 Annex-B 转 AVCC 或封装 fragmented MP4。

不要因为第一次 configure/decode 报错就直接改服务器协议。
