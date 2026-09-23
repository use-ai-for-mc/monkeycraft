# Web 意外断连自动恢复

日期：2026-09-19。范围为浏览器 Web 客户端的回放夹具验证；未连接真实 Minecraft `:9600`，未操作游戏、手机或账户。

## 故障与修复

真实 26.2 重启后，已经通过 HMAC 认证的浏览器连接会收到 `closed`。控制器先将 reducer 状态发布为 `idle`，随后才发布 `reconnecting`。`App` 的 signal effect 会同步看见中间 `idle` 并回到登录页；后台连接虽恢复，已卸载的 stream/debug UI 不会回来。

`SessionController` 现在将认证后、非主动且没有服务器 `DISCONNECT` 原因的 `closed` reducer 更新、连接清空、凭证失效处理和 `reconnecting` 调度置于 `@preact/signals` 的同一 `batch`。外部 effect 只会观察到 `reconnecting`，而显式退出、服务器拒绝和已经失败的握手仍保留原来的登录页行为。

## 浏览器回归

新增 `web/test/browser/reconnect.spec.ts`。它以 `streaming-360x640` 回放服务器完成密码认证，透过应用自身的 `RUN_COMMAND` 发出 `/replay close 1011`（有效的异常 WebSocket close code），然后断言：

1. stream 页面仍存在；
2. `Reconnecting…` overlay 实际出现，再在新连接认证后消失，debug overlay 回到 `link connected`；
3. 清空初始连接日志后，按同一 tag 从回放服务取回恰好一条新的 `AUTH` 和一条新的 `CLIENT_STATUS`，证明不是关闭指令送达前的旧连接状态。

修复前，该测试在 15 秒内找不到 `.stream`，页面显示 `Disconnected.` 登录页。修复、重新构建 Web bundle 后执行：

```bash
cd web
PATH=/opt/homebrew/bin:$PATH pnpm exec playwright test test/browser/reconnect.spec.ts --reporter=line
```

结果为 1/1 通过（Chromium，强化后约 3.7 秒）。随后 `test/unit/controller.test.ts` 6/6、TypeScript `tsc --noEmit`、Biome 检查与 diff whitespace 检查均通过。Playwright 启动的 `4173` 与 `9601` 回放进程已退出。
