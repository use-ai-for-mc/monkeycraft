# 接入与替换指南

本文依据当前源码与对 MonkeyCraft 26.2 的只读检查编写。列出的旧文件位置相对于接手者自己的 MonkeyCraft 仓库，不依赖原开发机器的绝对路径。本文给出适配方案；Fabric 适配代码还未实现。

## 1. 替换边界

调用链应从“Mod → 子进程协议 → Go helper/tsnet → tailnet”改为“Mod 的适配器 → `TailscaleClient` → tailnet”。Java 库负责一个指定 TCP 端口到固定 loopback 目标的字节流转发，应用层密码、配对、WebSocket、视频与游戏控制继续由原应用处理。

入口是 `com.monkeycraft.tailscale.TailscaleClient`。没有完整的 tsnet `Dial`、UDP listener、子网路由、exit node、Serve/Funnel 或 MagicDNS API。库不自动启动本地 WebSocket 服务，不自动打开浏览器，也不自动与 Fabric 生命周期绑定。

## 2. 依赖与打包

Minecraft 26.2 配置：

| 来源 | 内容 |
|---|---|
| 随库携带 | `tailscale-java.jar`、BC 1.86 子集、Netty HTTP/2 4.2.18 |
| 由宿主提供 | Gson 2.14.0；Netty 4.2.15 的 common、buffer、codec-base、codec-compression、codec-http、handler、resolver、transport |
| 不进入 Java 运行包 | Go 测试对端、完整 BC Provider、JVM、测试类、JNI/JNA、平台 helper |

完整坐标和 SHA-256 以 `minecraft-26.2.json` 为准。HTTP/2 单独采用修复版 4.2.18，基础模块仍复用宿主 4.2.15；这个具体组合已经在独立 JVM 中测试。先前试用的 HTTP/2 4.2.15 不再作为交付输入，原因见 [THIRD_PARTY.md](THIRD_PARTY.md)。

在目标 Mod 的构建中，把三个运行 JAR 加入编译和运行依赖，再按目标 Fabric/Loom 的 Jar-in-Jar 方式纳入最终 Mod。额外 HTTP/2 若通过 Maven 声明，需检查传递依赖解析，避免它悄悄把游戏的整套 Netty 升为另一版本。最终包中也不应误装独立配置的另一套 Netty/Gson。

用 Gradle 的依赖报告核对解析版本；在调试环境检查 `DefaultHttp2HeadersEncoder`、`ByteBuf`、`Gson` 和 `Blake2sDigest` 的实际加载来源。其他 Mod 也可能带入同名类，因此仅核对 Minecraft 的依赖文件不足以证明最终类路径一致。当前 BC 子集没有包重定位，若其他 Mod 携带完整 BC，也需要检查实际加载来源和冲突。不要用“编译通过”代替最终 Mod 加载测试。

其他游戏版本尚未提供可交付配置：1.19 的 Netty 4.1.77 缺 HTTP/HTTP2，且 Gson 2.8.9 不支持当前 `JsonObject.asMap()` 调用；1.21.11/26.1 使用 Netty 4.2.7，缺 HTTP/2。不能直接复制 26.2 的组合并声称已支持。

## 3. 配置与对象生命周期

`Config` 的字段如下：

| 字段 | 含义与约束 |
|---|---|
| `stateDirectory` | Java 专用身份目录；一个实例独占，不能与 Go 状态格式混用 |
| `controlURL` | 明确指定的控制服务器 URI；HTTPS，只有本地回环测试允许 HTTP；没有隐式默认账号或控制服务器 |
| `hostname` | 非空主机名，长度不超过 253 |
| `listenPort` | tailnet 上服务的 TCP 端口，1–65535 |
| `loopbackTarget` | 已解析的回环地址和非零端口；目标固定，不能用于任意主机代理 |

先确认原应用本地服务启动成功，再传入它**实际绑定的端口**。原 MonkeyCraft 可能在端口范围内选择可用端口，不应把配置中的首选端口误当成 `actualPort`。原 helper 启动消息用该端口作为 tailnet 监听端口；保持现有外部地址约定时，通常将 `listenPort` 与 `actualPort` 同步。若业务要改变对外端口，应同时更新展示和连接端信息。

| API | 实际行为 |
|---|---|
| 构造函数 | 校验配置，创建/读取身份并获取目录锁，可能抛异常 |
| `start()` | 异步启动；不是“连接已完成”的同步返回值 |
| `status()` | 返回当前状态及流量快照；不发送远程状态请求 |
| `stop()` | 停止网络，保留身份和对象；可能等待线程退出，仍持有状态锁 |
| `login()` | 先停止，清除本地 logged-out 标志并保存，再启动；不打开浏览器 |
| `logout()` | 停止，尝试提交远程到期，轮换本地节点键并保存注销状态；可能阻塞或抛异常 |
| `close()` | 最终释放线程/网络和身份锁，之后不能再 `start()` |

`Config` 不可变。本地实际端口改变时，先 `close()` 旧实例，再用同一个 Java 状态目录创建新配置的实例。仅调用 `stop()` 后马上构造第二个实例，会遇到状态目录已占用。

建议适配器用单一后台控制队列串行处理启动、登录、停止、注销和关闭，并以代次标记忽略旧实例的迟到回调。状态回调可能来自控制线程或数据线程，不在 Minecraft UI 线程；回调中宜只保存不可变快照、把 UI 更新投递到游戏线程，避免阻塞或同步调用耗时生命周期操作。

## 4. 旧 MonkeyCraft 接入位置

已核对的 26.2 文件位于 `mods/26.2/src/main/java/com/chenweikeng/monkeycraft/`：

| 旧接入点 | 建议适配内容 |
|---|---|
| `tailscale/HelperTailscaleService.java` | 用 Java 后端替代进程创建、nonce/JSON 行协议与 native helper 提取调用；保留其业务门面或新增同等适配器 |
| `tailscale/TailscaleSnapshot.java` | 明确新旧字段语义差异，见下一节 |
| `tailscale/SystemBrowserOpener.java` | 可继续承接登录 URL 的浏览器打开及失败处理 |
| `tailscale/NativeHelperExtractor.java`、`EmbeddedTailscalePlatform.java` | 旧进程后端使用；Java 分支无需提取 helper，但 Java/Fabric 平台能力仍要实际验证 |
| `MonkeycraftClient.java` | 启动/加入世界时使用本地服务返回的实际端口；登录、状态、注销、停止命令连接适配器；退出时关闭 |
| `ui/MonkeyPanelScreen.java` | 状态轮询、登录/注销/停止按钮与主线程刷新 |
| `server/WebSocketServerHandler.java` | 本地服务关闭时关闭 tailnet 后端 |

`ensureRunning(actualPort)` 可对应“配置相同时复用现有 Java 实例，否则关闭并重新创建后启动”。旧 `shutdown()` 对应最终 `close()`。旧 `snapshot()`/`status()` 对应适配器缓存和 `client.status()`，不再需要向子进程发送命令。

构建中原 helper 的二进制资源与提取流程应在验证后的 Java 分支中单独处理。为便于回退，建议先保留旧后端产物和原状态；本交付没有替接手者删除它们。

## 5. 状态与 UI 映射：不能机械复制字段

Java `Status` 含 `state`、`authURL`、`nodeKey`、`addresses`、`error`、`traffic`。当前状态字符串有 `starting`、`needsLogin`、`needsApproval`、`running`、`reconnecting`、`stopped`、`unsupported`，数据面异常还可能发出 `error`。

| 旧 `TailscaleSnapshot` 字段 | 对接要点 |
|---|---|
| `state` | 建立明确映射；原快照可能用 `failed`，库可能给 `error` 或 `unsupported` |
| `tailnetIp` | 从 `addresses` 选择用于展示的地址，保留 IPv6 的处理；IPv6 与端口拼接时使用方括号 |
| `nodeId` | **不能直接填 `nodeKey`**：后者是会轮换的公开节点密钥，不是旧稳定节点 ID；库当前未暴露稳定 ID |
| `port` | 来自适配器持有的 `Config.listenPort()`，不是从 `Status` 获取 |
| `listening` | **库没有直接等价字段**；`running` 主要来自控制 map 中的授权状态，不能据此声称本地目标或端到端路径已可用。接入者需补足就绪信号/验证与 UI 语义 |
| `connections` | 可读取 `traffic.getOrDefault("connections", 0L)`；它是本实现桥接连接数，不是历史累计计数 |
| `errorCode`、`error`、`recoverable` | 库只提供有限错误码；不可把所有异常都标为可恢复，需在适配器分类，未知错误应保留可诊断信息 |

`traffic` 当前包含直连/DERP 的发送和接收计数以及连接数，不能当作视频吞吐字节数或精确链路状态。纯计数变化不一定触发状态回调；需要流量显示时读取 `status()`。

`authURL` 非空时，把最新 URL 交给现有登录交互。库不自动打开浏览器；适配器处理相同 URL 的去重、重新打开、浏览器失败和新一轮密钥到期后的 URL 更新。没有 URL 的 `needsLogin` 不等于注册成功。不要将登录链接或完整身份文件写进公开诊断。

## 6. 迁移与回退

没有 Go/tsnet 状态导入功能。Java 新身份可能得到不同 tailnet IP、设备名记录、节点标识和权限；需要重新核实服务端批准、ACL/tag 和客户端保存的连接地址。`nodeKey` 轮换也不能作为 UI 稳定设备 ID。

建议使用如应用数据目录中的 `tailscale-java/` 作为新状态目录，保留原 helper 的目录。避免符号链接、网络盘和不支持私有权限/原子替换的文件系统。`identity.json` 保存私钥，库会限制文件权限并使用锁与原子替换；Windows ACL 路径尚未实机验证。

本地 `logout()` 成功返回也不证明真实服务端已撤销设备。`remote-logout-unconfirmed` 表示远程请求失败/未确认；UI 和验收记录应保留这一差异。本地测试验证了请求提交与本地停转发，没有验证托管服务的完整远程撤销语义。

回退建议：关闭 Java 实例 → 切回旧实现和原配置/状态 → 验证旧地址与连接 → 再按所有者决定处理新测试设备。回退不需要把 Java 私钥转换成 Go 状态，也不建议删除旧身份来“修复”测试失败。

## 7. 调试与验收

| 现象 | 首先检查 |
|---|---|
| `ClassNotFoundException` / `NoSuchMethodError` | 缺失 JAR、宿主版本、其他 Mod 带入的重复类；记录实际类来源 |
| 状态目录已占用 | 旧实例是否只 `stop()` 而未 `close()`，是否有第二个进程使用同一目录 |
| `control-*` / 反复重连 | 控制 URL、TLS、注册/map 响应；能力版本 39 与真实控制面兼容尚未验证，不要直接提高版本号绕过 |
| `unsupported`、`tailnet-lock` | 当前没有实现所需 Tailnet Lock 能力，需补实现或由所有者选择测试环境，不能伪造成功 |
| `running` 但无法连接 | 实际 loopback 服务与端口、ACL/节点批准、到期状态、目标地址、直连/DERP 收发；不要只改 UI 的 `listening=true` |
| 旧 IP/身份不见了 | Java 状态不是 tsnet 状态格式；先核对新设备与新地址 |
| Unix socket 路径过长 | 设置短一些的专用 `TSJAVA_TEST_TMP` 后重跑本地互操作测试 |

建议按本地协议 → 隔离互操作 → Fabric 类加载 → 专用真实 tailnet → 实际应用流量的顺序记录结果。真实账号和游戏测试需要确认环境范围。详细命令见 [TESTING.md](TESTING.md)，已完成的证据见 [TEST_RESULTS.md](TEST_RESULTS.md)。
