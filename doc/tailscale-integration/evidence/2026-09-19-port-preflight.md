# P3 Mod 版本移植前检查（只读）

日期：2026-09-19。本文只比较当前主 checkout 中的四个 Mod 树和路线文档；没有改动任何 `mods/` 源码、资源或构建脚本，也没有运行构建。P3 仍以 26.2 的最终可运行产物稳定为前提，本文不是把当前 26.2 工作区修改视为已经在其余版本验收通过。

## 结论与执行顺序

26.2 是目前唯一具备浏览器静态资源同端口服务、Tailnet HTTPS 入口探测和内嵌 helper 接线的树。26.1、1.21.11、1.19 三棵树均尚未包含这些功能。三者的基础 WebSocket、配对和配置迁移逻辑已存在，可以作为接入点；但不应以复制整个目录的方式移植。

在开始任一目标树前，应冻结经过 26.2 集成验证的源文件和 helper/Web 构建输入，记录其产物哈希与测试结果。建议严格按 26.1、1.21.11、1.19 的顺序逐树完成、单独构建和运行验证；前一树未完成时不并行扩散问题。26.1 与 26.2 同为 Java 25，适合作为第一站，但它仍有不同的 Minecraft API 和旧配置 UI，不能认为是无适配复制。

## 当前能力矩阵

| Mod 树 | Java / 映射与构建基线 | 同端口 HTTP 静态网页 | Tailnet HTTPS 探测 | 内嵌 helper | 直接移植风险 |
|---|---|---:|---:|---:|---|
| `mods/26.2` | Java 25；当前参考实现 | 有 | 有 | 有 | 仍须以最终集成结果冻结 |
| `mods/26.1` | Java 25；未映射的当前版本构建配置 | 无 | 无 | 无 | 低于旧版目标，但 UI 与 Minecraft 成员访问不同 |
| `mods/1.21.11` | Java 21；Fabric Loom remap、官方 Mojang mappings | 无 | 无 | 无 | 映射名、渲染/GUI accessor 和 Java 目标都不同 |
| `mods/1.19` | Java 17；旧 Fabric Loom、Yarn mappings | 无 | 无 | 无 | 最大：命令、屏幕、Mixin、依赖和映射代际均不同 |

路线文档要求每个版本先检查本地反编译 Minecraft 代码，不以网上类名或签名决定适配；这一步尤其适用于窗口、GUI 和屏幕相关 Mixin。

## 需要同步的 26.2 工作面

下表列出当前 26.2 工作区中与 P3 相关的准确文件集合。它是移植清单，不是“全部直接复制”清单。

| 工作面 | 26.2 参考文件 / 资源 | 目标树应做的事 | 是否可直接复用 |
|---|---|---|---|
| helper 生命周期、命令与配置 | `MonkeycraftClient.java`、`config/ModConfig.java`、`tailscale/HelperTailscaleService.java`、`tailscale/NativeHelperExtractor.java`、`tailscale/TailscaleSnapshot.java` | 增加显式开关、启动/停止生命周期、`/monkey tailscale` 子命令和状态读取；保留默认关闭与既有配置迁移 | helper 三个纯 Java 类需先以目标 JDK 编译；入口代码按目标 API 手工合入 |
| helper 资源和发行校验 | `build.gradle`、`build-and-deploy.sh`，以及由 `native/tailscale-helper` 生成的四平台 helper、manifest、SHA 和许可证 | 为每棵树加入同等的资源复制和 `processResources` 前完整性校验；发布脚本先生成 `web/dist` 与 helper | 构建意图可复用；Gradle 文件和部署脚本必须按目标树改写 |
| 同端口 Web 服务 | `server/HttpAwareWebSocketServerFactory.java`、`server/HttpOrWebSocketChannel.java`、`server/WebAssetServer.java`、`server/WebSocketServerHandler.java` | 在现有 WebSocket 服务工厂/启动路径中接入 HTTP 识别、GET/HEAD、资源读取、关闭顺序和端口占用检查 | 网络层Java实现大部分可复用；先与目标树的Java-WebSocket工厂和依赖版本逐项比对 |
| 浏览器发行资源 | `build.gradle` 的 `web/dist` 打包规则 | 在生成 JAR 后检查包含 `web/index.html` 及构建输出；缺失时构建失败 | 资源内容可共享，资源任务和路径解析按目标 Gradle 配置适配 |
| 系统 Tailscale HTTPS 入口 | `utils/TailnetHttps.java`、`ui/MonkeyPanelScreen.java` | 只展示与当前 Mod 端口严格匹配的现有 Serve HTTPS 入口；不创建或改写 Serve/Funnel | `TailnetHttps` 本身为 Java 17 可用代码，UI 调用点不可直接复制 |
| 设置、向导与状态展示 | `ui/MonkeyPanelScreen.java`、`ui/SetupWizardScreen.java`、`ui/HomeCopy.java` | 将开关、登录、登出、状态和 HTTPS 入口放入各版本原有配置入口；定义首启向导迁移行为 | 不可直接复制：三个目标树只有 `ConfigScreenFactory`，没有 26.2 的独立 panel/wizard 类 |
| 窗口与 GUI 行为 | `mixin/WindowMixin.java`、`mixin/GuiMixin.java`、`monkeycraft.mixins.json` | 先在每个目标的本地反编译 jar 中确认目标类、字段、方法描述符和注入点，再决定是否需要等价 Mixin | 不可直接复制 |
| 回归测试 | `server/HttpAndWebSocketPortTest.java`、`server/WebAssetServerTest.java`、`server/WebSocketServerShutdownTest.java`、`tailscale/HelperTailscaleServiceTest.java`、`tailscale/NativeHelperExtractorTest.java`、`utils/TailnetHttpsTest.java`、`src/test/resources/tailscale-test-helper.bin` | 连同生产代码移入，并保留假 helper，不进行真实登录或创建身份 | 纯 Java 测试可优先尝试复用；涉及 Minecraft 初始化和端口的测试按目标环境修正 |
| 路线、架构和验收文档 | `doc/PRODUCT_ROADMAP_2026-09.md`、`doc/PRODUCT_ROADMAP_EXECUTION.md`、`doc/FLUTTER_CLIENT.md`（协议变更时） | 每树完成后更新实际能力、构建命令、JAR 内容检查和运行证据；未验证不要标为支持 | 文本框架可复用，结果必须逐版本记录 |

## 已确认不能整块复制的内容

1. **Gradle 与部署脚本。** 26.2 的 `build.gradle` 已有 helper manifest/hash/protocol/platform/license 校验和 `web/dist` 复制规则，其他三棵树只有普通 `fabric.mod.json` 资源展开。26.1 是同 Java 版本但项目配置独立；1.21.11 使用 remap 和官方 mappings；1.19 使用 Yarn 与旧 Fabric Loom。应将“先生成输入、再校验、再打包”的行为逐项移植，不覆盖目标的插件、映射、依赖和 Java 配置。
2. **`fabric.mod.json` 与 Mixin JSON。** 1.19 声明 `fabric` 依赖，较新三树为 `fabric-api`；兼容级别分别为 Java 25、21、17。26.2 的 `WindowMixin` 和 `GuiMixin` 目前不在三个目标树的 Mixin 列表中；1.21.11 反而已有 `GameRendererAccessor`、`GuiRendererAccessor`。不能原样覆盖资源文件。
3. **26.2 的设置面板和首次向导。** 三个目标树的 `/monkey config` 仍调 `ConfigScreenFactory`，且没有 `MonkeyPanelScreen`、`SetupWizardScreen`、`PanelScrollArea` 或 `HomeCopy`。应先决定在现有配置屏中增加独立 Tailscale 页面/控件，或为目标版本分别实现相应 UI；不能把 26.2 的屏幕类连同 Minecraft GUI 调用直接粘贴。
4. **Minecraft 客户端调用与 Mixin。** 26.2 的客户端代码使用其版本的 `client.gui.screen()`、`client.gui.setScreen(...)` 等成员；26.1、1.21.11 的当前代码使用 `client.screen`、`client.setScreen(...)`，1.19 的命令回调还通过 `pendingScreen` 延迟打开屏幕。应基于目标版本本地反编译结果和现有目标源文件调整。
5. **端口和关闭改动的假设。** 26.2 当前工作区还有 IPv4 `StandardProtocolFamily.INET` 端口检查、HTTP/WebSocket 共端口和 helper 异步停止修复。它们必须先以 26.2 最终测试结论为准；目标树移植时保留各自服务器启动/关闭语义，并以目标端口测试验证，不能只套用差异块。

## 各版本适配风险与前置核对

### 26.1

- Java 25 减少 helper 类语言与标准库风险；`record`、`ProcessHandle`、`Files.readString` 等参考代码均可用。
- `MonkeycraftClient` 的屏幕成员访问与 26.2 已不同，当前仍从 `ConfigScreenFactory` 打开配置。先做生命周期、命令、配置和服务层，再单独做 UI。
- Mixin JSON 与 26.2 相近但没有 `WindowMixin`/`GuiMixin`。对每个新增 Mixin 先查本地 26.1 反编译类和方法描述符。
- 第一轮只应证明 helper、HTTP/Web、WebSocket、既有配对共存；再测试实际游戏内面板和输入。

### 1.21.11

- 构建采用 Java 21、remap 和官方 Mojang mappings。不得从 Java 25 目标复制 toolchain 或无映射依赖声明。
- 已存在 `GameRendererAccessor` 和 `GuiRendererAccessor`，说明图形访问路径与 26.x 不同。新增窗口/GUI 行为要先确认现有 accessor 是否已能承载需求，避免重复注入。
- helper 实现使用的 Java 标准库 API 可在 Java 21 使用；仍需对编译、线程、资源提取和进程清理进行独立测试。

### 1.19

- Java17是最低语言/库上限。已有明确不兼容点：`NativeHelperExtractor`使用`Thread.currentThread().threadId()`，Java17移植时须改用兼容方式（如`getId()`或不依赖线程ID的临时文件创建）；不能直接复制后宣称标准库完全兼容。`record`、`ProcessHandle`、`Files.readString`和`InputStream.readAllBytes`本身可用。
- 使用 Yarn mappings、Fabric Loader 0.14.22 和旧 Fabric Loom，客户端命令使用 `ClientCommandManager`，设置屏幕通过 `pendingScreen` 在 tick 中打开。这些调用点必须保留该版本的时序。
- 缺少 `NativeImageAccessor`，且 1.19 的 Mixin 集合最小。窗口/GUI Mixin 需要在本地 1.19 反编译 jar 中重新定位，不保证存在等价类或签名。
- 该树应最后移植，并在接口无法保持时明确给出降级行为，不以编译替代游戏内验证。

## 每棵树的实施与验收清单

1. 记录已冻结的 26.2 参考文件、Web 产物和四平台 helper manifest/hash；确认目标树没有待保护的用户修改。
2. 对目标 Minecraft 版本的本地反编译 jar 核对所有新增/修改的 Minecraft 类、字段、方法和 Mixin 描述符；把结论写入该树的证据记录。
3. 先移植不依赖 GUI 的 helper、资源校验、HTTP/WebSocket 分流和 `TailnetHttps`，再合入生命周期与命令。默认保持 embedded helper 关闭，不读取、复制或删除已有身份。
4. 在目标既有配置流中实现开关和状态；首启向导/独立面板只有在该版本 API 已本地核实后才添加。
5. 迁入假 helper 和单元/集成测试，确认资源 JAR 包含 `web/index.html`、四平台 helper、manifest、SHA 与许可证；测试不可触发真实账户登录。
6. 使用该树规定的 JDK 单独运行格式化和构建，再在对应 PrismLauncher 实例验证启动、端口竞争、HTTP GET/HEAD、WebSocket 配对、helper start/stop 与关闭。实际 Tailscale 授权、身份持久化和跨设备连接应另列人工验收，不能由构建结论替代。
7. 仅在该树所有结果齐备后更新路线执行矩阵，标注版本、命令、产物哈希和未覆盖场景；然后才开始下一棵树。

## 本次只读证据边界

- 当前执行记录将 P3 标为“等待 26.2 完成首轮集成再移植”；本检查没有改变该优先级。
- 未运行 Gradle、未部署任何 JAR、未接触 Tailscale 登录状态或身份目录。
- 26.2 工作区同时含有用户/其他任务的进行中修改。上述文件清单用于下一阶段人工挑选和逐项比对，不表示可以直接纳入或覆盖其他树。
