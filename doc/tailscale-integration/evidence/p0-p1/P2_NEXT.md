# P2 下一步：Java extractor / process supervision

本轮停止在 standalone helper。下一轮（仍先 26.2，不改另外三棵树的产品行为）建议按此顺序：

1. **`NativeHelperExtractor`**  
   复用 imf 的 JAR 资源 SHA-256 sidecar + 临时文件 rename。资源路径：`/native/tailscale/<os>-<arch>/monkeycraft-tailscale-helper`。缓存目录：`FabricLoader.getConfigDir()/monkeycraft/tailscale/helper/`。缺二进制 → `BINARY_MISSING`，不得尝试本机编译。

2. **平台选择器**  
   显式映射 `darwin-arm64` / `darwin-amd64` / `windows-amd64`（仅这些在 P2 标“构建过”）。`os.name` 模糊匹配禁止。Linux/Windows ARM 显示 unsupported。

3. **`HelperProcess` 监督**  
   照 imf `WebViewBridge`：stdin JSON Lines、stdout 行长/总量上限、stderr 脱敏轮转、ready 超时、只杀直接子进程、父退出关闭 stdin、指数退避熔断。sessionNonce 每次启动随机。协议版本不符 fail closed。

4. **`TailscaleService` 接口**  
   `ensureRunning(actualPort)` / `stop()` / `logout()` / 状态回调。`WebSocketServerHandler` 只在 start/stop 和实际端口变更点调用，不解析 JSON。

5. **fake helper fixture**  
   脚本化 `authRequired → running → listening`、malformed stdout、timeout、crash、旧协议、state lock。四棵树先只在 26.2 跑；共享纯 Java 类保持字节一致。

6. **不要在 P2 做的**  
   Cloth Config UI、打开系统浏览器、把 helper 打进发布 JAR 作为默认功能、同步 26.1/1.21.11/1.19。那些是阶段 3+。

7. **P2 准入前补的真机洞**  
   浏览器批准一次 → 重启 helper 确认持久 Node ID；另一台已装系统 Tailscale 的设备 TCP 连 `:listenPort` 再转到 127.0.0.1 echo。
