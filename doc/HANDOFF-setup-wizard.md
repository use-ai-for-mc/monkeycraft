# MonkeyCraft 设置向导（Setup Wizard）· 跨会话交接文档

> 交接日期：2026-08-31 ｜ 来源会话：MonkeyCraft 面板视觉稿 + 向导设计（Ardot 画布会话）
> 用途：在新会话中恢复全部上下文，继续在原画布上补画向导视觉稿。

---

## 1. 已完成的工作（不要重做）

### 1.1 控制面板视觉稿（已完成并交付）

- **画布**：`https://ardot.tencent.com/file/720793256481329`（名称「MonkeyCraft 游戏内控制面板 · 视觉稿」），云端存在，实测 HTTP 200。
- **本地导出备份**：`/Users/cusgadmin/if-local/monkeycraft/exports/monkeycraft-panel/`，8 张 PNG：
  - 01-status-small / 02-status-pairing / 03-connect-small / 04-password-small / 05-access-small / 06-advanced-small / 07-status-large / 08-pairing-strip-zoom
- **画布关键节点 ID**：
  - `3:3` Status 小图 ｜ `3:45` 配对待处理条 ｜ `3:88` Connect ｜ `3:136` Password ｜ `3:191` Access ｜ `3:236` Advanced
  - `3:297` Large Status（1600×900 双栏）｜ `3:286` 配对条放大 ｜ `3:380` 旧界面截图
- **屏幕统一结构**：header（金色 MonkeyCraft + 状态点 + Enabled 复选框）→ 分隔线 → 5 tab（激活 tab 底 #313136 + #FFAA00 下划线）→ 滚动区 → footer（提示条 + Close）

### 1.2 工作流简化结论（已定）

1. Start 即总开关；Enabled 只管自动启动。
2. 主路径零输入：LAN 发现 + 配对条；密码/QR 退出主路径。
3. 日常使用可以不开面板：auto-start + 已配对即可。

---

## 2. 设置向导（Setup Wizard）视觉稿 —— ✅ 已完成（2026-08-31 晚，新会话交付）

**目标**：新用户三选一道路 → 选路后进该道路专属配置页 → 合流到连接手机页。向导只做「首次上手」，非默认/高级设置留在主面板 Advanced。

### 2.0 交付清单（不要重做）

- **画布**：同 `https://ardot.tencent.com/file/720793256481329`，向导分区在主面板右侧（x≈2902 起），5 屏横排。
- **节点 ID**：`4:1`/`4:2` 分区标题｜`4:3` P1｜`4:25` P2a｜`4:43` P2b｜`4:68` P2c｜`4:88` P3｜标注 `4:24` `4:42` `4:67` `4:87` `4:106`。
- **本地导出**：`exports/monkeycraft-wizard/`，5 张 PNG（01-p1-choose-path / 02-p2a-tailscale-login / 03-p2b-tailscale-vpn / 04-p2c-local-network / 05-p3-connect-phone，2×）。
- **§2.4 三问已拍板**：① 首次启动自动弹（写 wizardDone 后不再弹）② P2b 进页自动写 `tailscaleAccess=ALWAYS`，第 4 步自动勾选并标注 (set automatically) ③ Finish 不强制手机已连上，P3 右钮为 Skip for now。
- **骨架沿用 imf WizardScreen**：header 40 + footer 40（GUI）+ 三按钮 80×20（Back 左 / Next 中 / Close 右；首页无 Back、末页 Next→Finish 且无 Close）。
- 可选未做项：大尺寸 P1（1920×1080 @ scale 1 放大示意）。

### 2.1 页面结构（已定稿）

```
P1  Choose how to connect
├─ P2a  Tailscale login        （出门也支持，推荐）
├─ P2b  Tailscale VPN          （电脑手机都装 Tailscale，直接 IP 连）
└─ P2c  Local network only     （用户可自行加 funnel/tunnel/ngrok）
        ↓ 三路合流
P3  Connect your phone          （Finish；可 Skip）
```

### 2.2 各页规格

**P1 — Choose how to connect**
- 标题 + 一句副文案（说明选一条路，之后可在 Advanced 里改）。
- 三个 vanilla Button（纵向大按钮或三选一列表），每条道路一行：名称 + 一行说明。
- 推荐标注：P2a 带 "Recommended"（#55FF55 或金色标注）。
- 底部 `< Back`（P1 无）/ `Next >`（未选路时置灰）/ `Close`。

**P2a — Tailscale login（embedded Tailscale）**
- 只做 login 流：说明 → 一个 "Log in to Tailscale" 主按钮 → 等待状态文案。
- 成功后自动进入 P3。
- **写入配置**：`embeddedTailscaleEnabled=true`。

**P2b — Tailscale VPN（System Tailscale）**
- 四步清单（复选框样式）：
  1. Install Tailscale on this computer
  2. Install Tailscale on your phone
  3. Log in with the same account on both
  4. Allow MonkeyCraft through Tailscale（配一个按钮打开授权，见待拍板②）
- **写入配置**：`tailscaleAccess=ALWAYS`。
- 铁律：此页绝不出现 login 流内容（与 P2a 严格分离）。

**P2c — Local network only**
- Start 按钮说明 + 显示电脑的局域网地址（`http://<ip>:<port>` 形态，Copy 按钮 46×20）。
- 一行提示：出门在外需要远程？可自行配置 Tailscale funnel / cloudflare tunnel / ngrok（Advanced 里有更多）。
- **写入配置**：`networkScope=LOCAL_NETWORK`。

**P3 — Connect your phone（合流页）**
- 三路合流后统一页面：手机侧动作说明（打开 app → 发现/输入地址 → 输入配对码或点配对条）。
- **绝不出现**：密码全文、QR、端口设置、命令表（这些留在主面板 Password/Advanced）。
- Finish 主按钮 + "Skip for now" 次按钮（Finish 不强制手机已连上，见待拍板③）。

### 2.3 向导铁律（不可违反）

1. 每条道路只见自己的配置，互不掺杂。
2. 密码 / QR / 端口 / 命令表全程不进向导。
3. 向导只写 4 个配置项：`enabled` + `embeddedTailscaleEnabled`（P2a）+ `tailscaleAccess=ALWAYS`（P2b）+ `networkScope=LOCAL_NETWORK`（P2c）。

### 2.4 待用户拍板的三个问题（新会话开场先问）

1. **入口方式**：首次启动自动弹向导 vs 主面板只放 "Set up MonkeyCraft" 按钮？（AI 倾向：按钮，避免打扰老手）
2. **P2b 第 4 步**：自动写 `tailscaleAccess=ALWAYS` vs 给按钮让用户自己点？（AI 倾向：给按钮，用户知情）
3. **Finish 门槛**：是否要求手机已连上才能 Finish？（AI 倾向：不强制，可 Skip）

---

## 3. 平台硬约束（MC 26.2 / Fabric / Java 25）

- 入口：`/monkey`、`/monkey config`、Mod Menu 三入口；Screen 子类。
- 渲染入口：`extractRenderState(GuiGraphicsExtractor, int, int, float)`；GuiGraphics 仅 fill / text / centeredText / blit / textWithWordWrap / enableScissor / outline。
- **只能用 vanilla 控件**：Button / EditBox / Checkbox / CycleButton；弹窗用 vanilla ConfirmScreen（肯定左、取消右）。
- 尺寸适配：GUI scale 2 小窗（854×480 ≈ 427×240 GUI 单位）到 1920×1080 @ scale 1。
- 基线：~420 GUI 宽单列、行高 20、单列滚动、各 tab 记忆滚动位置。
- 鉴权模型：HMAC + 长期密码；配对 = 密码下发（仅 loopback / LAN / CGNAT 100.64.0.0/10 可配对）。
- 嵌入式 Tailscale（embedded helper）与系统 Tailscale（System Tailscale / CGNAT）严格分离，UI 不得混谈。
- UI 文案英文、与代码原型逐字一致；画布中文仅用于标注。

## 4. 视觉规范速查

- 色板（vanilla）：#55FF55 绿 / #FFAA00 金 / #FFFF55 黄 / #FF5555 红 / #55FFFF 青 / #AAAAAA 灰字 / #555555 深灰 / #FFFFFF 白；tab 激活底 #313136。
- 控件高 20 GUI；单一字号 9 GUI，层级靠颜色不靠字号；Copy 按钮 46×20；QR 64×64 白底；footer 提示条约 6 秒；Copied! 翻转约 7 秒。
- 画布字体：Pixelify Sans（模拟 MC 像素字）+ Sarasa Gothic SC（中文标注）。

## 5. 参考文件

| 文件 | 用途 |
|---|---|
| `mods/26.2/.../ui/MonkeyPanelScreen.java` | 主面板文案与交互的准确参考（逐字） |
| `~/if-local/imf/src/main/java/com/chenweikeng/imf/nra/wizard/WizardScreen.java` | 向导骨架：暗色全屏 + 居中标题 + footer 三按钮 |
| `~/if-local/imf/.../wizard/WizardPage.java` | 页面抽象 + `readyToGoNext()` 门控；末页 Next 变 Finish |
| `~/if-local/imf/.../wizard/TutorialPages.java` | TextBlock / RowBlock / SeparatorBlock 内容块模式 |
| `~/if-local/imf/.../wizard/pages/Page1AlertSettings.java` | 单页布局实例 |
| `exports/monkeycraft-panel/*.png` | 主面板已完成视觉稿（风格基准） |

注意：MC 26.2 下 imf 的向导骨架需适配 `extractRenderState`（imf 用的是旧版 render API）。

## 6. 画布操作经验教训（前会话踩过的坑）

1. `batch_edit` 整批大插入容易解析失败回滚 → **拆成多条小批次**（每批 ≤ 5~8 个节点）。
2. frame 内子节点坐标是**相对 frame** 的；散落到根层级的节点要用 M() 移入 frame 并改写相对坐标。
3. 注意图层顺序：QR/浮层不能压 footer；插入后截图验证。
4. 截图验证用 `capture_screenshot`（只传节点 ID，不传 screenShotDir），下载后用 Read 看图。
5. 新会话若画布工具正常：**优先打开已有画布** `https://ardot.tencent.com/file/720793256481329`，在右侧空白区新建「Setup Wizard」分区块；若系统强制 create_design 新文件，则新建画布并复制视觉规范，不要试图重建旧面板内容。

## 7. 新会话执行步骤建议

1. 读本文档 + `MonkeyPanelScreen.java`（文案基准）。
2. 先向用户确认 §2.4 三个待拍板问题。
3. 打开已有画布，新建向导分区块（建议 5 屏横排：P1 / P2a / P2b / P2c / P3，小尺寸 427×240 基线为主，可加一张大尺寸 P1）。
4. 按 §2.2 规格逐屏绘制，控件/文案遵循 §3、§4。
5. 每屏画完截图自查；全部完成后导出 PNG 到 `exports/monkeycraft-wizard/` 并交付。
