# 测试说明

`python3 tools/build.py` 在所选 JDK 上重新编译、执行协议与依赖测试，并生成包。通过 `JAVA_HOME` 分别选择 Java 17、21、25 可复验三种 JVM。

验证内容包括 X25519 和 XChaCha 的公开 Go 向量、低阶点拒绝、错误认证标签、WireGuard cookie/重放窗口/计数器伪造/换钥/到期、源地址归属与 ACL、IPv6、状态目录锁与身份恢复。额外 HTTP/2 检查在对端声明极大 HPACK 表时验证本地内存上界；旧的 4.2.15 额外模块不再作为发布输入。

## 隔离互操作

需要 Go 1.26.6、已完成一次构建，以及 macOS 或 Linux。若 Go 不在 PATH，通过 `GO_BIN` 指定。测试需要首次下载锁定的 Go 模块，默认缓存在本项目 `.cache/`。

```sh
python3 tools/build.py
python3 tools/interop.py --recovery --streams
```

测试自行创建 loopback 控制面、DERP/STUN、tsnet 对端和私有状态/套接字的官方 tailscaled。运行内容包括控制连接与 250 KB HTTP/2、WireGuard/Go TCP 互通、官方客户端直连和 DERP、交互登录/批准、进程退出后身份恢复、过期换钥、ACL 拒绝恢复、注销及关闭。`--recovery` 增加 IPv6 TCP 与 UDP 中断后 DERP 回退及直连恢复。`--streams` 增加四条并发连接，每条双向回显 2 MiB，包含延迟读取、慢速读取、半关闭和完整 EOF 校验；这些是有界压力测试，不代表长时间稳定性验证。日志保存到 `build/test-results/`。

官方客户端测试目前依赖 Unix socket，因此 CI 配置在 Windows 仅运行构建与协议测试；本地尚未运行 Windows，也没有执行远程 CI。不能据此宣称 Windows 官方客户端互操作已通过。互操作测试不会读取真实认证密钥，测试状态和证书均临时生成，Java 只信任本次本地 DERP 证书。

## 真实环境尚待验证

下面是建议的后续验证范围，不是已经通过的测试，也不是项目所有者已经确认的新规则：

1. 专用测试 tailnet 上的浏览器登录、设备批准、密钥到期、注销与服务器撤销。
2. 实际 Fabric 类加载，确保只使用预期的宿主 Netty/Gson、没有重复类或方法缺失。
3. 不同 NAT、手机蜂窝与 Wi-Fi、UDP 被阻断、DERP 断线与切换、电脑睡眠唤醒。
4. 长连接、双向持续流量、慢接收端、零窗口、半关闭、丢包、乱序与资源回收。
5. Windows/macOS 平台行为与独立协议/安全审查。

真实环境测试应使用专用测试状态和账号，按项目所有者确认的范围运行。构建与 CI 不会自动发起这些操作。

如果 Unix socket 因检出目录过长而失败，可用 `TSJAVA_TEST_TMP` 指定较短的专用临时目录。项目缓存默认位于 `.cache/`；`GO_BIN` 可指定固定 Go 工具链。
