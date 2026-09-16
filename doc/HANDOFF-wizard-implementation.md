# MonkeyCraft 设置向导 · 交接文档（设计定稿 + 实施参考）

> 交接日期：2026-08-31 晚 ｜ 来源：向导视觉稿会话（Ardot 画布 + 26.2 参考实现）
> 用途：为继续开发 / 集成 / 移植设置向导的 AI agent 提供完整上下文。

---

## ⚠️ 阅读前必读（本次交接的边界）

1. **§1–§4 是版本无关的设计定稿**：三个决策、三条铁律、五屏逐字文案与布局。这些不依赖任何 MC 版本，可直接作为实施依据。
2. **§5–§6 是 mods/26.2 树上的一份"参考实现"**：本会话已写入但**未提交**，仅 `./gradlew build` 编译通过，**未做游戏内人工验收**。
3. **仓库有其他改动并行进行中**。26.2 的参考实现可能与并行改动冲突。是否保留、合并或整体回退该参考实现，**由你（接手的 agent）与用户确认后决定**，不要默认它就是最终集成路径。
4. **本次交接未触碰 26.1 / 1.21.11 / 1.19 三棵树**（只做了目录勘察，无任何写入）。跨版本移植方案由接手 agent 统一规划。
5. 视觉稿（画布 + PNG）是确定交付物，勿重画。

---

## 1. 已完成的交付物（不要重做）

### 1.1 视觉稿（定稿）

- **画布**：`https://ardot.tencent.com/file/720793256481329`（向导分区在主面板右侧 x≈2902 起，5 屏横排）
- **节点 ID**：`4:3` P1｜`4:25` P2a｜`4:43` P2b｜`4:68` P2c｜`4:88` P3（标注 `4:24` `4:42` `4:67` `4:87` `4:106`）
- **导出 PNG**：`exports/monkeycraft-wizard/01-p1-choose-path.png` … `05-p3-connect-phone.png`（2× = 854×480，对应 427×240 GUI 基线）
- 设计层面更早的交接：`doc/HANDOFF-setup-wizard.md`（本文件是其续篇，聚焦实施）

---

## 2. 已拍板的三个决策（不可回退）

1. **入口**：首次启动自动弹出（`wizardDone=false` 时）；写 `wizardDone=true` 后不再自动弹；主面板 Advanced 与 `/monkey setup` 命令可重进。
2. **P2b 第 4 步**：进入页面即自动写 `tailscaleAccess=ALWAYS`，第 4 步显示已勾选 + 灰字 `(set automatically)`，**不可交互**（手绘复选框，非 vanilla Checkbox）。
3. **Finish 门槛**：不强制手机已连上。P3 底部为 `Finish`（中）+ `Skip for now`（右），两者都写 `wizardDone=true` 并关闭。

## 3. 向导铁律（不可违反）

1. 每条道路只见自己的配置，互不掺杂（P2a 绝不出现系统 Tailscale 内容，P2b 绝不出现 login 流）。
2. 密码 / QR / 端口设置 / 命令表全程不进向导（留在主面板 Password / Advanced）。
3. 向导只写 4 个配置项：`enabled=true`（P1 Next 时）+ `embeddedTailscaleEnabled=true`（进 P2a）+ `tailscaleAccess=ALWAYS`（进 P2b）+ `networkScope=LOCAL_NETWORK`（进 P2c），外加完成标记 `wizardDone=true`（Finish/Skip 时）。

---

## 4. 五屏规格（版本无关 · 文案逐字 + 布局，GUI 单位，427×240 基线）

统一骨架（沿用 imf `WizardScreen` 惯例）：暗底 `0xF0000000`；header 高 40（黑底 `0xDD000000` + 底部分隔线 + 居中白标题）；footer 高 40（同底 + 顶部分隔线）；三按钮 80×20：Back 左（x=20）/ Next 中（居中）/ Close 右（x=右-80）。首页无 Back；末页 Next→Finish 且右侧变 Skip for now。内容列 x=20，行高 20，字号 9。

> 布局数值是 427×240 基线的比例参考，各版本按各自 GUI 缩放换算即可；文案为逐字定稿，不得改动。

### P1 · Choose how to connect（标题 "MonkeyCraft setup"）

- y52 白：`Choose how to connect`
- y64 灰：`Pick one path. You can change it later in Advanced.`
- 三个全宽大按钮 y80 / y116 / y152：
  1. `Log in to Tailscale (built in)`；y104 说明：绿 `Recommended` + 灰 `— sign in once; works at home and away.`
  2. `Use Tailscale VPN on both devices`；y140 灰：`You already run Tailscale. Connect by IP — no login in MonkeyCraft.`
  3. `Local network only`；y176 灰：`Same Wi-Fi as this computer. Simplest, but home only.`
- 选中道路在按钮左缘画 2px 绿色竖条；未选路时 Next 置灰。

### P2a · Tailscale login（标题 "Tailscale login"）

- y52 白：`MonkeyCraft runs a small built-in Tailscale node on this computer.`
- y66 灰（自动换行）：`Sign in once. Your phone can then find this computer from anywhere — at home or away.`
- 初始：`Log in to Tailscale` 主按钮（150×20，y92）。点击 → 起服务器（若未跑，9600–9700 端口回退）→ 启动内嵌 tailscale helper。
- 等待中：y96 青 `Starting the built-in Tailscale...`；`NEEDS_LOGIN` 且有 authUrl 后：y96 青 `Waiting for login — finish signing in in the browser window.` + y112 两按钮 `Copy login URL`（112 宽，复制后闪 `Copied!` 1.4s）/ `Open login page`（112 宽，经确认弹窗后打开系统浏览器）；y140 灰 `This page moves on automatically once you're signed in.`
- helper 出错：红字换行显示（错误码→人话映射与主面板 Connect tab 一致）。
- **Next 恒置灰**（前进全靠自动）；helper snapshot `listening=true` 时自动进 P3（约每 0.5s 轮询）。
- 进入本页写 `embeddedTailscaleEnabled=true`。

### P2b · Tailscale VPN（标题 "Tailscale VPN"）

- y52 灰：`Both devices use the Tailscale app. Check each step when done.`
- 四步清单 y70 / y92 / y114 / y140（行高 20）：
  1–3. 普通复选框（可勾）：`Install Tailscale on this computer` / `Install Tailscale on your phone` / `Log in with the same account on both`
  4. **手绘复选框**（12×12 黑底灰框 + 绿色像素勾），不可点击：白 `MonkeyCraft is allowed through Tailscale` + 灰 `(set automatically)`
- y166 灰：`Next unlocks when the first three steps are checked.`
- 1–3 全勾后 Next 激活。进入本页写 `tailscaleAccess=ALWAYS`。

### P2c · Local network only（标题 "Local network only"）

- y52 白：`Start the server. Phones on the same Wi-Fi can find this computer.`
- y70 状态行（4×4 色点 + 文字）：运行中绿 `Running · port <实际端口>`；启动中青 `Starting...`；失败红 `Could not start the server (no free port 9600-9700).`
- y92 灰 `Address on this network`；y104 白 `http://<ip>:<port>`（局域网地址取首个，截宽适配）+ 右侧 `Copy` 按钮 46×20（闪 Copied!）。
- y128 灰（换行）：`Away from home? You can set up Tailscale funnel, a tunnel, or ngrok later — see Advanced.`
- 进入本页写 `networkScope=LOCAL_NETWORK` 并自动起服务器（若未跑）。Next 恒可用。

### P3 · Connect your phone（标题 "Connect your phone"，三路合流）

- y50 状态行（点色随状态）：绿 `Waiting for phone · port <N>` / 绿 `Phone connected · port <N>` / 金 `Server not running`（约每 0.5s 刷新）
- y72 / y86 / y100 白：`1. Open MonkeyCraft on your phone.` / `2. Pick this computer from the list, or type its address.` / `3. Tap Pair on the phone, then choose Allow this phone here.`
- y122 起两段灰（自动换行）：`The pairing request pops up right here in game — no passwords to type.` / `You can finish now and pair later. This status also shows on the Status tab.`
- 底部：`< Back`（回所选道路页）/ `Finish`（中，写 wizardDone）/ `Skip for now`（右，同样写 wizardDone）。

---

## 5. mods/26.2 参考实现（未提交，去留由接手 agent 决定）

### 5.1 改动清单与 git 状态（回退风险提示）

| 文件 | 改动 | git 状态 | 回退方式 |
|---|---|---|---|
| `ui/SetupWizardScreen.java` | **新增**。五页向导完整实现：vanilla Button/Checkbox + `extractRenderState`，无注释、spotless 格式 | 未跟踪（`??`） | 可整体删除，零风险 |
| `config/ModConfig.java` | 新增 `wizardDone` 字段 + `isWizardDone()/setWizardDone()`（Gson 自动持久化） | **混合改动（`M`）** | 只能删 wizardDiff 相关行，勿 `git checkout` 整文件——会连带丢掉并行改动 |
| `MonkeycraftClient.java` | ① `CLIENT_STARTED`：`!wizardDone` 时标题屏自动弹向导 ② 新命令 `/monkey setup` ③ `openSetupWizard()` 静态方法 | **混合改动（`M`）** | 同上，行级摘除；该文件同时含并行 agent 的改动 |
| `ui/MonkeyPanelScreen.java` | Advanced tab 顶部新增 "First-time setup" 区块 + `Run setup wizard` 按钮（重入口） | 未跟踪（`??`），但文件本体是先前主面板工作的产物，非本次新建 | 只摘 "First-time setup" 区块，勿删整个文件 |
| `AGENTS.md` | Key Files 表补两行 UI 文件 | 混合改动（`M`） | 文档行，可留可删 |

> 并行改动涉及所有四棵树的 `MonkeycraftClient.java`、`WebSocketServerHandler.java`、`AuthenticationHandler.java` 等以及 flutter 端大量文件——**任何回退操作前先 `git status` + `git diff` 核对，禁止整文件 checkout**。

### 5.2 构建验证

`cd mods/26.2 && JAVA_HOME=/opt/homebrew/Cellar/openjdk/25.0.2/libexec/openjdk.jdk/Contents/Home ./gradlew build`（Java 25）——**通过（含测试）**。游戏内人工验收未做。

### 5.3 26.2 平台要点（仅适用于该树）

- 渲染入口是 `extractRenderState(GuiGraphicsExtractor, int, int, float)`（旧 `render(GuiGraphics,...)` 已废弃）。可用绘制仅：`fill` / `text` / `centeredText` / `textWithWordWrap` / `blit` / `enableScissor`（已用 javap 对着 loom-cache 的 mapped jar 逐一验证）。
- 只用 vanilla 控件：`Button.builder(...).bounds(...)` / `Checkbox.builder(...).pos(...).maxWidth(...).selected(...).onValueChange(...)`；打开 URL 用 `ConfirmLinkScreen.confirmLinkNow(screen, url, true)`。
- 屏幕切换用 `minecraft.setScreenAndShow(...)`；页内刷新用 `rebuildWidgets()`（注意会触发 `init()` 重放，paintSteps 要先 clear）。
- MC 内部类名不要信网上资料，先查 `mods/26.2/.gradle/loom-cache/` 里的 mapped jar（`unzip` + `javap`）。

### 5.4 参考实现用到的现成 API（26.2 树内）

| API | 用途 |
|---|---|
| `ModConfig.getInstance()` / `.save()` | 配置读写（单例，Gson 存 `config/monkeycraft.json`） |
| `MonkeycraftClient.startServerWithPortRange(port)` | 起服务器（9600–9700 回退，返回实际端口，≤0 为失败） |
| `WebSocketServerHandler.getInstance()` | `isRunning()` / `isClientConnected()` / `getCurrentPort()` |
| `HelperTailscaleService.get()` | `ensureRunning(port)` / `status()`（返回 `TailscaleSnapshot`：state/authUrl/listening/errorCode...） |
| `HelperMessage.STATE_NEEDS_LOGIN` 等常量 | 状态判断 |
| `NetworkUtils.getLocalIpAddressesWithPort(port)` | `List<String>`，形如 `192.168.0.10:9600` |
| `MonkeyPanelScreen` 的 `humanError(TailscaleSnapshot)` | 错误码→人话文案（向导里复制了一份私有版本） |

---

## 6. 跨版本移植注意（勘察结论，未动手）

四棵树并行（26.2 / 26.1 / 1.21.11 / 1.19），**差异比"同 API 换签名"大**：

- **26.1**：无 `MonkeyPanelScreen`、无 `tailscale` 包——整体落后于 26.2，向导依赖的 helper/面板体系尚缺，不是简单拷文件。
- **1.21.11 / 1.19**：旧渲染 API（`render(GuiGraphics)` 直绘），骨架写法参考 imf：`~/if-local/imf/src/main/java/com/chenweikeng/imf/nra/wizard/`。
- 建议：先与用户确认各树的追赶计划（是否等 26.2 功能全量下放），再决定移植顺序与策略。**本次未做任何跨树写入。**

## 7. 剩余工作清单（按优先级，供接手 agent 规划）

1. **决定 26.2 参考实现去留**（结合并行改动）：保留 → 游戏内人工验收五页流程；回退 → 参考实现仍可作为对照样板。
2. **游戏内人工验收**（若保留）：首次弹窗、三路各自配置写入、P2a 自动前进、P2b 门控、P2c 地址/Copy、P3 状态刷新与 Finish/Skip。
3. **跨版本移植**：见 §6。
4. **打磨点**（可选）：
   - P1 大按钮在超宽屏（1920×1080 @scale1）下的观感（span 全宽可能过长，可封顶 ~400 GUI）。
   - P2a `Open login page` 切出浏览器后回来，屏幕状态是否正确恢复。
   - 配对请求弹出（ConfirmScreen）与向导 P3 同屏时的层叠关系。
   - 首次弹向导时用户直接 ESC 关闭：不写 wizardDone，下次启动还会弹（符合"未完成"语义，确认是否合意）。

## 8. 相关文件路径速查

- 视觉稿导出：`exports/monkeycraft-wizard/01–05*.png`；主面板导出：`exports/monkeycraft-panel/`
- 设计交接（视觉稿层面）：`doc/HANDOFF-setup-wizard.md`
- 向导骨架参考：`~/if-local/imf/src/main/java/com/chenweikeng/imf/nra/wizard/`（imf 用旧渲染 API）
- 画布：`https://ardot.tencent.com/file/720793256481329`
