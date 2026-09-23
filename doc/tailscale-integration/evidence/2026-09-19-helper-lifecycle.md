# 26.2 Helper 生命周期回归（2026-09-19）

## 发现与修复

复核真实 helper `Engine` 后确认：同一 child 的第二个 `start` 会返回 `ALREADY_STARTED`，不能把再次 start 当作浏览器重试；logout 成功后才会发出 `needsLogin`，若提前杀 child 会丢失 logout 结果。还发现旧 helper 在 stop 或 shutdown 后的消息可能触发浏览器或覆盖 stopped，存活 helper 的端口变更也不应再发第二个 start。

`HelperTailscaleService` 现将 AuthURL 仅保存在内存，不写入 snapshot、诊断或日志。浏览器失败时，显式 `login(port)` 会用缓存 URL 重试打开浏览器，不发送 start；自动 ensure 只做生命周期去重。缺失 URL 保持可见错误；失败状态收到真实 running/listening 后让成功状态覆盖。

stop 与 shutdown 会立即发布 stopped、使旧 child/input 脱离服务并在控制线程终止；旧 child 的 stdout、stderr 与 exit callback 均按 process generation 过滤。端口变更会先终止旧 child，再启动新 child，避免真实 Engine 的 `ALREADY_STARTED`。logout 带独立 requestId，保持 child 存活直到收到同 requestId 的 needsLogin 或 error；期间拒绝新的 ensure 和 login 重开，成功 needsLogin 后才停止 child，下一次 login 才启动新 child，且 logout 期间不会自动打开认证页。

## 离线验证

`HelperTailscaleServiceLifecycleTest` 使用生产一致的脚本化 helper：重复 start 返回 `ALREADY_STARTED`，logout 返回 needsLogin。覆盖：

- 浏览器打开失败后，status 不覆盖错误；显式 login 使用缓存 URL 重试并清除失败状态，且 start 计数仍为一；
- 同端口存活 helper 的重复 ensure 不发送第二个 start；
- stop 后 stdin EOF 才发出的 authRequired 不打开浏览器，随后同 JVM restart 启动新 child；
- 端口变更产生新 child，不向旧 child 发送第二个 start；
- logout 在无 child 的 queued start 阶段会取消该 start；在等待匹配结果期间 login 不会重开浏览器或改写状态；匹配 needsLogin 后停止 child，新的 login 启动新 child。

执行：

```text
JAVA_HOME=/opt/homebrew/opt/openjdk@25 PATH="$JAVA_HOME/bin:$PATH" \
  ./gradlew --no-daemon test \
  --tests com.chenweikeng.monkeycraft.tailscale.HelperTailscaleServiceTest \
  --tests com.chenweikeng.monkeycraft.tailscale.HelperTailscaleServiceLifecycleTest
```

通过。所有 helper 均为临时脚本；没有连接 Minecraft、启动真实 helper、登录浏览器、账户、auth key 或 tailnet。

本次只修改源码与测试，未构建或部署新 26.2 JAR；正在进行的游戏验收不受该工作目录变更影响。
