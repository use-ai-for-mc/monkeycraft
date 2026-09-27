# 发布前剩余事项

更新时间：2026-09-27。按用户确认的范围，只把**本次 Tailscale 与新 Flutter 网页端的主要路径**作为功能验收对象。已经通过的 Safari、Android 内网和原生 App 功能不重复测试；不安排声音、通知、倒计时、锁屏、Windows/Linux 或四个 Minecraft 版本的排列测试。

## 已完成，不再要求用户操作

- Flutter Pages 已发布到 <https://use-ai-for-mc.github.io/monkeycraft/>。最新发布来源 `74ea3ab`，Pages 运行 [35948438290](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/35948438290) 成功；公开入口和 Tailscale 资源的 12 项哈希与来源清单一致。
- 实体 iPhone Safari 已通过公开 Pages 的 Tailscale 登录、选择电脑、配对、看到游戏画面以及刷新后自动回到游戏。后来发布的临时断线保持游戏页修复有 13 项定向测试和静态分析通过，但没有新的真机锁屏结果；按当前验收范围不追加手机操作。
- Android 实体手机的内网连接已由用户确认成功；PC 与 iPhone 原生内嵌 Tailscale 的主要连接此前已有真实双端证据。
- Pages 使用浏览器内嵌 Tailscale 访问用户自己的电脑，不要求 Funnel 或公网游戏入口。内置于 Mod 的根路径网页与 Pages 是不同产物；Pages 新增的 WASM 不需要复制进四个 Mod 才能发布浏览器版。

## 还需要做的发布决定与交付工作

1. **确定本次对外发布范围。** 若仅指 GitHub Pages 网页版，已上线且主要路径已验收，没有剩余人工功能测试。若还要发布新版 Mod JAR、Android APK 或 iOS App，需要确定发布渠道与版本号，再由代理从同一选定源码整理对应构建、来源、签名和发布说明。现有 `1.4.2` GitHub Release 早于九月的新改动，不能当作本轮产物。
2. **移动应用商店发布前修正公开材料。** [现行隐私政策](../PRIVACY_POLICY.md)以及历史 `1.4.1` App Review 文案称私有网络仅由用户在 App 外配置、MonkeyCraft 不提供 VPN 功能。新增原生内嵌 Tailscale 后，这些原文不能直接复用于新版商店提交。代理应先按实际实现拟定更新的隐私说明与审核答复，并核对加密声明；账号持有人最后在 App Store Connect / Play Console 确认申报并提交。历史 `1.4.1` 文档保留作历史记录。
3. **仅处理具体阻断。** 若打包或上线发现阻止启动、连接、游戏画面或控制的确定故障，修复并验证对应路径。其他已稳定功能不因版本或设备组合重新验收。

当前用户不必再操作手机。只有选定新的 Mod/App 发布范围，或商店账号内必须由账号持有人确认的事项，才需要用户介入。证据边界和各平台状态见[精简矩阵](TEST_MATRIX.md)、[Pages 说明](../GITHUB_PAGES.md)与[执行日志](../PRODUCT_ROADMAP_EXECUTION.md)。
