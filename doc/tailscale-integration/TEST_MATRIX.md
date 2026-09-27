# MonkeyCraft 精简发布矩阵

更新时间：2026-09-27。只按本次新增的 Tailscale / Flutter 网页主路径判断功能验收；次要功能及无实质变化的旧路径沿用此前结论。表内“已通过”区分本轮自动化、先前实机反馈和正式发布。

| 范围 | 证据与结论 | 本轮剩余 |
|---|---|---|
| Flutter GitHub Pages | [运行 35948438290](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/35948438290) 成功，公开 12 项入口/运行时资源哈希一致；正式 Pages 已上线 | 无功能验收 |
| Pages 浏览器内嵌 Tailscale | 真实 Chrome 登录及 26.2 游戏连接通过；用户确认实体 iPhone Safari 登录、配对、画面、刷新自动恢复 | 临时断线修复仅有定向自动化、未获更新后的真机锁屏反馈；按用户确定的精简范围，不追加人工测试 |
| 共享 Safari 旧功能 | 2026-09-23 用户已确认主要功能；见[真机记录](evidence/2026-09-23-iphone-safari.md) | 无；不重测声音/通知/倒计时 |
| iOS / Android 原生 App | 内嵌 Tailscale 主要路径已有实机证据；Android 内网连接已由用户确认；其他旧功能沿用既有结果 | 若新版上架，先修正隐私与审核材料并核对产物；不追加声音等功能测试 |
| 四个 Minecraft Mod | 既有构建和主要游戏路径通过；Pages WASM 是单独发布产物 | 若要发新版 JAR，从同一发布源码核对四个构建包；不逐版本重复手机验收 |
| Windows / Linux helper | 无新的具体联网回归依据，沿用既有结果 | 无 |

未测的范围不写成“实测通过”。iOS Safari 页面被系统回收后需要启动浏览器 Tailscale 节点，不能承诺与仅切换 App 后的健康连接同样快。原生 App 的后台能力与普通浏览器不同。发布范围、商店资料问题和下一步见[剩余事项](REMAINING_ACCEPTANCE_STEPS.md)。历史扩展矩阵仅供追溯：[2026-09-23 旧矩阵](evidence/2026-09-23-test-matrix-before-simplification.md)。
