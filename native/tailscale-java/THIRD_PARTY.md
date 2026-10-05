# 第三方来源

- Wirefin 纯包处理核心：MIT，提交 `c64848e405e470474c995faab6a3229e3dd2d2e8`。来源为 `https://github.com/shri299/wirefin`；没有包含 JNA/TUN 集成。该实现是教育用途，不能视为成熟用户态 TCP 栈。
- TweetNaCl Java：MIT，提交 `9279c44925808ecb640b2d05189288507578cc5f`，来源为 `https://github.com/InstantWebP2P/tweetnacl-java`。NaCl 消息显式使用安全随机 nonce。
- Bouncy Castle 1.86：锁定官方 Maven JAR；构建保留所需算法的完整传递类依赖。没有注册 JCA Provider，JDK 提供 X25519、ChaCha20-Poly1305 和 TLS。子集不冒充完整 BC Provider。
- Netty：Apache 2.0 及上游 notices。独立配置使用 4.1.138；26.2 宿主基础模块为 4.2.15，额外 HTTP/2 为修复后的 4.2.18。这个特定组合需要独立验证，不能外推到所有 Netty 版本。
- Gson：Apache 2.0；独立配置 2.13.2，Minecraft 26.2 配置复用宿主 2.14.0。
- Tailscale 1.102.3：BSD-3-Clause，作为协议参考和隔离测试对端。Go 不在 Java 的运行依赖中。
- WireGuard Go 测试适配层：MIT；`tests/interop/internal/wgnetstack` 从锁定上游用户态 netstack 适配，调整了锁定 gVisor 的空值 API。

许可证全文位于 `licenses/`，源码哈希在 `vendor.json`，下载来源及 SHA-256 在 `dependencies.json`、`minecraft-26.2.json`。

HTTP/2 4.2.15 的已知 HPACK 问题见 [GHSA-8352-h356-c9qh](https://github.com/netty/netty/security/advisories/GHSA-8352-h356-c9qh)。它影响的依赖版本已从当前分发配置中替换；没有把“与宿主版本号一致”作为携带旧实现的理由。这不代表本库已完成全面安全审查。
