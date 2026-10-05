# Experimental Java Tailscale client

**接手替换工作请先读 [HANDOFF.md](HANDOFF.md)。** 具体适配见 [INTEGRATION.md](INTEGRATION.md)，已经执行的验证见 [TEST_RESULTS.md](TEST_RESULTS.md)。

这是在 JVM 内接入 Tailscale 的实验库：通过控制协议、WireGuard、DERP 和 UDP 发现建立连接，将一个指定的 tailnet TCP 端口转发到固定的 loopback 服务。运行时不依赖 Go、JNI、TUN、系统 Tailscale 或管理员权限。

目标是承担这类应用中 tsnet 的嵌入式联网职责；当前不是完整 tsnet API 的替代品，也不是已经完成真实 Tailscale 托管服务验证的正式客户端。

默认交付复用 Minecraft 26.2 的 Netty/Gson，另外携带精简 BC 与 HTTP/2。其他应用可使用独立依赖配置。这个仓库提供 Java 库，不是可以放进 `mods/` 的 Fabric Mod。

## 构建

需要 JDK 17 或更高版本和 Python 3.10 或更高版本。首次构建按 SHA-256 锁定下载 Maven 依赖；运行库不会联网下载依赖。

```sh
python3 tools/build.py
```

Windows 可使用 `python tools/build.py`，通过 `JAVA_HOME` 选择 JDK。默认产物是 `dist/tailscale-java-minecraft-26.2-libs.zip`；本库以 Java 17 字节码编译，但 Minecraft 26.2 本身使用 Java 25。构建会运行加密/协议与 HTTP/2 依赖回归测试，不会登录真实 Tailscale 或启动游戏。

```sh
python3 tools/build.py --profile standalone
python3 tools/build.py --offline
```

`--offline` 要求所选配置的全部依赖已在本项目缓存中。独立包携带 Netty/Gson；Minecraft 配置不携带游戏提供的模块，其完整坐标与哈希在 `minecraft-26.2.json` 和分发包的 `host-requirements.json`。

BC 完整 Provider 仅作构建输入。构建提取 BLAKE2s、XChaCha20-Poly1305 及其传递依赖，保持每个 class 的上游字节码不变，保留来源、许可证和逐类哈希。没有重写加密算法或关闭认证校验。

## 在应用中使用

将 `tailscale-java.jar` 和分发包中 `lib/` 的 JAR 加入应用类路径。Minecraft 配置还需要宿主提供清单列出的依赖，不能独立运行。不要在游戏中再加入独立包的另一套 Netty 基础模块。

```java
var config = new TailscaleClient.Config(
    stateDirectory, controlUrl, hostname, tailnetPort,
    new InetSocketAddress("127.0.0.1", localPort));
var client = new TailscaleClient(config, status -> {
    // 将状态和登录 URL 转交给应用 UI。
});
client.start();
// client.status(); client.stop(); client.login(); client.logout();
// 应用退出时调用 client.close()。
```

可编译的完整入口见 `examples/LoopbackBridge.java`。示例必须显式提供控制服务器、状态目录和端口，不会自动使用系统 Tailscale 或默认账号。状态目录包含私钥，应留在用户本机，不能提交仓库。`stop()` 保留身份，`logout()` 提交远程到期请求并清除本地节点键，`close()` 释放资源。

## 已验证与未验证

已有隔离环境验证：Java 17/21/25、标准加密向量、Noise 控制连接、HTTP/2 大消息、Go WireGuard、tsnet 与官方 tailscaled 的 TCP 互通、直连/DERP、登录批准与密钥到期、跨 JVM 身份恢复、ACL 拒绝/恢复。Minecraft 26.2 依赖组合在独立 JVM 中验证，尚未证明 Fabric 内部加载兼容。

关键缺口仍在：用户态 TCP 使用教育用途 Wirefin 核心，尚无成熟协议栈等价的拥塞/异常网络验证；真实 Tailscale 托管控制面、节点键挑战和长期协议兼容尚未验证；没有完整 Tailnet Lock 支持，遇到要求会停止。Windows 实机、长期视频流和独立安全审查也未完成。

当前只开放一个指定的 TCP 端口并转发到固定 loopback，不提供任意出站 Dial、UDP 服务、子网路由、exit node、Serve/Funnel 或完整 tsnet API。不能将本地测试通过解释为可无条件替换正式 tsnet。

## 测试与发布准备

详见 [TESTING.md](TESTING.md)。Go 1.26.6 仅用于本地测试对端，不进入分发包。测试不连接个人 tailnet、不启动 Minecraft、不读取系统客户端状态。

源码、依赖锁和测试入口已整理；[许可证状态](LICENSE-STATUS.md) 中的原创代码许可证还需要项目所有者确定。第三方来源和限制见 [THIRD_PARTY.md](THIRD_PARTY.md)。没有发布 Maven 坐标、创建远程仓库或上传代码。
