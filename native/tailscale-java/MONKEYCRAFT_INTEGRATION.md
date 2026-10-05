# MonkeyCraft 四版本接入记录

来源：用户提供的 `tailscale-java-handoff.zip`，SHA-256：
`3361c25a042cae2513ae97957012f4a5bf66be269867b33bc61e63bcde249e27`。
本目录由最初的 `mods/26.2/third_party/tailscale-java/` 移至 `native/tailscale-java/`，供四个版本共用。
本目录来自该包中的源码归档；保留原始交接文档、源码、锁定依赖及第三方许可证。
`SOURCE-MANIFEST.json` 是交接时的原始清单，不是本地修改后的校验清单。

本地改动：`DataPlane` 暴露实际监听状态，`TailscaleClient.isListening()` 提供线程间可见的只读查询。
控制面授权成功但监听尚未建立、已关闭、或设备已过期时，不应向 MonkeyCraft 报告就绪。
2026-10-04 实机发现：托管控制面的 Peers 不带 MachineAuthorized。
该字段用于本机授权；官方客户端也只用 SelfNode.MachineAuthorized 决定本机是否获批。
NetworkMap.usable 不再把它作为 peer 可用条件，继续检查过期、隔离、UnsignedPeerAPIOnly、
对端身份/源地址及 ACL；本机 ready() 仍要求明确授权。ProtocolTests 增加字段省略及限制条件回归。

26.2 的 Gradle `buildJavaTailscale` 调用 `tools/build.py`，使用 Java 25 编译并执行库的协议和依赖检查。
构建需要 Python 3，可用 `-PpythonExecutable=/absolute/path/python3` 指定。
依赖只在构建期间下载，校验锁定的 SHA-256；游戏运行时不下载组件。
Mod 包合入 Java 库、BC 最小类集和 Netty HTTP/2 4.2.18 的类及许可证，复用 Minecraft 的 Gson 和其余 Netty 模块。
没有把 Gson 或基础 Netty 再次打入 Mod，也没有注册 BC Provider。
原生 helper 继续随包提供，用于回退。

普通构建默认使用 helper。Java 测试包的构建参数为：

```sh
./gradlew spotlessApply build -PtailscaleBackend=java -Pmod_version=1.4.4-java-test.1-26.2
```

启动参数 `-Dmonkeycraft.tailscale.backend=helper` / `java` 优先于包内默认值。
选择后端后，整个游戏进程保持该选择；切换需要重启游戏。
本次没有扩大支持平台，仍只启用 Apple Silicon macOS 和 Windows x64。

Java 身份保存在实例的 `config/monkeycraft/tailscale-java/`，原生身份继续保存在
`config/monkeycraft/tailscale-state/`。不迁移、不覆盖原生身份。首次 Java 登录是新设备，可能得到新地址。
构建日志和测试报告不能包含实际登录链接、身份文件或私钥。

此目录的 `LICENSE-STATUS.md` 仍适用；没有替用户为交接源码指定公开发布许可证。
本次用途为本地整合测试，没有发布正式版本。

## 26.1 / 1.21.11 / 1.19

三个旧版本通过 `embedded.gradle` 构建同一份协议源码和生命周期适配器。
宿主实际依赖分别为 Netty 4.2.7 / Gson 2.13.2（26.1、1.21.11）和
Netty 4.1.77 / Gson 2.8.9（1.19），不能直接使用 26.2 的宿主依赖配置。
因此使用交接包锁定的 standalone 依赖（Netty 4.1.138、Gson 2.13.2、BC 1.86 子集），
由 Shadow 9.6.1 重定位到 `com.monkeycraft.tailscale.internal`，不会替换宿主同名类。
该过程仅发生于构建期；运行时仍无组件下载。未启用最小化删除，保留运行依赖及许可证。
26.2 保留已经实机验证的原打包方式。

每个项目的生成文件位于自己的 `build/tailscale-java/`，共用下载缓存，避免不同 Java
版本的编译结果互相覆盖。Gradle 构建会执行源码协议检查、重定位后的协议及依赖检查，
以及 Mod 生命周期测试。Java 17 的适配器测试避免使用 Java 21 的集合 API。
旧版本保留原 Cloth Config 界面，显示所选后端；登录和状态查询沿用 `/monkey tailscale` 命令。

测试包继续用 `-PtailscaleBackend=java -Pmod_version=1.4.4-java-test.2-<mc>` 构建。
普通构建仍默认 helper，正式版本号、默认后端和发布时机等待用户测试后的决定。

最终包隔离互通测试：将 `build/tailscale-java/test-classpath.txt` 设为
`isolated/tailscale-java-tests.jar` 与最终 Mod JAR 的绝对路径（用系统 classpath 分隔符连接），
使用该版本对应的 JDK 运行：

```sh
python3 native/tailscale-java/tools/interop.py --build-dir mods/<mc>/build/tailscale-java --recovery --streams
```

测试仍是临时本地控制面和官方对端，不读取个人 tailnet 身份。
依赖重定位方式参考 [Shadow 官方文档](https://gradleup.com/shadow/custom-tasks/)。
