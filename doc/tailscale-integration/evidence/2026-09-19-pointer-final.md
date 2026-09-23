# 2026-09-19 最终 PointerLock 修复与恢复验收

本文的实例状态与“未启动”表格为当时快照。后续用户已开启26.1会话控制，当前四包均已实际运行；26.1完成十分钟，另外两版完成最新包短测。截图复核还发现旧live用例可能将暂停菜单误判为背包；该测试已加强，四版本重新运行并逐张确认真实背包。最新结果见[26.1运行证据](2026-09-19-26-1-runtime.md)、[1.21.11运行证据](2026-09-19-1-21-11-runtime.md)、[1.19运行证据](2026-09-19-1-19-runtime.md)及[执行记录](../../PRODUCT_ROADMAP_EXECUTION.md)。原十分钟视频证据不受此背包判定问题影响。

## 改动与浏览器结果

`PointerController` 现在捕获同步异常和 Promise 拒绝，每个请求在调用前监听成功/失败，并在完成时清理。请求未完成时不重复申请；迟到锁定按生命周期代次、连接与游戏界面状态释放。旧式 void 返回接口也走事件完成路径，断开后不会仅因移除普通输入监听而丢失清理。新增三个真实浏览器回归覆盖失败后拖动/重试、Promise 与 void 的迟到完成。

最终 TypeScript 与 Biome 通过。首次 Biome 只报告两文件格式差异，格式化后通过，原日志保留。正常 Web 与 Pages 构建通过；最终全套 Chromium 23 passed / 5 skipped，Playwright WebKit 22 passed / 6 skipped。160 项单元测试来自前一批次，本次只追加输入生命周期修复，未重复该套件。WebKit 不等于实体 Safari 或 iPhone。

Pages 本地 `/monkeycraft/` 专项：四个既有 spec 共 4 passed / 1 skipped，三个 PointerLock 用例 3 passed。首次命令未给测试进程传入 Pages 环境，额外跳过 Pages 页面用例；修正环境后完整重跑，保留两份日志。最终仅无头 Chromium 通知权限场景跳过。测试自启的 4191 / 9601 服务均已回收，未部署公开 Pages。

## 四版本包与失败记录

四树使用匹配的 JDK 串行构建，26.2 的 62 项、其余各 57 项 JUnit 均通过；成功日志的 test task 均实际执行。1.19 首轮增量 remapJar 报重复嵌入 Java-WebSocket；确认无仍运行的同树 Gradle / 日志写者后，仅对 1.19 clean build，21 秒、15 tasks 全执行通过。未修改依赖、跳过 nesting 或更改生产代码，初次失败日志保留。清理成功证明当时中间产物被重建，不据此断言已找到可重复的脚本缺陷根因。

每个 JAR 的 11 个 Web 文件、四平台 helper、manifest、摘要侧文件与许可证均逐字节核对；manifest hash/size 一致。清单见[最终产物](2026-09-19-pointer-final-artifacts.json)。

| Minecraft | 最终 JAR SHA-256 | 当前真实运行范围 |
|---|---|---|
| 26.2 | `2f6045c246f22e65f7a056dd4aba38e55d4f74e7ccaf465a923be26a27fefe03` | 新包真实 HTTPS/WSS 视频、背包开关通过；本包未重跑十分钟 |
| 26.1 | `2a48ef6a643a5582dbff651ebe9fdba13bbe852853d71ba09045f1a2ef9dcbef` | 本地部署，未启动；会话控制仍待用户授权 |
| 1.21.11 | `b927c80ffbab19a87ee648c7a3c3758eea9cf32919aacc942d825c6a044104a9` | 本地部署，最新包未启动；d42a65 的十分钟/最小化记录保留为前一包证据 |
| 1.19 | `e9df6d39e3ad9e2614550f4c717559a370857e2e58059f1926df20c6e8c843bc` | 本地部署，最新包未启动；dd3dd0 的十分钟本地世界记录保留为前一包证据 |

此次晚期变化只涉及浏览器输入清理，不改变视频编码/解码与 Java 运行逻辑。因此以两浏览器完整回归、Pages 专项和最终 26.2 实际视频/背包检查验证；不把旧哈希长测转写成新哈希结果。

## 26.2 恢复现场

常用 ImagineFun Add-Ons 已进入原 `mp.imaginefun.net`，游戏 PID 99472 / helper 99560。新包普通 live 为 1 passed / 1 skipped，跳过的是未请求的十分钟用例。结束后控制客户端和 Shift 均 false；helper running / listening，IP `100.82.132.32`、身份指纹 1148163683 保持不变，无需重新授权。既有电脑园区音频 active / connected 均 true；这不是手机可听验收。

部署只原子替换 MonkeyCraft JAR，旧包备份并校验，未编辑账户、网络配置或其它 Mod。26.2 的配置文件哈希与更早 preflight 不同；认证处理会更新 lastPhoneSeenAt 并保存，现场时间与配置 mtime 一致。更早只保存哈希，无法严格证明仅哪些字段改变，因此不写“26.2 配置字节不变”，也不为消除差异回滚运行时信息。1.21.11 / 1.19 长测前后配置哈希相同的独立记录仍有效。

原始证据在 `outputs/roadmap-2026-09-19-pointer-final/`：构建日志、web-results.json、local-deployments.json、restored-26.2.json、26.2-live.log、26.2-playwright/。

## 复现命令与边界

从 `web/` 使用现有本地 TypeScript、Biome、Vite 和 Playwright 工具执行 typecheck、lint、普通/Pages build；完整浏览器命令为 `node node_modules/@playwright/test/cli.js test --workers=1`，WebKit 设置 `PLAYWRIGHT_BROWSER=webkit`。Pages 使用同目录独立配置和 4191 端口。真实测试由 `MONKEYCRAFT_REUSE_DEV=1 MONKEYCRAFT_LIVE_URL=https://mac.tail977122.ts.net:8443/ node tools/run-live-test.ts` 读取本机密码，仅在进程内使用。主构建、完整浏览器与真实 live 命令显式选择 `/opt/homebrew/bin` 下 Node 26；最终 Pages 专项使用已有 PATH 的 NVM Node 22.22.3。

四树常规命令为 `./gradlew --no-daemon --max-workers=2 spotlessCheck build`；1.19 清理重建为 `./gradlew --no-daemon --max-workers=2 clean build`，Gradle 使用 JDK21，源码工具链使用 JDK17。外部门槛与最短人工步骤见[剩余验收](../REMAINING_ACCEPTANCE_STEPS.md)。
