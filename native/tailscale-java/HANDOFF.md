# 接手说明：用 Java 库替换嵌入式 tsnet/helper

交接日期：2026-10-04。接手者无需阅读此前对话，先读本文，再按 [INTEGRATION.md](INTEGRATION.md) 接入。

## 这次交接要完成什么

项目所有者希望使用纯 Java 实现，替代 MonkeyCraft 当前 Go helper/tsnet 承担的 Tailscale 接入与固定本地端口转发，并优先复用 Minecraft 已有的依赖。当前已经交付可以构建、可以与官方对端在隔离网络中互通的实验库；**尚未完成 MonkeyCraft/Fabric 适配，也不能直接宣称已可靠替代正式 tsnet**。

当前默认依赖配置针对 Minecraft 26.2，运行游戏使用 Java 25。本库编译目标为 Java 17，Java 17/21/25 均有构建和协议测试证据。其他 Minecraft 版本的依赖组合尚未交付，不能把 Java 版本兼容理解为全部游戏版本兼容。

## 接收的文件

| 文件或目录 | 用途 |
|---|---|
| `tailscale-java-project.zip` | 完整源码项目；解压后的顶层目录是 `tailscale-java/` |
| `tailscale-java-project-minecraft-26.2-libs.zip` | 交接包中的预构建运行库；来源是源码项目 `dist/tailscale-java-minecraft-26.2-libs.zip` |
| `SHA256SUMS.txt` | 交接包内各文件的校验值；由交接打包流程生成 |
| `src/main/java/com/monkeycraft/tailscale/` | Java 客户端实现 |
| `examples/LoopbackBridge.java` | 已编译验证的完整调用入口 |
| `tools/build.py` | 下载锁定构建依赖、编译、协议测试和打包 |
| `tools/interop.py`、`tests/interop/` | 本地控制面、tsnet 和官方 tailscaled 互操作测试 |
| `minecraft-26.2.json` | 宿主提供与本库额外携带的依赖清单和哈希 |
| `docs/verification.json`、`docs/test-results/` | 交付时的验证记录和选取的测试输出 |

运行库 ZIP 含 `tailscale-java.jar`、`lib/bc-lightweight-subset-1.86.jar` 和 `lib/netty-codec-http2-4.2.18.Final.jar`。它需要 Minecraft 提供 Netty/Gson，不是可以直接放入 `mods/` 的 Fabric Mod。

## 建议接手顺序

以下是基于当前实现的接入建议，不是项目所有者新增的项目规则。

1. 解压源码，在本机设置 `JAVA_HOME`，运行 `python3 tools/build.py`。Windows 可使用 `python`。核对输出含 `PROTOCOL_TESTS_OK` 和 `DEPENDENCY_CHECKS_OK`。
2. 在 macOS/Linux 上准备 Go 1.26.6，运行 `python3 tools/interop.py --recovery --streams`。这一步只连接临时本地网络，预期最终输出 `INTEROP_PASS`。
3. 阅读 [INTEGRATION.md](INTEGRATION.md)，实现应用层适配器：生命周期、状态、登录 URL、实际本地端口与旧 UI 的对接。保留旧后端以便对照和回退。
4. 在目标 Fabric 构建中加入三个运行 JAR，复用宿主 Netty/Gson，检查实际类来源及重复依赖；再验证应用主线程、停止/重启、游戏退出等行为。
5. 在项目所有者确认的账号和实例范围内，完成真实 Tailscale 登录、设备批准、访问控制、过期、注销和远端 TCP 验证。
6. 对比原实现进行视频流、长连接、网络变化和目标平台测试，记录结果后再判断正式替换是否合适。

## 已做与没做

已验证：Java 17/21/25 构建和协议检查；真实 Go WireGuard 与官方 tailscaled/tsnet 对端在本地测试网络中互通；直连/强制 DERP；IPv6；UDP 中断后的 DERP 回退和恢复直连；跨 JVM 身份恢复；ACL 拒绝与恢复；四条并发连接各 2 MiB、延迟/慢速读取、半关闭与完整 EOF。详见 [TEST_RESULTS.md](TEST_RESULTS.md)。

尚未验证或实现完整：真实 Tailscale 托管控制面、Fabric 实机加载、Windows 实机、所有公网 NAT 类型、长期视频流稳定性、完整用户态 TCP 成熟度、Tailnet Lock 和现代控制协议全部语义。当前能力版本为 39，不能通过把版本号改成上游最新值来替代缺失能力的实现。

用户态 TCP 复用了教育用途 Wirefin 核心；已有有界测试不能证明与成熟 gVisor 栈等价。当前入口拒绝未支持的 IP 分片和 IPv6 扩展头/分片，完整 PMTU、拥塞恢复和异常网络行为仍需继续。这些是接手工作的重要组成部分。

## 身份、切换与回退

Java 库使用自己的 `identity.json`，没有实现导入 tsnet/Go helper 状态的迁移器。接入时使用独立状态目录，首次在真实服务上使用应预期产生新的设备身份和登录过程；旧 IP、旧设备标识和原授权不会因更换库自动继承。

建议保留旧 helper 的状态和构建产物，逐步接入 Java 后端。回退时先关闭 Java 实例，切回旧后端及其原状态目录，再验证原访问入口。`stop()` 只停服务，不释放状态目录锁；需要 `close()` 才能由另一个 Java 实例重新打开同一目录。旧后端状态与 Java 状态不互相覆盖。

## 交接时的操作范围

此前项目所有者要求研究期间不修改原 MonkeyCraft、不连接真实 tailnet、不启动 Minecraft。本次只读检查了接入点，没有修改或启动原项目，也没有访问个人 Tailscale 状态。本次文档交接本身不代表已经获准在接手者环境登录账号、部署或启动游戏；相关范围由项目所有者与接手者确认。

没有创建远程仓库、上传源码或发布 Maven 包。新增代码的发布许可证尚未指定，见 [LICENSE-STATUS.md](LICENSE-STATUS.md)。所有第三方许可证和来源已保留。

## 完成接入后的回报内容

建议交付实际适配代码、构建产物、所用 Minecraft/JDK/依赖版本、类加载来源、测试结果与失败日志，以及明确的旧后端回退步骤。真实环境结果应与本次隔离测试记录分开写；未完成的项目保持未完成状态。
