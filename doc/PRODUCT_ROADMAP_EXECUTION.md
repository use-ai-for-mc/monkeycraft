# 产品路线执行记录

## 2026-09-21 自主收尾：最新状态

本轮源代码/最终包/真实运行的对应关系以 [自主收尾证据](tailscale-integration/evidence/2026-09-21-closeout.md) 为准。下面原有开头与日志包含前批次“最新/最终”字样，均作为历史保留，不覆盖本节。

- Flutter当前232项与analyze通过；Chrome28项；四版Mod66/61/61/61；helper Go/race、五平台构建及Java17/21/25 harness通过。Android正常Release与iOS clean签名设备包已归档，未装实体手机。
- 音频跨端抢占已用既有INFO API接通，并在真实26.2+iOS调试模拟器完成持有、断线不抢占、明确释放后恢复PC的服务级验证；配套ImagineMoreFun修改在独立现有checkout，详见证据。新Refresh失败清理由自动化验证。不是正常GUI/手机听感通过。
- 旧三版先补库存键真实回归，后又重建最终INFO/Web包；最终26.1/1.21.11已再跑60秒467/550新帧、零解码错误。用户提供`main.mcparks.us`并授权继续接管，最终1.19在MCParks通过七项核心回归，60秒487新帧、零错误；自动暂停测试前提单列。Android最终包从实际聊天链接连接MCParks，通过Home111.665秒、模拟器熄屏68.471秒、返回、单曲停止/Refresh/断开不复活，未声明真机听感。
- Pages99文件候选在普通archive副本通过232+28、analyze、Release、本地项目路径10项E2E；6项provenance测试通过。公开入口、真实系统通知及听感不由无头结果代替。本轮无commit/push/dispatch/deploy。
- 26.2曾因我过早复制构建中间JAR而缺API崩溃，已保存原包和失败日志；完整包8aaaf7核验并重启后恢复，真实音频回归通过。不是内存故障，详见证据。
- 人工待办已缩短为手机Safari恢复提示音、原生最终包音频/去重/计时两组；账户、设备、网络和发布权限门槛单列。见 [最短步骤](tailscale-integration/REMAINING_ACCEPTANCE_STEPS.md)。保留用户修改、主checkout，不占用物理手机。

## 历史批次概览与完整执行过程

开始：2026-09-18。路线依据：[PRODUCT_ROADMAP_2026-09.md](PRODUCT_ROADMAP_2026-09.md)。本文持续更新，未勾选的验收不表示完成。

当前范围：Flutter iOS、Android 与浏览器共用 UI/业务代码；独立 TypeScript `web/` 只保留参考与测试夹具。使用主 checkout，保护既有修改。旧授权提交 `ace51c9` 已在 origin/master，但没有发布其独立客户端；本轮新的73文件 Flutter Pages 候选尚未提交或发布，正等待共享 Dart 范围的明确授权。以下为重启后最新状态；旧批次与失败过程保留在后文。

最新浏览器：26.2最终包 `ee2dbc28…` 已完成真实Chrome提醒并发修复复测（原81ms被覆盖→修复后至少2634ms可见）、完整倒计时流程及120秒核心回归（969新帧/解码错误0）；真实Safari完成登录、resize、E/ESC、输入释放、计时更新取消到点，以及W3C鼠标Pointer Lock/ESC解锁。Safari真实前台声音调用计数8→静音8→有声9→重复9，用户听感待确认；后台系统通知尚未有效取证，不能因permission=granted就写通过。真实手机浏览器仍待验。

最新版本支持：26.1 `660d0a50…`、1.21.11 `0063d289…`、1.19 `52fa89f6…` 均已部署各自最终Flutter包并完成真实60秒核心回归，分别521、562、479新帧，错误0。1.19使用既有独立验收世界，未尝试绕过ImagineFun最低1.21要求。四树最终JAR各49个Web资源逐字节核对通过，26.2 Java66项、其余各61项通过。结束版本测试已恢复26.2原服、helper正常监听、按键释放和乘坐休眠原设置；随后Android模拟器短测仅在明确交接唯一控制权后进行。

最新音频进展：此前iPhone包的提醒/倒计时/游戏恢复已获本人确认，但园区音频回前台失败。按用户要求改用iOS26.5模拟器LAN直连真实26.2，已复现并通过单变量对照定位为No Sleep保活视频抢占；iOS专用兼容修复已在重新构建的模拟器App通过锁屏71秒/Home44秒返回及断开不复活。正常iPhone Release已clean构建并验证（Runner06c2a363…），尚未安装/真机复验，不能称真机音频全部通过。模拟器已显式断开并关闭，电脑音频已恢复active/connected且音量保持0。本轮依赖改变使以下73文件Pages候选只代表历史，正式发布前需重新核对。

此前自动化与候选：主checkout Flutter224项/analyze通过；73文件Pages候选在普通archive（非worktree）中逐文件SHA一致，204项VM/widget、24项Chrome、Release/完整性检查及本地 `/monkeycraft/` 录像夹具端到端通过。候选补丁SHA为 `a5b78800f921fee5d6a236af10f405066207717c2332537a8ecae3de753bdd66`。没有把无头权限仿真、录像或旧包十分钟结果算成新包真机验收。

此前原生构建与安装：iOS增量构建曾混入Simulator objective_c.framework，已标无效并保存；经既有clean设备构建入口重建后，所有嵌套平台/签名通过，有效Runner `369feb4e…`。AGENTS与根README构建入口已修正，避免再次误用普通增量build。物理iPhone已在用户解锁连接后恢复可达，最新有效设备包已覆盖安装并读回1.4.2(11)；正按用户要求逐项人工验收。Android Release `39218eaa…`（本地个人签名，非Play发行声明）通过双ABI/16KiB/签名后，已保留数据覆盖安装到Android16现有AVD，并真连26.2完成视频、静音系统通知、倒计时更新取消到点、输入释放、后台前台恢复及受控断线重连。模拟器已关闭；声音、锁屏/后台音频及Tailscale本人授权仍不能据此写成真机通过。

最新明细见[支持矩阵](tailscale-integration/TEST_MATRIX.md)、[Flutter真实运行证据](tailscale-integration/evidence/2026-09-19-flutter-live-26-2.md)与[剩余验收](tailscale-integration/REMAINING_ACCEPTANCE_STEPS.md)。公开Pages E2E、手机感知与音频、Android本人tailnet授权/系统VPN共存、旧版helper账户授权/跨设备及Windows/Linux原生联网仍未完成。

## 工作区与证据规则

- 主 checkout：`/Users/cusgadmin/if-local/monkeycraft`，分支 `claude/web-m2-m3`。
- 初始用户修改：`mods/26.2/src/main/resources/monkeycraft.mixins.json`；未跟踪的 `WindowMixin.java`、产品路线、`exports/`、`outputs/`、`web-tailscale/`。保留原样，不自动纳入提交。
- 未创建 worktree；除用户明确授权的 Web/Pages `ace51c9` → `origin/master` 外，不 commit、push、创建 PR、生产部署或开通付费资源。该提交尚未部署。
- 未发现已安装的 ultracode 工具/命令/技能，使用现有开发与并行代理工具执行。
- 历史：`web/CHANGELOG.md`、`web-tailscale/docs/EVIDENCE.md` 等只作为历史线索。本轮自动化、实机、待测和阻塞分别记录。

## 环境

| 项 | 本轮探测 |
|---|---|
| 主机 | macOS / Apple Silicon |
| Java | JDK 25.0.2、21.0.11；另有 26.0.1，Mod 显式使用匹配版本 |
| Web | 初始Node 22.22.3；最终本机验证显式Homebrew Node 26.0.0、pnpm 11.26.0；Chrome、Safari 已安装 |
| Go | Homebrew 1.26.6；另有旧 `/usr/local/go/bin/go` 1.19.5，构建明确选择 Homebrew |
| Flutter | `/Users/cusgadmin/if-local/flutter/bin/flutter` |
| iPhone | `devicectl` 检测到已配对真实 iPhone；可用状态不等于 App/锁屏/音频已测 |
| Android | 无连接真机；既有API36 ARM64模拟器保留数据覆盖安装当前Release，完成真实26.2短测后关闭；Android Studio/SDK 已安装 |
| Minecraft | 四个真实 Prism 实例均存在；26.2 为 `ImagineFun Add-Ons`，含 DebugBridge |
| DebugBridge | 四版本会话控制均已开启；本轮三旧版完成运行并退出，已恢复26.2；当前测试使用独占交接 |

## 阶段与验收矩阵（重启后最新）

| 阶段 | 已实施与本轮证据 | 剩余门槛 |
|---|---|---|
| P0 | 产品文档已统一为Flutter共享App/Web；主checkout与既有修改保留；历史、当前、真机与自动化区分记录 | 随最终设备/发布结果继续更新 |
| P1 Web | 主224/analyze；真实26.2 Chrome核心/提醒、真实Safari核心/计时/Pointer Lock与声音调用；四版最终包均真实运行 | 用户听感、后台OS通知、实体手机浏览器、进一步平台/网络 |
| P1 App | 通知/倒计时/音频修复保留；最新共享源码iOS clean有效设备包及Android Release结构验证；历史原生与设备用例按原包保留 | 最新真机行为、锁屏/后台音频/切网；iPhone当前不可达；Android Release现有AVD短测已完成 |
| P2 iOS | 原Go桥接与登录等待反馈保留；早前本人登录与双内嵌真机通过；本轮新设备包逐嵌套平台/签名通过 | 新包安装/真机感知、冷启身份与切网 |
| P2 PC | helper集成/分发/生命周期与协议测试通过；26.2同身份重启并正常监听；历史真实双端和离线Linux容器证据单列 | Windows/Linux原生联网、强制DERP、节点撤销、跨网络 |
| P2 Android | JNI/Kotlin、双ABI与授权门控已实现；本轮Release签名/ABI/16KiB通过并保留数据覆盖安装；真实26.2视频/系统提醒/恢复/重连短测通过 | 本人tailnet授权、VPN共存、混合连接、物理设备/OEM后台 |
| P3 | 四树同步，最终JAR49资源核对；Java66/61/61/61；当前Flutter包真实回归26.2 120秒，其余各60秒 | 旧版helper授权/跨设备；当前包更长持续与平台范围；不转算历史长测 |
| P4 | 73文件候选普通archive验证204+24、Pages Release及本地项目路径E2E通过；部署工作流就绪 | 等共享Dart范围发布授权，再commit/push/dispatch及公开入口验收；未部署 |

## 共享 Flutter 实际验收前的状态快照（历史，不代表当前）

以下保留先前日志原文；其中“当前”“最终”仅指该阶段，不能覆盖本文件顶部最新状态。

当前范围：用户已恢复原产品路线并确认 GitHub Pages 采用 Flutter Web。浏览器与 App 共享 UI/业务代码，浏览器只保留薄适配层；旧独立 TypeScript Web 保留作参考，尚未删除。除用户已明确授权的 Web 客户端和 Pages 工作流范围外，不提交、推送、创建 PR 或公开部署。该例外已将含既有九个 Web 提交的 `ace51c9` 推送至 `origin/master`；尚未触发 Pages 发布，公开地址仍为旧 Flutter 网页。待 Flutter Web 通过验收后，用户已同意将其发布到 Pages。域名可选，不阻塞本地静态入口开发。历史记录中的“暂停”只描述当时状态。

当前追加验收（2026-09-19）：用户已完成步骤1，26.1会话控制已开启，最终2a48ef6包已在真实ImagineFun完成600,028ms/6,273帧/解码错误0、四次尺寸切换、最小化、按键释放与受控断线重连；helper启动到needsLogin并随游戏退出，账户授权尚未确认。1.21.11与1.19的最新包也已完成真实短测和按键释放。旧live用例的暂停菜单误判已修复，四版本均重新运行并逐张确认真实背包。详见[26.1证据](tailscale-integration/evidence/2026-09-19-26-1-runtime.md)。此前blocked段落保留为历史，26.1权限门槛已解除。

当前执行状态（2026-09-19）：最终 PointerLock 补丁的四个 JAR 已构建、独立核验并部署到本地对应实例。26.2 当前包 `2f6045c…` 已在真实 ImagineFun 通过 HTTPS/WSS 视频与背包开关；游戏 68918 / helper 68983，内嵌 IP 100.82.132.32、身份指纹 1148163683 不变，无控制客户端、SHIFT=false，电脑园区音频 active/connected。恢复状态见 `outputs/roadmap-2026-09-19-26.1-acceptance/final-restored-26.2.json`；此前[修复证据](tailscale-integration/evidence/2026-09-19-pointer-final.md)保留为历史。

真实十分钟结果按实际产物保留：26.1当前2a48ef6包600,028ms / 6,273帧；26.2 的 6fabc1 包 600,032ms / 4,786帧；1.21.11 的 d42a65 包 600,031ms / 6,778帧（含最小化）；1.19 的 dd3dd0 包 600,030ms / 7,971帧，均四次尺寸切换、错误0。最终晚期补丁只改变浏览器鼠标锁定，未将这些结果转算到不同哈希。1.19 在既有独立世界 `MonkeyCraft acceptance 2026-09-1` 验证；ImagineFun 最低要求1.21+。

独立 TypeScript Web 的最终 TypeScript、Biome与两种构建曾通过，Chromium23项/5跳过、WebKit22项/6跳过；Pages当前项目路径既有专项4项/1跳过，加PointerLock3项通过。160项单元及此前Pages项目路径19项/根路径专项4项分别保留为历史批次。它们不再构成正式 Flutter Web 的验收。当前 Flutter Web：`flutter analyze` 无问题、完整 Flutter 测试210项通过、release Web构建25.1秒且Wasm dry run成功；Chrome视频2项、浏览器通知11项、浏览器输入Chrome5项与VM20项、托管目标/认证25项、Node来源5项定向检查通过。各套件可能重叠，不合并计数；生产UI smoke仍在进行。

App最近基线为Flutter完整192项/analyze；Android原生11项在此前通过，本次仅改Dart协调器，未改原生代码。旧`f8bbc80…`包在强制Doze到点后GUI断开重连，实测重新提交过期提醒；已修复，新正式Android包`4f5a225…`在相同旧deadline上不重发，新的未来提醒在深度IDLE中+9ms生成，恢复/GUI重连/额外等待均无重复，显式取消正常。详见[过期提醒证据](tailscale-integration/evidence/2026-09-19-expired-reminder.md)。此前正式GUI的通知限额、精确定时授权、输入释放与园区音频状态验证另保留，不算新包逐项重跑。iOS同修复的clean Release 1.4.2(11)已通过平台/签名验证并覆盖安装，较早包的真机声音/锁屏反馈与新包待复验分别记录。5554本人授权等待状态保留，隔离5556恢复测试设置后已关闭。四个版本已嵌入最新Web/helper产物；26.2测试62项，其余各57项实际重跑通过，[当前产物清单](tailscale-integration/evidence/2026-09-19-pointer-final-artifacts.json)。1.19增量remap失败及清理重建通过均保留，不把首次失败隐去。26.1会话控制及本机运行已完成；旧版内嵌本人授权和实际手机的剩余门槛仍未完成。

当前P4与Safari追加工作（2026-09-19）：用户已授权推进GitHub Pages配置并手动开启Safari自动化。远端仓库为公开仓库、Pages已采用Actions/强制HTTPS，仅master可部署，无自定义域名；现有公开地址HTTP200仍为旧Flutter网页。用户明确授权的 Web/Pages 范围（含既有九个 Web 提交）已以 `ace51c9` 推送至 `origin/master`，但尚未 dispatch 工作流或部署。用户确认采用 Flutter Web 作为 App/Browser 共享 UI/业务代码、浏览器薄适配层的正式方向；旧独立 TypeScript 客户端保留参考，待 Flutter Web 验收通过后发布 Pages。Flutter Web 本轮已通过静态、完整回归、release构建以及视频/通知/输入/身份定向检查；生产UI smoke仍在进行，不能写作功能验收或迁移完成。本地 TypeScript Pages 产物的来源/run/工具链/hash与其160项单元、Pages浏览器5项/1项权限跳过，均保留为历史验证。真实桌面Safari第二会话的安全上下文、H.264 解码（dec259/err0）、E/ESC 背包协议与原生 `InventoryScreen`、页面提示音 API及真实 NUDGE横幅，同样仅是旧独立实现的历史证据；Flutter Web 后续需重新覆盖桌面Safari连续视频、后台系统通知和重连。见[Flutter Web证据](tailscale-integration/evidence/2026-09-19-flutter-web-feasibility.md)、[Pages核验证据](tailscale-integration/evidence/2026-09-19-pages-provenance.md)与[桌面Safari证据](tailscale-integration/evidence/2026-09-19-desktop-safari.md)。

### 早期阶段与验收矩阵

| 阶段 | 代码/文档状态 | 本轮自动化 | 真实设备/环境 | 剩余门槛 |
|---|---|---|---|---|
| P0 | 产品方向文档已统一；持续维护证据与能力矩阵 | 初始检查和失败基线已归档 | 四实例与开发工具已探测 | 随实施更新最终支持矩阵 |
| P1 Web | 提醒SW、后台重连、输入、手机横幅、资源打包与Pages静态直连已实现 | 最终Chromium23项、WebKit22项，Pages当前专项4+3项；此前160项单元与Pages19/4项保留；权限不足场景单列跳过 | 当前2f6045c包真实视频/背包通过；6fabc1十分钟及旧版d42a65/dd3dd0十分钟按原哈希单列；Android Chrome133模拟器现场结果保留 | 实体手机、最新Android Chrome/iOS Safari、可听声音与公开托管入口E2E |
| P1 App | 通知授权/声音、倒计时串行化、音频后台租约、Android提醒配额/精确定时与过期重放保护已实现 | Flutter192项/analyze；此前原生11项通过，本次原生未改；新APK双ABI/16KB/签名通过 | 新4f5a225包真实26.2 GUI旧deadline不重发、深度IDLE未来到点+9ms、恢复/重连去重、显式取消通过；此前f8包通知压力/授权/输入/音频单列 | iOS新包感知与园区后台音频；Android本人登录、真机声音/锁屏、OEM休眠与VPN共存 |
| P2 iOS | 保留原Go集成、等待动画、正式日志静默与设备包预检；共享过期提醒保护已更新 | 登录7项、数值ring race与签名诊断此前通过；最新完整Flutter192项/analyze、嵌套平台/签名通过 | 新修复包clean构建48.5秒、覆盖安装/readback 1.4.2 (11)；较早真机通知/锁屏和模拟器园区连接结果单列 | iOS新包可听/锁屏/园区后台音频、NUDGE授权、Live Activity、冷启动身份与切网 |
| P2 PC | 26.2 helper集成、分发与登录/身份事件修复已实现 | Go全量/race/四平台构建/Java harness通过；生产backend隔离控制面转发与持久身份重启通过；26.2相同AuthURL去重补丁后62项测试通过 | 本人账户授权、iPhone双内嵌画面、同身份重启及系统→内嵌150帧；Linux amd64 helper在arm64 Docker翻译下生产backend离线生命周期通过 | Linux原生x86/联网、Windows、强制中继、撤销节点与跨网络切换 |
| P2 Android | JNI/Kotlin、双ABI、登录门控、提醒配额/精确定时与过期重放保护已实现 | Flutter192项/analyze，新APK双ABI/hash/16KB/签名通过；原生11项此前通过 | 新4f5a225包GUI连真实26.2、强制Doze+9ms到点、过期重放保护/重连去重/取消通过；此前正式包通知/输入/音频另列，5556已关闭 | 5554本人授权、VPN共存、身份恢复、混合连接、Android真机声音/锁屏与持续播放 |
| P3 | 四树源码、Web/helper资源及Java版本适配已同步；CI四版本资源链已接入 | 26.2为62项、三个旧版本各57项；各JAR资源/hash/许可核验通过 | 四个当前包已实际运行，最新26.1十分钟/resize/最小化/断线恢复通过，最新1.21.11真实ImagineFun及1.19既有本地世界短测/输入释放通过；四版加强背包用例及截图复核通过；三个旧版配置哈希不变 | 三个旧版helper本人授权/混合连接/真机全量待验；1.21.11/1.19十分钟仍归属此前包；ImagineFun不接受1.19；未触发远端CI |
| P4 | Flutter Web 共享App UI/业务代码，浏览器薄适配层已进入实施；旧独立版保留参考。Web/Pages范围已推送`ace51c9`至master，但其独立产物未部署 | Flutter analyze无问题、完整测试210项、release Web构建/Wasm dry run、视频2项、通知11项、输入Chrome5项+VM20项、认证25项、Node来源5项通过；生产UI smoke进行中 | 无本轮真实Minecraft或Safari/手机浏览器通过结论；未 dispatch 或部署公开入口 | 完成Flutter生产UI、真实浏览器/真实游戏与Pages项目路径验收后发布；不将迁移或删除独立版列为完成；域名未购买不阻塞 |

## 初始版本能力（代码事实，非验收结论）

| 版本 | App WebSocket/配对 | HTTP静态网页/同端口分流 | tailnet HTTPS入口探测 | PC helper Java集成 |
|---|---|---|---|---|
| 26.2 | 已有 | 已有；初始构建错误引用旧Flutter Web产物 | 已有 | 初始缺失 |
| 26.1 | 已有 | 初始缺失 | 初始缺失 | 初始缺失 |
| 1.21.11 | 已有 | 初始缺失 | 初始缺失 | 初始缺失 |
| 1.19 | 已有 | 初始缺失 | 初始缺失 | 初始缺失 |

## P0 / P1 打包改动

- 更新 `doc/WEB_TAILNET_PLAN.md`、`web/PLAN.md`、Flutter/项目结构文档和 Tailscale 计划的优先级说明。保留 App 两条正式产品线、LAN/系统与内嵌混用；旧阶段编号不再替代产品路线。
- 26.2 Gradle 与本地部署脚本改用 `web/dist/`；缺失浏览器产物时明确失败，防止成功生成没有网页的发行包。
- 历史 CI 的26.2构建使用独立 Web job 产物，release 先生成 TypeScript 客户端。Flutter Web 成为正式P4方向后，Pages/发布链须改为生成并验收Flutter产物；当前尚未声称该替换完成。

## 本轮命令与结果

| 命令 | 结果 | 证据边界 |
|---|---|---|
| `JAVA_HOME=$(/usr/libexec/java_home -v 25) ./gradlew build`（26.2初始） | 成功，8秒，全部任务缓存 | `/tmp/monkeycraft-26.2-baseline.log`；并非本轮重新执行单测 |
| `adb devices -l` | 无连接设备 | Android真机尚不可测 |
| `xcrun devicectl list devices` | 检测到真实iPhone及关闭的模拟器 | 不等于已解锁/已安装本轮App |

## 待用户动作与未完成项

目前先推进无需用户介入的开发和验证。需要账户登录、设备解锁或架构选择时记录具体步骤；不得将构建成功、模拟器或Playwright WebKit标为真实手机通过。

恢复现场验收的最短顺序：

1. **iPhone新包的感知音频复验。** 含OpenAudio URI与过期提醒修复的新包已通过平台/签名验证并覆盖安装；此前iOS模拟器fresh session已验证页面媒体连接、调用softRefresh后仍保持连接和断开清理，但不能替代真机可听、锁屏或园区后台播放。复验首次NUDGE授权、Live Activity、园区后台音频、冷启动身份和切网；较早包的有声/静音、更新、取消、锁屏反馈不能替代新包。
2. **Android本人登录与真机。** 当前Release `4f5a225…` 已通过双ABI/16KB/签名验证，在隔离5556连接真实26.2完成过期重放保护、强制Doze未来到点+9ms、恢复/GUI重连去重和取消；此前f8包的通知压力/授权/音频/输入结果另列。5556已关闭，5554仍保留旧包及本人授权等待状态。本人登录后继续新包tailnet混合/身份恢复；模拟器无声，真实声音、锁屏、OEM后台策略、VPN共存仍待验。
3. **旧版内嵌授权。** 26.1会话控制与十分钟、重连验收已完成；其helper曾请求打开一个授权页，最后读回仍为needsLogin，尚未确认本人授权。三个旧版helper启动/退出有证据，实际账户授权及跨设备连接仍待完成；保留各实例独立身份，不复制26.2节点。1.19使用本地测试世界，ImagineFun要求1.21+。
4. **P4托管入口。** 用户已允许并完成 Web/Pages 范围的 `ace51c9` 推送到 master，但未 dispatch/deploy，公开地址仍是旧 Flutter 网页。产品方向已确认：以 Flutter Web 共享 App 的 UI/业务代码，使用浏览器薄适配层，保留旧独立版作参考。当前静态/完整回归/release编译和定向浏览器套件已有记录，生产UI、真实浏览器/真实游戏和Pages入口验收尚未完成；完成后发布Pages。

## 集成回归发现（本轮，不隐去失败）

- Web 首轮通过 Biome、TypeScript、138 项 Vitest、17 项 Chromium 回放；两个真实场景默认跳过。补上用户声音开关、15秒迟到窗口、刷新去重、触控失焦释放和留黑点击测试。详见 [Web证据](tailscale-integration/evidence/2026-09-18-web.md)。
- Flutter 首轮 analyze、146 项测试、debug APK 和无签名 iOS 设备包通过。后续 iOS 静音回调引入 Swift 类型推断错误，被根代理签名构建抓出；修复后签名 `flutter build ios --release` 本轮通过（48.2MB）。详见 [Flutter证据](tailscale-integration/evidence/2026-09-18-flutter.md)。
- `flutter install -d 00008140-000E65D40183801C` 未安装成功：工具报告设备 Developer Mode 未开启 / No target device。已请求用户开启、按需重启/解锁和信任电脑。不能声称本轮App已装机。
- 26.2 `spotlessApply clean build` 首次集成执行48项测试，4项 HTTP/Shutdown 测试失败，原因是新增helper入口令普通测试触发Minecraft类初始化；正在修复并重测，缓存基线成功不能掩盖此次失败。
- 本机已有多个 Tailscale Serve 路由。原 `TailnetHttps` 取第一个端口会误指其它服务；已改为严格匹配当前Mod端口的loopback根代理与HTTPS监听，并新增测试。已有8443指向9600，且用户既有配置含Funnel；本轮没有新增/修改Serve或Funnel。
- HTTP HEAD原来错误返回Content-Length=0；本轮改为与GET内容长度相同但不发送body，HTML添加no-cache，补充同端口HTTP/WebSocket集成断言。
- PC helper构建资源包含四平台binary、manifest、SHA、Tailscale许可证；Gradle校验协议/平台/长度/hash。已新增可重复`build-all.sh`，并接入CI。尚不等于已完成签名/各OS运行验收。
- Android原生桥接已实际实现并构建，当前继续修复生命周期和socket清理审阅发现的问题；必须以最终重测结果为准，不能以较早APK成功替代最终验收。

### 早期外部阻塞（历史，当前状态以上方矩阵为准）

1. iPhone已通过devicectl安装启动；原Flutter Developer Mode报错已排除。当前需用户本人完成Tailscale账户登录与声音/锁屏等感知验证。
2. DebugBridge session control关闭，已提出精确授权问题，未修改权限。真实游戏已从Prism启动；可用产品自身服务器选择流程继续测试。
3. Android无已连接设备。桌面自动化、构建和代码修复继续；真实Android的SELinux、已有VPN、后台音频/切网待测。
4. 内嵌Tailscale首次登录与设备授权需要用户本人完成；不创建可复用auth key或替用户选择账户。

### iPhone与26.2复测更新

- `devicectl device info details` 返回 Developer Mode **enabled**、本地网络配对连接；Flutter的提示与系统状态不一致。使用系统识别的 CoreDevice ID 后，`devicectl device install app` 成功安装本轮签名 `Runner.app`，`device info apps`确认`com.chenweikeng.monkeycraft` / `1.4.2` / build `11`，`device process launch` 成功启动。此前“需开启Developer Mode”不再是已确认阻塞；真实UI/通知/声音/锁屏/音频仍未验收。
- 26.2修复后的`spotlessApply clean build`全部任务实际执行并成功（17秒）。之后继续修复helper异步停止竞态，最终结果待再次集成。
- 真实26.2旧jar + 当前Web Vite路径已通过配对密码鉴权、正式服务器选择器进入`mp.imaginefun.net`、视频解码、E库存和Escape关闭。第一次Escape失败已定位到pointer lock状态事件时序，修复后普通live测试通过；不能将此路径写成最终JAR或HTTPS已验收。

### helper原生组件实测与工具链

- 本机darwin-arm64真实tsnet helper（无fake backend）启动→ready→starting→needsLogin，nonce一致，状态目录建立，发送shutdown后进程exit 0。未收到完成授权，未声称tailnet数据面互通；测试没有输出登录URL或密钥。
- 环境同时存在旧`/usr/local/go/bin/go` 1.19.5和Homebrew Go 1.26.6。直接bash构建命中了旧版本并报go.mod格式错误；使用`PATH=/opt/homebrew/bin:$PATH`后重建四平台。此为工具链路径问题，不能删改go.mod降低版本掩盖。


### 真实浏览器与登录延迟专项（更新）

- 最终打包26.2 JAR（SHA256 `733c58582efbab719cd76c21f145b5f03c4d470a1d60211b3be46628a79ed90f`）在已有HTTPS入口完成普通live场景及10分钟持续测试，安全上下文/WSS、服务器选择进入ImagineFun、视频持续解码与4次尺寸变化采样通过。后续helper修复将产生新JAR，不能将本次hash冒称最终全部修复产物。
- Playwright WebKit三项decoder回放在单worker重测仍分别49/65、143/159、68/84帧，均比输入少16帧；无解码错误，不降低断言，继续修复。WebKit不是真实iPhone Safari。
- 用户先报告iPhone点击登录未弹窗，随后确认最终打开；再操作仍约半分钟，并明确以前较稳定。记录为真机延迟复现，**未解决**。正在记录启动、状态、登录请求、AuthURL收到和系统浏览器打开的阶段耗时。
- 安装到iPhone的首轮包未修改原有`TailscaleCBackend.swift`与`TailscaleNodeManaging.swift`，其内容与HEAD一致；本轮原生iOS变化为通知静音行为。不能据此排除旧实现受生命周期/环境触发的缺陷，也不能声称已找到回归来源。
- PC helper真实独立新状态三次：needsLogin约0.14–0.16秒，authRequired约4.197 / 1.134 / 1.439秒，均正常shutdown exit 0。只保存阶段/耗时/是否有URL，不保存登录URL或密钥。该对照不等于iOS性能结果。
- PC根因修复：`BrowseToURL`可能没有伴随State，旧适配层把登录地址事件丢弃；现显式映射needsLogin，并报告交互登录请求错误。已补单测、四平台重建。
- 新一轮Java构建发现本机其他IPv4服务占9601时，IPv6通配端口预检误报空闲，HTTP测试连到错误服务返回400。增加IPv4占用检查和真实占用端口回归测试；并修复helper标准输出EOF先于进程退出时可见状态的竞态，增加延迟退出测试。
- 官方/第三方Flutter接入核查与来源见[接入与延迟调查](tailscale-integration/evidence/2026-09-18-tailscale-mobile-review.md)。继续现有实现并以旧路径对照，未擅自更换框架或节点身份存储。


## 用户调整范围：当前唯一任务为 iOS Tailscale 延迟

用户于2026-09-18明确要求：先将其他事项记录、以后处理；当前唯一待办为查清并修复iOS内嵌Tailscale约30秒登录等待。用户允许充分调试、使用模拟器/虚拟机并花足够时间深入阅读相关代码。此节优先于前述阶段推进顺序。

### 延期工作交接

- 26.2：HTTP打包、HEAD/cache、helper接线和登录事件修复代码保留。正在打包的新helper尚未部署到游戏；真实MC仍为之前通过HTTPS持续测试的jar。新增IPv4端口占用检查和helper EOF/exit竞态修复已有代码，最后一轮构建结果需收取归档，不继续部署。无commit/push/PR。
- Web：有限录像回放在WebKit关闭decoder前尚有16帧未输出；新增有限流drain/flush再采样，不修改实时播放路径、不降低阈值。最终139单测、lint/typecheck/build、Chromium与WebKit各17回放通过（各2 live默认跳过）。此前最终jar真实HTTPS普通+10分钟持续测试通过；新web bundle未再装入运行游戏。真实iPhone浏览器声音/通知/音频未测。
- Android：已完成三次ARM64 API36原生integration（包括状态事件、start/stop重复/restart/cancel），analyze无问题；已修缺少so、NETLINK_ROUTE/Go日志目录崩溃、线程/取消竞态、状态轮询、logout和dial超时；两ABI可复现构建脚本与overlay保留。没有真实账户授权、交互浏览器/peer/dial或Android真机证据。测试AVD已关闭、数据保留。
- Flutter通用：首轮146测试、analyze与原生构建结果见证据。真机通知有声/静音、锁屏倒计时、音频后台恢复、混合连接与身份重启仍待验收，暂停。
- P3其他三个Minecraft版本尚未移植；P4未作架构决定、无部署或付费资源。以上全部延期，不作为当前并行任务。

### 当前iOS排查分工

- Swift/真实原生测试：逐段测start、status、loopback、login请求、AuthURL收到、浏览器完成回调；首次/重复/前后台/取消等状态对照。
- 独立源码审查：深入Flutter和Swift队列、事件、生命周期与固定Go1.94.1控制面时序，列每个超时/退避的触发条件，实验验证，不能只给泛泛可能。
- 原实现追溯已确认：Go自编译C archive，现存iOS archive与2026-08-30 manifest完全一致，详见[iOS来源证据](tailscale-integration/evidence/2026-09-18-ios-libtailscale-provenance.md)。
- 初个模拟器native测试start/status/login POST/status约1.230秒，但未覆盖等待AuthURL实际出现，不能因此排除后续控制面/重试等待，更不等同于真机通过。


### iOS延迟：已复现并缩小到注册响应（进行中）

- 使用iOS同固定`tailscale.com v1.94.1`在macOS运行纯Go临时基准，绕开Flutter/Swift/C ABI和URLSession：三次Start20–25ms、login请求返回90–93ms，首次AuthURL **33.770 / 8.391 / 1.890秒**。
- 再次无敏感日志测试：`/key`537ms、Noise连接864ms均完成，首次`RegisterReq`538ms开始，`got response`32172ms，AuthURL32251ms。该次没有注册重试，等待窗口位于`POST /machine/register`响应头或body/decode，正在加更细探针；不能提前称为Tailscale服务端问题。
- iOS模拟器原生完整测试：Start78ms、本地登录POST71ms、首次AuthURL20689ms。之前0.78–1.23秒的短测试只测到POST返回，已修正测试终点，未作成功性能结论。
- 去掉额外显式login请求、仅靠tsnet.Start自动登录的一次样本1.732秒；样本不足，不认定重复调用是根因，后续按同环境串行对照，避免并发注册干扰。
- 原始脱敏阶段数据归档：[登录计时](tailscale-integration/evidence/2026-09-18-ios-authurl-timings.json)。来源/固定版本与调用分析分别见专项证据。
- 延期工作的最后构建：26.2的IPv4占用回归测试仍失败（其他HTTP请求测试通过），该改动未完成验证且未部署，留待恢复该阶段处理。不能把早先构建成功覆盖此次失败。


### iOS延迟对照：控制面502直接证据

同一机器、同一临时Go程序、全新临时state，按序运行两轮（非并发注册）：

| 方案 | 第1轮首次AuthURL | 第2轮首次AuthURL |
|---|---:|---:|
| v1.94.1仅自动登录 | 45秒超时 | 9.717秒 |
| v1.94.1加显式登录 | 24.275秒 | 8.658秒 |
| v1.94.1加显式登录、强制443对照 | 28.818秒 | 1.340秒 |
| v1.102.3加显式登录 | 10.343秒 | 8.783秒 |

- 28.818秒样本中，注册接口连续14次明确返回HTTP502：`backend not found or not available; reqType=noise-register/machine-pubkey; saw 43/44; tn=0`。Tailscale客户端随后按官方通用退避策略重试。已保存脱敏错误与请求追踪ID；未保存登录URL、密钥、请求体或响应体。
- 此为至少一个同量级慢样本的直接控制面失败证据，不能把它归结为Flutter/Swift/Debug慢，也不能断言服务端内部具体是哪台机器、部署、容量或限流。其他无502但慢的样本仍在细分响应等待。
- A/B方差很大：仅去掉额外login、升级库或强制443均没有稳定消除等待，尚不据此改变产品pin或网络配置。
- iOS增加默认关闭的阶段诊断宏；下一步准备保留原Go库和身份的Release诊断包，以原生日志白名单分类确认真机是否遇到相同502，且继续改进准确的等待/错误显示。尚未安装新版诊断包，不宣称问题修复。

### 真机取证准备与证据复核

- 已暂停额外注册请求。细分探针在45秒超时前未得到外层register响应；内部HTTP Upgrade约324ms响应。由于父context上的httptrace会传到内部Upgrade，不能把该324ms标作register的首字节时间，也不能把首版丢失数值参数的日志当作“未写出请求”的证据。专项源码分析已修正文案。
- 官方已有跨平台同文本502报告 [tailscale/tailscale#16841](https://github.com/tailscale/tailscale/issues/16841)，但公开信息不解释服务端内部原因；官方状态页当前正常也不能否定本轮抓到的短暂失败。未向外发送日志、创建issue或联系支持。
- 原生`tailscale_set_logfd`经独立审查不适合本次取证：Go接管fd却不显式在重设/关闭时释放，Swift代管会造成关闭/复用竞态，而且原始日志包含敏感字段。未使用pipe采集原始日志。
- 仅准备独立的、可重建的诊断archive：固定原libtailscale和v1.94.1源码，隔离副本打窄补丁，只导出注册阶段、耗时、HTTP状态码与序号；保留原产品archive，默认正式构建不启用。旧archive来自Go1.26.3，诊断也以同工具链减少变量。补丁、构建和签名包尚在实施，不能写成已安装或真机通过。
- 真机当前可达，已确认MonkeyCraft为1.4.2(11)。计划用同bundle ID覆盖安装诊断Release包，不卸载、不清空身份、不手工杀App；等待用户确认当前是否已完成账户登录，再选择最短复现步骤。

### 登录交互修正与诊断构建（本轮新增）

- 用户确认尚未完成账户登录，因此后续直接在现有身份上复现，无需退出账户或清理state。
- 独立审查明确了额外等待风险：没有AuthURL时再次调用`loginInteractive`会经官方`Auto.Login`取消并重启在途注册。修正Flutter提示和按钮：等待期间让自动注册继续，仅已有登录地址时提供重新打开；初始化和快速重复点击均加busy保护。此项不是已经抓到的502根因，也不承诺消除服务端等待。
- `flutter test test/stream/tailscale/tailscale_login_sheet_test.dart`：7/7通过；包括35秒等待不额外发起登录、地址就绪后提供重开、快速双击仅一次请求。测试是界面自动化，非真机性能结果。
- 诊断archive已经用Go1.26.3、原libtailscale pin和v1.94.1隔离构建完成，补丁/脚本见`flutter/monkeycraft/ios/tailscale_diagnostics/`。固定数值ring记录register Do开始/返回、非200 body耗时、成功decode耗时；不更改超时、重试或HTTP逻辑。Go的UserLogf另行设为Discard，避免默认AuthURL打印。
- 原产品archive SHA仍为`ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9`。仅抽出Runner使用的归档路径变量，普通Release的完整linker flags、编译条件、bundle ID与修改前逐项相同。诊断构建检查确认只替换一个archive，所有Pods target均不链接Go归档；不使用全局OTHER_LDFLAGS替换。
- 原先被忽略的iOS构建脚本现在有窄范围Git例外，可审阅其`link-config`生成路径；生成配置、源码副本和二进制仍不纳入版本。签名构建正在执行，尚未安装到真机。

### 诊断Release已装机，等待单次真实复现

- `python3 ios/tailscale_diagnostics/build_release.py --check-only`通过；普通/诊断链接隔离及25个Pods检查通过。`--skip-flutter-config`签名构建成功，`codesign --verify --deep --strict`通过。原有视频/loopback警告、AppIntents元数据提示及扩展build号1与App11不一致警告保留记录，不将warning当作本轮延迟原因。
- `flutter analyze`本轮无问题（5.3秒）。诊断Runner二进制SHA为`f9168d502c77fd22054f23d1a1d6416448f0145e4e06268615804ac05c6c074e`，所链接诊断archive SHA为`5594077ad3c8de9bde63f3c6d401d7435e718989804562cefe0bdfa48308d2df`；后续只格式化/追加离线测试的archive不得混称为此轮已安装产物。
- `devicectl device install app`覆盖安装成功，随后`device process launch`成功。同bundle ID、1.4.2(11)，没有卸载、注销或清空state，也没有手工kill App。构建/安装日志位于`/tmp/monkeycraft-ios-diagnostic-{config,release,install,launch}.*`。
- 已请用户仅点一次Connect with Tailscale并等待自动打开登录页，暂不完成账号登录。尚未获得此次真机耗时，不宣称真机延迟修复；等待期间继续完成离线数值ring验证和证据整理。

### 离线诊断验证完成；真机采样待用户操作

- 最终格式化补丁加入有界窗口、并发读写和reset测试。隔离副本中`GOTOOLCHAIN=go1.26.3 /opt/homebrew/bin/go test -race -run TestMonkeycraftDiagnosticBoundedConcurrentReset`通过（1.620秒），没有发起注册请求。
- 与最终跟踪补丁一致的诊断archive为`e999dccbd9d09d1362f09f6b07492bace524edd542775e89d11f39d623083aed`。重签构建成功，日志确认实际执行Runner链接步骤，签名二进制SHA变为`8eddcf065867d6a929949273a88d44170870c209cdccb80168192117baec3762`，codesign严格验证通过；没有把缓存构建视为重新链接。该候选包尚未再次安装，以免打断已请用户进行的首轮采样。
- 首轮已安装的完整签名包保留于`/tmp/monkeycraft-ios-diagnostic-first.app`。真机读取指定诊断JSONL的一次尝试返回CoreDevice7000文件节点不可用；尚未取得本次连接事件，不能据此判断手机端性能通过或失败。需用户点一次Connect with Tailscale并报告页面出现/60秒未出现，再读取阶段文件；后续恢复分析时优先执行这一项，不重跑已经完成的注册A/B。

### 真机结果：首次注册200；补上等待动画

- 用户反馈登录页约8秒出现，并希望等待阶段显示转圈。本轮已成功读取34条真机数值事件，根代理和独立子代理分析一致；证据：[真实iPhone登录时间线](tailscale-integration/evidence/2026-09-18-ios-phone-login.json)。之前文件节点不可用已不构成阻塞。
- 这次**没有502**。原生start耗时34ms，首次注册`httpc.Do`到200响应头耗时3944ms，decode为0ms；Swift在start.entry后5068ms观察到AuthURL，系统open成功回调在5125ms，打开调用约56ms。Go事件实际发生时间使用offsetMs，不能把Swift轮询收集时间当成Go发生时间。
- 本次没有显式loginInteractive，故没有重复点击导致的取消重启。第二次register发生在第一次已拿到AuthURL之后，是后续等待授权流程，不能算成失败重试或弹页前阻塞。
- 用户主观约8秒与埋点覆盖5.125秒边界不同；日志不能分辨额外时间是点击到原生入口、网页呈现还是估计误差。3.944秒也不能再拆成传输与闭源服务端处理。不能将此前纯Go的502慢样本直接归给此次真机，亦不能追溯证明用户最初30秒那一轮真机错误码。
- 对用户澄清：502并非正常成功登录的必经步骤，它是本次请求失败；官方重试是容错机制。本次200首发成功说明正常注册也存在网络等待。节点启动方式或Debug性能不是本次主要耗时。
- 已让`needsLogin`且AuthURL未就绪时持续显示转圈；就绪时结束，保留取消和原有操作可用性，不用动画替代错误处理。相关7项Flutter测试通过（包括等待期间动画存在、URL就绪后消失、不重复发起登录）；签名Release构建正在进行。

### 2026-09-19 等待动画安装完成

- `flutter analyze`无问题（6.4秒），登录界面7/7测试通过。首次增量Xcode build虽然报告成功，但独立codesign严格校验发现`a sealed resource is missing or invalid`；此失败包未安装，没有忽略校验。
- 将诊断签名脚本改为在专用DerivedData执行`clean build`。干净构建成功，完整app的`codesign --verify --deep --strict`通过后才覆盖安装。后续诊断打包沿用该规则，避免Flutter资源改变后旧签名被增量缓存保留。
- 本轮等待动画包已通过`devicectl device install app`安装并成功启动；同bundle ID和现有身份，不卸载、不logout。使用最终跟踪补丁对应的e999诊断archive。Runner SHA为`8644417dd6d0e950eefa1137214887876687b7bdd2ac02c714c951fc6e89359b`，Dart App.framework SHA为`3fb0a64f93217d3c1f9d117c02b337cd425350c11cf418178768b14a1cdebc55`；元数据见登录计时JSON中的`spinnerRelease`。
- 已验证“等待时转圈、AuthURL就绪后停止”的自动化行为；尚未另外取得用户对新动画的真机观感反馈，也未代用户完成账户授权。后续最短动作是点一次Connect with Tailscale，等待登录页自动打开后用本人账户完成登录；其他产品阶段仍暂停。


### 2026-09-19 恢复完整路线与 Android 启动调查

- 用户恢复原计划并允许模拟器验证；建立持续goal。沿用主checkout，不创建worktree，不提交或发布；普通并行代理分别负责Android/App、iOS正式构建、Web/P3准备。
- Android首次恢复启动在进入App之前停滞，adb没有设备。主机64 GiB，调查时系统约66%–67%可用、无swap进出；没有内存不足证据。两份现有qemu崩溃报告时间为9月18日22:24、22:48，SIGABRT堆栈指向skin_winsys_quit_request退出处理，不能据此宣称本轮App崩溃或OOM。
- 下一步为单AVD、脱离调用进程生命周期、保存完整启动日志、禁用快照加载并使用软件GPU。保留AVD数据，退出优先emulator自身命令；iOS重型模拟器测试暂时错开。
- 新证据：[App](tailscale-integration/evidence/2026-09-19-app.md)、[Web](tailscale-integration/evidence/2026-09-19-web.md)、[iOS正式archive](tailscale-integration/evidence/2026-09-19-ios-product.md)、[P4架构准备](tailscale-integration/P4_WEB_HOSTING_PREPARATION.md)。模拟器测试不替代真机声音、锁屏、VPN共存及账户授权。
- 26.2端口冲突测试发现Darwin的Java INET ServerSocketChannel默认SO_REUSEADDR=true，允许IPv4通配地址与已有特定地址监听并存。独立Java25探针已复现；预检查显式禁用地址复用，正在重跑完整构建。没有删除或放宽失败断言。


### 2026-09-19 26.2新包与 Android 恢复

- 26.2 `spotlessApply build`成功，52项测试、零失败/错误/跳过。新JAR SHA `2f27b3281fd28b76409ae6f4f93891da786017607d02944496abb3ee560b280a`，含当前Web bundle和四平台hash核验helper。已原子替换Prism `ImagineFun Add-Ons`内同名JAR；运行中的游戏仍加载旧包，不能当作新包实测。
- DebugBridge session control仍为disabled。遵守`mcdev://guides/dev-loop`门槛，已请用户在方便时开启配置并重启一次；未绕过该开关。当前新包现场重测等待这项操作。P3只读预检已完成，尚未开始实际移植。
- Android启动日志`Showing crashdialog to get consent`后展示的是旧dump，因此此前看到的free_ram=169与swiftshader启动参数不能归给本轮。仅对本次模拟器禁用crash上报和metrics提示后约19秒启动，API36 ARM64两项原生integration通过，全量Flutter150项通过。使用adb emu kill正常退出，无qemu残留；无新OOM/App fatal证据。
- Android构建链发现新问题：CI没有构建.so，CMake静默降级空JNI库。已接入依赖构建、改为缺库明确失败；重建两个ABI并加入UserLogf静默补丁，构建不再清理源码缓存。新库常规APK构建及两ABI哈希验证通过，最终库ARM64模拟器2项集成再次通过。详见[原生构建证据](tailscale-integration/evidence/2026-09-19-android-build.md)与[26.2产物](tailscale-integration/evidence/2026-09-19-integration.json)。
- iOS正式Release已完成独立clean build和严格codesign验证，Simulator RunnerTests为18通过、0失败、1跳过（需要显式启用真实账户网络的计时项）；未覆盖安装真实iPhone。最终正式archive来源和hash见iOS产品证据。


### 2026-09-19 音频并发修复

- 实际聊天链接不会等待connect完成，首个WebView启动期间连续链接可能并发创建播放器。两个音频服务新增串行会话操作、活跃同链接复用、初始化幂等和失败清理；不改变原园区网页播放协议。
- 监测只允许一个排队/运行任务，避免后台慢响应造成无限积压；断开同步撤销活跃状态，旧恢复/监测返回后重新检查状态，不能重新导航或上报连接。监测异常作为可恢复错误处理，下一周期仍能工作。
- 服务层可控WebView测试覆盖重复初始化、延迟恢复遇断开、同链接失败重试、周期检查异常恢复；连同队列测试8项通过。真正锁屏、音频焦点和两个园区服务器仍需设备验收。详见[音频证据](tailscale-integration/evidence/2026-09-19-audio.md)。


### 2026-09-19 最终自动化汇总（仍不含未授权的真实账号测试）

- 音频修复后的全量Flutter测试158项通过；最终analyze无问题，正式iOS Release构建及严格签名校验通过。Android最终APK双ABI/manifest哈希及所有ARM64 native库16KB ELF对齐验证通过，已加入CI；缺ABI、缺JNI和错误哈希负例均被拒绝。
- 补充本地隔离控制面/真实tsnet数据转发测试，以及模拟器系统通知实际状态验证，继续推进不依赖用户账户的验收。不会把本地测试控制面当作公共Tailscale登录或真实跨设备结果。


### 2026-09-19 追加回归发现：快速重启与生产 helper 状态

- 原52项通过后增加真实TCP关闭场景，发现SO_REUSEADDR=false预检查会把TIME_WAIT误判为仍有监听，导致快速重启不能保留原端口。独立Java25探针与新增JUnit均先复现失败，正在改为保留reuse并检查活跃接口的具体地址及通配地址；不以原52项绿掩盖新回归。
- 本机隔离testcontrol+DERP/STUN测试从自定义tsnet适配器推进到生产backend.NewTsnet，发现listening事件缺少TailnetIP/NodeID。自定义适配器通过不能代表生产watch/状态转换已通过；生产路径失败已记录，正在最小修复后重测。
- 最终音频代码的iOS正式Release构建44.7秒成功，严格codesign校验退出0；Runner和Dart framework的SHA记录在[正式包元数据](tailscale-integration/evidence/2026-09-19-ios-formal-release.json)。未替换真实手机上现有诊断包。


### 2026-09-19 两项追加回归已修复并重新打包

- 端口预检查现按活跃本地具体地址和通配地址验证，并保留reuse以允许TIME_WAIT后的重启。新增IPv4特定地址/通配地址、IPv6监听冲突和快速重启场景均通过；26.2全量55项测试，无失败/跳过。新JAR SHA `1a43affd0d0c86f1c11aa10bd39ca92c0372e738abf555c4f2a5458e2777db5c`，已经替换实例内产物，仍待游戏重启。
- 生产helper在Running通知缺身份时补一次本地状态查询；本机隔离测试现直接运行生产backend、Engine和forward.Proxy，验证真实TCP字节往返、stop、相同state目录重启后node ID/IP保持和shutdown。定向、race、全量、vet及四平台重建通过，CI已加入隔离控制面race测试；无用户账户或真实tailnet参与。详见[helper证据](tailscale-integration/evidence/2026-09-19-helper-hermetic.md)。
- Android系统通知取证已经完成：实际系统记录确认静音标志、固定ID倒计时更新、同ID定时替换与取消后移除。`-no-audio`模拟器不代表物理声音或锁屏验收；夹具47秒通过，取证和命令见[通知证据](tailscale-integration/evidence/2026-09-19-notifications.md)。
- helper脚本现统一选择满足go.mod的Go工具链，避免本机PATH旧Go1.19使常规部署失败。模拟旧PATH构建成功且host二进制hash与之前一致；明确指定旧Go则报可操作错误。不改系统PATH或全局Go设置。
- Android首次登录还在补自动弹页契约：Dart界面等待原生自动打开，而Android旧插件只在显式login调用中打开；正在修复及离线验证，尚不标为Android登录流程完成。


### 2026-09-19 发行重建文档与登录取消复审

- README已修正浏览器安全上下文说明与构建顺序：先生成web/helper再构建26.2，Android先生成双ABI库；其余版本不冒称已包含26.2新能力。音频文档按实际串行队列、可恢复监测异常及终止分支重写，明确Android尚无媒体播放前台服务，不能把旧示例当作现状。
- iOS原生VERSION与重建README加入窄范围忽略例外，archive/src缓存继续忽略。CI增加macOS ARM64正式archive重建与无签名Release编译；Android明确JDK21并加入原生登录生命周期JUnit。YAML/脚本本地检查不等于远端workflow已运行，本轮未push或触发Actions。Runner选择依据[GitHub官方说明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)及[macOS 26镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)。
- Android自动AuthURL打开初版通过编译后，复审抓出正常stop误发failed、旧start取新generation、UI线程读取native快照与浏览器启动异常未捕获。修复后继续检查取消代次、重复打开及失败可重试；曾有两项原生测试未先设置正确generation而未真正排队，已纠正夹具并断言实际排队后再取消，不将早先假阳性作为证据。
- Dart登录sheet的系统返回/下滑/遮罩关闭原先不会native cancel；现所有取消型关闭统一取消一次，选中peer则保留节点。取消期间异步start/status/logout返回不继续操作已关闭sheet。新增用例已通过，最终合并测试和产物验证待以下后续记录。


### 2026-09-19 登录取消与错误处理最终构建

- Flutter登录sheet新增取消与错误展示回归后，全量162项通过，analyze无问题。Android Kotlin的6项真实排队回归通过，覆盖取消/销毁后不打开、自动去重、显式重开及打开失败后提示保留；CI已接入。原生emit在IO取快照，UI发送前核对代次；正常停止不误报failed。证据见[Android登录](tailscale-integration/evidence/2026-09-19-android-authurl.md)。
- 正式iOS Release再次构建27.3秒成功，codesign严格验证退出0；原始archive不变、Dart与Runner新hash见[正式包元数据](tailscale-integration/evidence/2026-09-19-ios-formal-release.json)。没有安装/触碰睡眠中的真实iPhone。
- Android正式入口debug APK构建12.3秒成功，双ABI/hash/ARM64 ELF校验通过；已另存`outputs/roadmap-2026-09-19-login/MonkeyCraft-1.4.2-11-debug.apk`以避免之后集成夹具替换构建目录，SHA与体积见[APK元数据](tailscale-integration/evidence/2026-09-19-android-final-apk.json)。不是Play签名release或商店发布物。
- Android原生集成夹具新增stop后EventChannel必须stopped、不得failed的确定性断言；等待Chrome模拟器测试完成后运行，不能先标通过。


### 2026-09-19 本轮收口状态

- Android最终插件API36 ARM64两个集成场景通过，新增EventChannel断言实测确认stop发送stopped、没有failed，重复stop保持正确状态；模拟器已正常关机。该集成启动真实native库，但没有本人账户登录、peer拨号或实际VPN混合验收。
- Android模拟器Chrome133在localhost安全上下文完成回放H.264解码、横竖屏尺寸上报、触控W按下及切到系统设置后释放。没有解码错误；不是物理手机，且未覆盖Android GUI留黑点击、声音、锁屏或公网端到端。Vite/replay、端口映射、测试开关与模拟器均已清理，详见[Web证据末节](tailscale-integration/evidence/2026-09-19-web.md)。
- 当前可审阅成果均保留主checkout；没有commit、push、PR、worktree或生产发布。此前用户WindowMixin/mixins、exports/outputs和web-tailscale探索未被清理；本轮APK仅写入新建的专用outputs子目录。
- 26.2构建JAR与Prism目标JAR的SHA再次核对一致，游戏PID仍为原进程且session control关闭，因此新包现场验收仍等待用户一次重启。P3仅完成适配预检，未开始其他版本的源码移植；P4仅完成现有成果核对和架构准备，未擅自选择/部署。
- 下一步仍按顶部最短验收顺序推进：一次26.2重启→新包实际浏览器/App回归→本人Tailscale授权及混合连接→逐版本移植。真实手机声音、锁屏、音频和VPN共存列为明确待验收，不以现有自动化完成代替。


### 2026-09-19 继续补齐可独立完成的移动端视频验收

- 本次续轮重新检查：原Minecraft进程23404仍在，session_control_enabled仍为false；没有新包重启证据。上一轮有实际代码修复和自动化进展，本轮继续做不依赖该门槛的验收，没有把静态配置当作正在等待的后台作业。
- Android Chrome现在通过实际页面聊天打开回放GUI；横竖屏分别验证留黑触摸不产生SCREEN_CLICK、画面中心只产生一条正确归一化坐标。证据已追加[Web记录](tailscale-integration/evidence/2026-09-19-web.md)。
- Android新增可重复的生产视频链路集成夹具：真实StreamProxy WebSocket、SessionController、HardwareH264Decoder和VideoSurface/Texture。每轮原生decodedFrames至少5且继续增长；退出卸载Texture、stop与dispose后native stats为空，再连接重新解码。首次input8/decoded6/dropped1，重连input8/decoded7/dropped0，360×640；1项实测通过。详见[Android视频证据](tailscale-integration/evidence/2026-09-19-android-video.md)。这不是完整游戏UI、真机硬解或真实Minecraft链路验收。
- Android测试服务、reverse与AVD已正常清理；接着在现有iOS模拟器验证相同生产视频路径，真实iPhone保持不动。iOS的decoding字段表示当前队列是否正在处理，与Android持续激活标志含义不同；跨平台共同验收以实际解码输出、尺寸、计数增长和释放为准。结果待实测记录。


### 2026-09-19 iOS视频补测与当前外部门槛

- 跨平台夹具现为`integration_test/native_stream_h264_replay_test.dart`。iOS26.5 Workbench iPhone16模拟器实跑1项通过：两次连接均input6/decoded6/dropped0、360×640，实际VideoToolbox计数持续增长；卸载Texture并释放后native stats为空，再次连接成功。初次新夹具漏foundation导入编译失败已修复；未更改生产解码逻辑。详见[iOS视频证据](tailscale-integration/evidence/2026-09-19-ios-video.md)。
- 根代理核对模拟器全部关闭、ADB无设备、回放9601无监听；新夹具格式、静态检查与diff检查通过。没有把iOS模拟器标为真实iPhone，没有因共用夹具改名而虚构额外Android运行。
- 本续轮产生新集成夹具与Android/iOS视频、Android Chrome GUI映射的实际证据，属于进展；目标保持完整且未标完成。仍需用户完成一次26.2实例重启和本人账户授权，才能继续新包现场、混合连接与其后的P3。原有已确认产品方向、禁止提交/发布和主checkout约束保持。


### 2026-09-19 阻塞审查与目标状态

- 上一目标轮为进展：新增跨平台原生视频回放夹具，iOS/Android解码、释放与重连，以及Android Chrome GUI留黑映射均取得实际模拟器证据。
- 本轮重新读取权威状态：原Minecraft PID23404仍存在（9月18日22:23:46启动）、DebugBridge session_control_enabled=false；构建JAR和Prism目标JAR均匹配最新记录hash。iOS模拟器无Booted设备、ADB无设备，已完成测试均已清理；不存在仍需等待的测试作业。
- 根代理与独立子代理按完整路线检查剩余工作，确认需要新26.2实际运行、个人Tailscale授权、真实手机或P4架构选择。P3继续遵守先26.2完整验收的用户顺序；远端CI未经push不触发。没有用重复构建或扩大无关范围代替这些门槛。
- 同一外部阻塞已连续三个目标轮存在，本轮没有进一步独立推进条件，因此将目标设为blocked而非complete或paused。代码、证据和待办保留，用户重启/授权后从当前状态恢复；没有提交、推送、PR或生产发布。


### 2026-09-19 用户重启后恢复最终JAR现场验收

- 用户确认已重启；DebugBridge连接确认26.2、正确ImagineFun Add-Ons目录、session control已启用，实际游戏内快照正常。端口9600由新进程99326监听；构建与实例JAR继续匹配SHA `1a43affd0d0c86f1c11aa10bd39ca92c0372e738abf555c4f2a5458e2777db5c`。
- 新包HTTPS/WSS普通场景与10分钟持续测试已启动，结果待运行完成。首次启动测试因5173已有本仓库Vite而拒绝；确认服务归属后使用显式复用，不结束已有服务。密码仅由本地配置注入进程，不写证据。

- 正式iOS Runner SHA匹配当前发布元数据，严格签名有效；devicectl对真实iPhone覆盖安装成功并回读1.4.2(11)。未卸载、手动结束或启动App。已请用户在正式包完成本人Tailscale授权后停于设备列表，暂不抢占浏览器持续测试的唯一控制连接。
- 新JAR实际HTTPS返回HTML与JS均200，JS SHA与当前web/dist逐字节一致；普通真实浏览器场景4.1秒通过（HMAC连接、解码>20、err=0、背包打开/关闭）。10分钟持续场景仍运行中。

- 子代理深入Java helper生命周期发现：stop后迟到authRequired可能仍弹页，打开浏览器失败提示可被状态轮询覆盖。首版修复的离线定向测试通过，但根代理对照生产Engine时发现fake错误地允许重复start返回AuthURL（真实返回ALREADY_STARTED），另logout失效代次会吞结果。该首版尚不能发布，正在修正真实协议契约及logout/更换端口回归；当前运行中的JAR未改变，浏览器soak继续。
- 26.1仅补JDK25现状基线：8秒BUILD SUCCESSFUL，未移植源码或部署；本地反编译确认26.2 Gui.setScreen不能原搬到26.1，保持既有MinecraftMixin路径。

- 新增真实游戏阻断证据：DebugBridge在实际26.2 JVM读取 `java.awt.headless=true`，`Desktop.isDesktopSupported=false`、`BROWSE=false`。当前PC helper生产登录实现依赖AWT Desktop，在该真实启动环境无法打开授权页；先前fake loginOpener测试不能覆盖它。正在核对本地Minecraft平台打开接口并修正，未把helper编译成功等同真实登录完成。

- 当前运行JAR真实HTTPS普通场景及10分钟持续/四次resize全部通过（2项，10.1分钟，日志 `/tmp/monkeycraft-26.2-final-live.log`）。游戏内按键状态核对：浏览器Shift false→true，合成blur后false；真实服务stop/start165.336ms仍使用9600，按键立即释放。
- 快速重启实测发现新的Web回归：底层HMAC连接与视频发送已自动恢复，但UI退回登录、`.debug`消失，30秒断言失败。已定位controller先发布closed→idle、随后reconnecting；App信号effect看到瞬间idle就切登录页。正在补真实浏览器重连回归并修复，不能把10分钟连接稳定等同重启恢复已通过。

- 修复后新JAR SHA `249a06108fe1b286e37bc4c0630d71afdc98277c45cd6e92563ac7c7f84355c5`，61项Java测试全过；包含`index-DhSuvO0A.js`和无AWT的SystemBrowserOpener。经原子替换后使用已启用的官方DebugBridge关机/Prism启动流程加载，PID18533，重新加入同一ImagineFun。
- 新包实际HTTPS JS与构建逐字节一致。服务再次stop/start165.230ms保持9600，这次网页保持stream并自动回到connected，解码帧110→166→239持续增长、err=0；修前UI回登录故障已在同一真实场景复测通过。随后实际静音NUDGE横幅出现，倒计时Validation A→B更新与取消完成；该测试不代表物理提示音或手机系统通知。
- iOS模拟器直接连此前26.2 JAR完成实际HMAC、原生VideoToolbox连续帧与SessionController重连（两轮8帧，360×640）。凭证经一次性loopback运行时配置传入，没有编译进应用；临时文件与服务均清理，详见[iOS实际LAN](tailscale-integration/evidence/2026-09-19-ios-live.md)。

- 26.2现场核心回归后开始26.1实际增量移植；共享的个人账户/物理设备感知验收仍明确待测。按用户允许使用模拟器与继续独立工作的指示，先做不依赖这些外部条件的版本代码工作，不宣称双端内嵌产品已经完成。


### 2026-09-19 公共tailnet与真实iPhone双端内嵌

- PC helper成功进入running/listening，用户完成本人授权；iPhone正式Release也已完成授权。首次手机选到电脑系统节点，实际socket确认手机内嵌→电脑系统Tailscale；随后用户选择名称准确为`monkeycraft`的电脑内嵌节点。
- 双内嵌实际Java连接为loopback，另一端由helper PID19215持有，HMAC成功、streaming=true，490×960视频帧应答正常；用户明确反馈“画面正常，可以继续”。这是实机初连证据，尚不替代重启身份、切网、强制中继或长时稳定性。
- 用户反馈电脑多次弹出授权页，已修复同一helper重复AuthURL自动打开：相同URL仅自动打开一次，显式重开仍有效。新增生产一致fake回归后62项Java测试通过，新包SHA `1c0a90cb652e6d4316e765b651ccb96691905990b91cab459e1eddf08d0d1e3d`；暂未替换运行游戏，以保持手机验收。另补实际端口传入HTTPS入口探测，后续构建单独记录。
- 最新Web完整回归139单测、Chromium18与WebKit18均通过，各浏览器两个真实场景默认跳过；WebKit运行日志`/tmp/monkeycraft-web-runtime-fixes-webkit.log`。Playwright WebKit不代表真实iPhone Safari。
- 首条真实iPhone静音NUDGE发送时游戏仍connected/streaming；用户反馈前台没有看到提醒。已记为失败观察，正在复发并核对权限/通知处理，不标静音通知通过。详见[iPhone双内嵌证据](tailscale-integration/evidence/2026-09-19-ios-dual-embedded.md)。


### 2026-09-19 真机定位即时通知首次授权缺口

- 两次前台静音NUDGE均未显示；用户读取App设置为`notification permission not requested yet`。代码证实NUDGE未请求权限，只有定时路径请求。已补即时授权门控、并发请求共享、拒绝后可重试，定向9项通过；首次授权新包尚待安装验证。
- 当前正式包用定时A触发系统授权后，用户确认静音03正常且只有更新后的B；有声05只响一次，取消后倒计时消失。中间有声04发送时连接断开，作为无效发送记录，不计提醒失败或成功。90秒本地锁屏到点待观察。
- 26.2实际端口提示修复最终构建62/0/0/0通过，新JAR SHA `837404d20f7dd7d8f8428a811fffde0c0d7c58c2d3d8142da1d8b60200724d26`；运行中JAR仍为249a，未中断手机验收。
- 26.1、1.21.11、1.19首轮移植均构建成功；根代理比较四树helper生命周期/浏览器打开/snapshot源码哈希一致，Java17提取适配单独保留。交叉检查发现旧版本配对来源未限制到现有26.2允许的范围，正逐版本补齐并重测，不用首轮56项覆盖后续修复结果。


### 2026-09-19 锁屏与电脑身份重启通过

- 用户确认90秒本地倒计时锁屏可见、到点只响一次并显示提醒；解锁后游戏画面自动恢复，无需重新登录Tailscale，随后主动退出连接。实时后台消息与已安排本地通知仍区分。
- 在无手机连接后，启用与Mod正常登录按钮一致的embeddedTailscaleEnabled持久开关，原子部署最终837404 JAR，经DebugBridge退出旧游戏18533；shell确认其helper19215也已退出。Prism重启后helper自动running/listening，IP保持100.82.132.32，nodeId的String.hashCode前后均1148163683，无新登录要求。随后重新进入同ImagineFun，实际游戏身份恢复通过。
- 26.1/1.19最终配对来源补丁后各57项通过；1.21.11同样57项通过。所有补丁均保留配对/HMAC及单客户端限制；其他版本尚未声称真实游戏通过。


### 2026-09-19 四版本产物独立校验

根代理读取四个最终JAR，确认各自包含网页、LICENSE、darwin-amd64/darwin-arm64/linux-amd64/windows-amd64 helper，并逐一重新计算二进制SHA与体积匹配manifest。26.2为62项，其他三个版本各57项，均0失败/错误/跳过。产物SHA和测试汇总见[四版本产物清单](tailscale-integration/evidence/2026-09-19-four-mod-artifacts.json)。这不代表其它OS或其它Minecraft实例已经运行。26.1等实例DebugBridge会话控制默认关闭，已向用户提出针对三个测试实例的具体授权问题；没有绕过该控制。


### 2026-09-19 移动端后续修复与审核边界

- 新增即时提醒授权的完整回归、Live Activity串行初始化/创建/更新/取消、同截止时间内容更新和重复初始化保护。定向20项通过；真实手机前一版已完成感知验收，新代码仍须完整构建。
- 因实机设备列表只能显示名字、用户误选系统节点，补显示已有snapshot中的tailnet地址，IPv4优先，保留nodeId身份/选择契约；同名节点选择回归及模型共14项通过。没有根据名字猜测系统/内嵌类型。
- 音频后台配置首版代码审查发现200ms超时可能在原生迟到启动后留下无法释放的session/service，已退回修正为可测试的串行租约；此前音频测试挂起、全量测试在169项阶段主动中断并有最终化错误，不记作全量通过。后续须以修正后完整重跑为准。
- 已向用户提出P4的A静态直连/B代理/C浏览器WASM架构选择，明确选择仅授权本地实现和验证，不包含生产部署/付费。尚无答复，不默认选定A。


### P4 域名状态更新

用户说明候选域名可能尚未购买或不可用，将自行确认。`www.monkeycraft.com`继续仅作为候选名称，本地预览可独立推进；未购买域名、修改DNS或假定用户已选择架构。等待架构选择与域名确认的同时，继续当前客户端/版本验收。


### 2026-09-19 最新26.2持续连接与GitHub Pages方向

- 最新837404 JAR实际HTTPS/WSS普通场景及10分钟/四次resize连续解码全部通过（2项，10.2分钟，err=0），日志`/tmp/monkeycraft-26.2-837404-live-soak.log`。
- 补测本机系统Tailscale→PC内嵌helper：经utun7到100.82.132.32，HMAC成功、20秒内6次HEARTBEAT_ACK；0视频帧经实时状态确认为ImagineFun乘坐Disneyland Railroad而自动HIBERNATING。首个15秒探针因未考虑休眠而未达视频断言，第二次明确捕获休眠状态；不宣称该探针视频通过。Android真实视频排在自然休眠结束之后，期间继续原生音频及正式构建。
- 用户倾向GitHub Pages，已按静态入口+现有HTTPS/WSS直连方向开始本地支持；保留Mod根路径产物，Pages使用独立子路径产物与手动工作流，默认仅构建，未发布。域名仍待用户确认。


### 2026-09-19 Pages 复核与后台媒体生命周期

- Pages 复核修复了输入服务器地址后仍保留上一目标密码的问题；凭证以规范 WebSocket URL（保留路径）和 keyId 隔离，旧条目仅按已记录 lastServer 迁移，混合条目按 lastSeen 取最新。新增浏览器用例验证换目标后替换/清空密码。
- 最新 TypeScript、Biome、146 项 Web 单元测试、Mod 构建下 Chromium 19 项和 WebKit 19 项通过；Pages 项目子路径下18项回放/凭证测试通过（4项明确跳过），根路径专项2项通过。日志：`/tmp/monkeycraft-web-final-webkit.log`、`/tmp/monkeycraft-pages-final-browser.log`、`/tmp/monkeycraft-pages-root-browser.log`。上述回放测试不连接真实Minecraft。
- Pages工作流保持只手动触发且默认不发布；pnpm先安装再配置缓存，所有合法base（包括根路径）都运行路径与凭证隔离专项。未执行GitHub远端工作流、修改Pages设置或DNS。
- Flutter全量175项与完整analyze通过；音频测试静态队列跨fakeAsync环境的挂起已通过每次测试重建队列解决，未用生产超时绕过。
- Android API36 ARM64模拟器媒体服务夹具：两次start保持前台服务、类型mediaPlayback、通知ID990002一条；两次stop后服务与通知均清零，夹具退出0。首轮未授通知权限时通知0导致外部断言失败（夹具本身0）；允许模拟器通知后第二轮通过。证据：[原生媒体服务状态](tailscale-integration/evidence/2026-09-19-audio-native.json)。它不证明真实园区网页在手机后台持续播放。


### 最终安装与打包中发现的问题（继续处理中）

- iOS最新正式Release和Android Release APK均已构建归档到`outputs/roadmap-2026-09-19-final/`；Android签名为开发签名，尚非商店发布验收。iOS外层严格codesign通过后实际覆盖安装被iOS拒绝：`objective_c.framework`的可执行签名无效（0xe8008014）。原有1.4.2(11)仍可由devicectl查到；未卸载、未清空身份。正在检查嵌套framework与Flutter原生assets签名，不记装机成功。日志`/tmp/monkeycraft-ios-final-device-install.log`。
- 四Mod最新Web资源重建时，26.2、26.1、1.21.11通过；1.19的`logoutCancelsAStartQueuedBeforeTheHelperExists`在57项中失败1项（预期stopped但实际starting）。测试没有确保start任务尚未开始，根代理与子代理正在区分fixture调度假设和生产logout语义；不按既有另一项flaky说明直接跳过。

- iOS签名失败继续定位：归档中`objective_c.framework`为x86_64+arm64、LC_BUILD_VERSION platform 7（模拟器）、adhoc签名；其余嵌套framework为device arm64并由开发证书签名。与共享native_assets生成目录的旧模拟器产物完全一致。此轮SDK调用已串行，不能仅归咎于并发；正在检查增量构建缓存并加入产物平台校验。原始失败包明确标为INVALID，重建前不作为可交付设备包。


### 2026-09-19 最新实际验收收敛

- Pages静态产物跨origin连接真实WSS，错误密码拒绝、正确密码视频、保存凭证后二次连接通过；最新097d40 Mod上1项通过。它是localhost安全上下文，不是公开GitHub Pages域名或真实手机浏览器。详见[Pages证据](tailscale-integration/evidence/2026-09-19-pages.md)。
- Android API36 ARM64模拟器到真实26.2 LAN：首次input13/decoded8、重连input10/decoded9，360×640，解码计数增长，释放后native stats为空，1项通过。详见[真实Mod链路](tailscale-integration/evidence/2026-09-19-android-live.md)。
- 系统Tailscale→PC内嵌helper在园区休眠结束后再次探测：HMAC成功，20秒接收150帧/1,742,432字节、360×640、6次心跳，state ACTIVE。属于同机系统路由经utun7到内嵌节点的数据面，不声称该脚本做了解码或跨设备验证。
- 1.19失败定位为queued-start测试未控制调度；加入executor/latch使前提确定，保留已启动helper必须完成logout ACK的语义。另外IOException退出同步块后可能晚于stop写snapshot，四树加入generation guard。四树完整构建重跑通过：26.2 62项、其余各57项；最终10个Web文件、四平台helper manifest/hash/size/sidecar和许可证全部核验。
- 26.2最新JAR `097d40d51eaef9452d7f464b0b491b60f7a8a34ab6d4a816f56ee817372b84b5` 已原子部署并正常退出旧进程/旧helper，Prism重新启动游戏70132/helper70207，身份fingerprint仍1148163683，无新登录，已回到同一ImagineFun。最新Mod提供的JS与当前dist字节匹配；真实HTTPS/WSS视频/库存操作1项通过。十分钟持续证据仍归之前837404，本次没有重复冒称新包十分钟。
- iOS clean重建设备包后，所有嵌套framework平台/架构/同Team签名均通过；最新包已成功覆盖安装，devicectl再次确认1.4.2(11)。新增设备构建入口强制clean→pubget→release→嵌套校验，避免模拟器native asset缓存混入设备包。没有卸载/清数据/自动启动手机App；新包真机感知仍待复验。
- 正式AndroidRelease冷启动成功后，首页验收发现内嵌入口仍受iOS-only UI条件限制。原生组件通过不代表产品入口完整，已单列修复并补首页回归，正在重建验证。


### Android正式入口最终复验

- iOS-only首页条件已修复。完整Flutter176项与analyze通过，新APK `eca32d4d158b45e2ac0c285d011384a8a68a2b05e055216a0f7e6c109c2f253d` 通过双ABI、manifest、签名与16KB校验，已在Android模拟器覆盖安装/冷启动。实际点击首页按钮后打开Chrome的 `login.tailscale.com` 登录页，可见Sign in，未保存AuthURL或替用户授权。
- 已向用户发出本人账户登录步骤，授权后继续Android混合/双内嵌与身份恢复。原有其它实例DebugBridge控制问题仍待用户回应；当前不绕过工具的会话控制开关。无提交、推送、PR、生产部署、域名购买或付费资源。


### 2026-09-19 OpenAudio真实链接与双模拟器验证

- 真实26.2聊天链接 `https://session.openaudiomc.net#opaque` 暴露旧前缀规则漏识别并外部打开；现改为共享URI精确host校验，聊天点击路由回归通过，完整Flutter179项与analyze通过。证据见[OpenAudio链接与会话验证](tailscale-integration/evidence/2026-09-19-audio-link.md)。
- 此前两次45秒未连接使用了PC仍持有会话的旧链接；不推断精确token生命周期。iOS 26.5与独立Android API36/ARM64模拟器5556均以fresh会话完成连接、调用softRefresh后保持连接并断开清理，页面均检测到HTML媒体1/playing1。Android 5556使用`-no-audio`，两者都不代表真机可听、锁屏或后台播放。
- 含该修复的iOS包clean构建47.8秒、通过原生平台/签名验证并成功覆盖安装，readback为1.4.2 (11)。Android新Release `e843496ea0501e5d7c0f835a02d81acacc471c425762c3e99201bd0081cc12ab` 已归档并通过双ABI/16KB/签名校验，随后安装到隔离5556、冷启动并确认首页与Connect按钮，未点击登录。
- PC已恢复active/connected（音量0，未改持久配置）；5556已正常关闭，5554保留旧`eca32d4…`包及等待授权的Chrome状态。剩余门槛为iOS/Android真机的实际声音、锁屏与后台表现，以及用户本人Android账户授权；不自动创建账户或节点。


### 2026-09-19 Android 正式界面与后台现场回归

- GitHub Pages继续作为首选；默认项目地址可以先用，自定义域名可选。已修正README/旧Web计划中易被理解为本轮已发布或工作流已删除的描述；无远端操作。
- 正式 `e843496…` Android APK在独立5556通过实际GUI连接26.2，通知权限弹窗实际Allow，聊天fresh链接留在App内并显示OpenAudio已连接。真实按Home后至少53.3秒音频前台服务存活，返回时游戏自动重连、重新打开设置仍显示音频连接；显式Disconnect后服务与通知消失。PC原音频已恢复active/connected、音量0。该模拟器无声音输出，不等于真机可听或连续播放。见[正式GUI证据](tailscale-integration/evidence/2026-09-19-android-production-lifecycle.md)。
- 倒计时A→B同截止时间更新、相同B去重、取消显示通过；随后新倒计时不显示，系统日志明确为App已积压50条通知而拒绝新通知。源头是外部ImagineMoreFun插件正常周期提醒，App无限递增即时通知ID导致配额耗尽；不关闭用户功能，正在修复保留数量与旧通知迁移。
- 新安装只有通知权限，未授权精确闹钟；实际不精确排程窗口约98秒，界面缺少说明。正在加入用户主动授权入口、返回刷新及当前未来提醒的重新排程，保留未授权降级；未经复测不声明到点精度或声音通过。


### 2026-09-19 Android 通知缺陷修复闭环

- 即时提醒限制最新16条，并测试旧通知和插件重建；精确定时设置页提供延迟说明、用户主动授权和当前未来timer重排。完整Flutter188项/analyze、Android原生11项通过。
- 首次Release因生成注册文件引用不可用integration_test插件失败24.8秒；保留日志。顺序全量验证→clean→pubget→Release后54秒构建成功，新APK `f8bbc80a5c79843fedd79bed3757f2b9d800d8295befc546ee1b2f7753574f53` 的双ABI/16KB/签名通过。详见[修复与正式GUI证据](tailscale-integration/evidence/2026-09-19-android-notifications-runtime.md)。
- 新包实际Allow后，已有timer同截止时间从inexact变为window0；64条提醒后仅16条即时项，倒计时和音频不受损。Home后到点alert按设备时间+3ms创建，回App未重复；后续A→B/重复/取消全过，实际Sneak按下→Home释放也通过。模拟器无声音输出，不扩大到可听声或真机结论。
- 显式退出后音频服务/通知及timer清空；PC园区音频已恢复，5556正常关闭，5554待本人授权的实例保留。旧通知在替换安装时被系统清空，因此旧版本迁移仅计原生策略单测，不冒称现场验收。

### 2026-09-19 Android Chrome、最终网页与 Mod 打包闭环

- 实际Android Chrome133在原生Allow后仍因旧`new Notification`构造器失败无法通知；改用有scope的Service Worker通知，Pages图标路径正确，用户手势内同时发起权限/音频解锁，注册/激活有等待上限。旧Flutter清理不再注销所有worker或删除同origin缓存。异步拒绝、静音切换和dispose后的回退声音都有单元覆盖。
- 实际Home后旧客户端会在后台断线并消耗重试后回登录；新客户端隐藏时保留重试预算，30,006ms采样间一直attempt=1，返回约1,052ms内连接和新增解码恢复。generation防护阻止显式退出/新连接受到旧retry影响。raw CDP touchStart确认SHIFT=true，原生Home后SHIFT=false；早期Playwright focus emulation探针不作为证据。
- Chrome系统通知已观察到silent=true/false和正确Pages图标；实际通知抽屉点击回到原游戏，旋转两次err0。无音频模拟器不代表可听声或锁屏可靠提醒。最终截图发现并修复提醒与工具栏重叠；界面只调整必要位置。
- 四树构建中的1.21.11 `immediateShutdownCancelsAQueuedStart` 首次失败已保留。根因是fixture未阻塞executor，名称所说的queued前提未成立；四树同步使用latch确定排队，不改生产shutdown。spotless与四树完整构建通过，test任务此次均实际执行：62/57/57/57。
- 新JAR各11个Web文件和四平台helper/manifest/sidecar/license校验通过；CSS修复前构建与失败尝试另存。最终26.2本地原子替换、正常退出旧70132/70207、Prism重启46058/46362并重入原服。内嵌身份不变，真实网页专项1项/5秒通过，PC园区音频active/connected，测试结束无控制客户端、SHIFT=false。
- 日志和截图位于`outputs/roadmap-2026-09-19-android-browser/`；完整方法、夹具失败与边界见[专项证据](tailscale-integration/evidence/2026-09-19-android-browser.md)。手动Pages工作流增加worker资源和重连专项，publish仍默认false；未运行远端workflow或部署。

### 2026-09-19 后续完成度核对与可继续事项

- 上一轮属于实际进展：网页修复、原生Chrome验证、四树构建/夹具修复和最终26.2重启。并非仅重复状态。
- 重新探测Android5554仍停留在Tailscale本人Sign in页。26.1的debugbridge配置仍关闭；初次仅按minecraft路径检查漏掉旧两实例，随后按各build-and-deploy脚本和实际目录复查：ImagineFun 1.21.11与Fabric 1.19的`.minecraft/config/debugbridge.json`均已开启session_control。现已备份并替换它们的旧MonkeyCraft JAR，保留其余mod；26.2最终十分钟测试完成后顺序启动验收，当前尚不声称旧版本运行通过。
- Firefox155.0已独立完成安全localhost+H.264回放解码（dec5/err0），聊天入口可用；未访问个人Firefox资料或真实游戏会话。见[Firefox证据](tailscale-integration/evidence/2026-09-19-firefox.md)。
- iOS出口合规技术核对发现旧文档仅系统网络/HMAC的依据已不适用于静态链接libtailscale/WireGuard的当前Runner。已更新旧文件并补[当前事实备忘](tailscale-integration/IOS_EXPORT_REVIEW.md)；未擅自更改plist答案、签名或做App Store申报，最终发布人评估仍待完成。
- 最终6fabc1网页重连逻辑发生了变化，因此补跑其独立十分钟持续/resize验证，并给现有soak加入非敏感调试样本日志；初次单行签名格式检查失败后已格式化并重新通过类型/格式检查，测试正在已确认存活的句柄8052运行。

- 最终包首次soak在约3.4分钟因测试浏览器关闭中断，140,005ms样本仍connected/dec1137/err0；没有证据认定产品崩溃，也不能计为十分钟通过。失败日志保留为`outputs/roadmap-2026-09-19-final-soak/live-browser-closed-attempt.log`，已启用仅浏览器进程诊断日志重跑，句柄68984。
- GitHub Pages本地项目路径追加真实Chromium不可达目标验证：5秒内错误可见、输入和Connect恢复、可修改地址重试；`ERR_NAME_NOT_RESOLVED`没有被伪装为成功。见[证据](tailscale-integration/evidence/2026-09-19-pages-unreachable.md)。未运行远程工作流或发布网页。
- 首次soak退出调查补充：并行探针曾在未核对父子进程/profile归属时终止PID49448；时间与原soak浏览器关闭相近，可能造成干扰。没有足够现场证据断言归属，不能把中断归因于产品；后续清理限定持有的browser.close或已核实的进程，重跑浏览器53379独立保留诊断。

### 2026-09-19 最终持续测试与旧版真实运行

- 最终6fabc1重跑2项通过；六个样本从1ms到600,032ms，解码22→4,786、cfg1→5、所有样本err0/link connected。首次浏览器关闭失败及可能的并行清理干扰独立保留；不与最终通过混淆。退出前无客户端、SHIFT=false、内嵌身份1148163683，游戏46058/helper46362均正常结束。
- 1.21.11（Java21.0.7，500105 JAR）在真实ImagineFun入服后普通live 1项通过，10分钟项明确跳过；实际SHIFT按住→关页释放，HTTP GET/HEAD及JS/CSS/worker一致。helper从stopped经ensureRunning到needsLogin，无错误、不调用login、不修改持久开关；游戏57735/helper58803退出。原配置SHA一致。首轮未等入服造成ConnectScreen退出断言失败；错误备份路径导致原log被覆盖，工具捕获的事实另存initial-attempt.json，详见[1.21.11证据](tailscale-integration/evidence/2026-09-19-1-21-11-runtime.md)。
- 1.19（Java17.0.15，a64bd9 JAR）首次直接连服触发现有ProxyServer未初始化按钮NPE；经正常多人游戏页面初始化后重试，服务器明确拒绝1.19并要求1.21+。未修改/移除代理Mod或其配置，改为新建独立Creative/Superflat世界（初记名称有误；实际为`MonkeyCraft acceptance 2026-09-1`）。在该世界完成live视频/背包、SHIFT释放、资源一致、helper needsLogin及游戏59347/helper61210正常退出；原MonkeyCraft配置SHA一致。详见[1.19证据](tailscale-integration/evidence/2026-09-19-1-19-runtime.md)。
- 上述两个helper探针只创建各实例自己的本地待登录状态，不复制26.2身份、不替用户授权；`embeddedTailscaleEnabled`仍按旧配置默认关闭。两个旧JAR备份与部署清单位于`outputs/roadmap-2026-09-19-version-runtime/`。本地验收世界保留供复验，没有覆盖旧世界。
- 已恢复常用26.2并重新进入mp.imaginefun.net，游戏61912/helper62015、同一内嵌IP和身份、无控制客户端/残留SHIFT。26.1的session_control_enabled重新读取仍false。未提交、推送、PR、发布或改DNS；`git diff --check`通过。
- 已通过异步问题请求26.1会话控制开关授权；依据是该实例当前DebugBridge配置关闭且工具要求开启才能自动进服/退出。收到授权前不修改该配置，现有26.2恢复状态保持。
- 恢复后进一步读取现有PC OpenAudioMcService：active=true、connected=true。结果追加到`restored-26.2.json`。

本轮持续与旧版浏览器命令均从`web/`运行，真实密码由本机实例配置在进程内读取，未写入日志：

```sh
MONKEYCRAFT_REUSE_DEV=1 MONKEYCRAFT_LIVE_URL=https://mac.tail977122.ts.net:8443/ MONKEYCRAFT_LIVE_SOAK=1 DEBUG=pw:browser PATH=/opt/homebrew/bin:$PATH node tools/run-live-test.ts
MONKEYCRAFT_CONFIG='/Users/cusgadmin/Library/Application Support/PrismLauncher/instances/ImagineFun/.minecraft/config/monkeycraft.json' MONKEYCRAFT_REUSE_DEV=1 MONKEYCRAFT_LIVE_URL=https://mac.tail977122.ts.net:8443/ PATH=/opt/homebrew/bin:$PATH node tools/run-live-test.ts
MONKEYCRAFT_CONFIG='/Users/cusgadmin/Library/Application Support/PrismLauncher/instances/Fabric 1.19/.minecraft/config/monkeycraft.json' MONKEYCRAFT_REUSE_DEV=1 MONKEYCRAFT_LIVE_URL=https://mac.tail977122.ts.net:8443/ PATH=/opt/homebrew/bin:$PATH node tools/run-live-test.ts
```

先用DebugBridge确认已入服/本地世界再运行普通live，不能让加载界面被误判为背包。该早期短测批次未开启旧版十分钟用例；后续 d42a65/dd3dd0 包已完成十分钟验证，见文末窗口与鼠标锁定复核。均不扩大为全平台或旧版双内嵌验收。

- 实体桌面Safari探测：Safari/safaridriver 26.6.2 (21624.5.1.11.3)，自有临时driver可启动，但新自动化session被HTTP500/session not created拒绝，明确要求Safari Settings → Developer → Allow remote automation。未修改偏好、未创建浏览器会话、未访问真实游戏；临时driver已退出。证据`outputs/roadmap-2026-09-19-safari-preflight/`。这不是Safari功能测试通过，须用户允许后继续。
- 38份本轮验收/主文档的62个本地Markdown链接检查通过；最新`git diff --check`通过。最短人工恢复步骤见[剩余验收步骤](tailscale-integration/REMAINING_ACCEPTANCE_STEPS.md)。

### 2026-09-19 过期提醒重放修复与正式包复验

- 旧f8 APK在强制深度IDLE时按截止+16ms提交提醒，普通恢复无重复；经正式GUI Disconnect→Connect后，服务端保留的过期deadline导致新协调器重建闹钟、同通知更新时间再次变化。保留现场JSON，未把静音系统记录解释成可听声音。
- 只改Dart通知协调器及其测试：权限前/后检查deadline，分别记录去重signature与真正成功排程的未来deadline；过期回放不重新排程、不误删已送达提醒，未来排程被过期更新替换时才取消。12项定向、192项完整Flutter测试和analyze通过；独立代理核对iOS接口与Live Activity路径。
- 新APK Release构建53.0秒，SHA `4f5a225b9d7a01b087fa573f6305a93de34aefbdf5a83c4fca6a88270cd355a7`；双ABI/manifest/ARM64 ELF16KB/zipalign16KB/v2签名通过。隔离5556覆盖安装保数据并回读相同SHA。在旧deadline下连接无新通知或闹钟；安装时系统已清旧通知，不能当作跨升级保留证据。
- 新未来deadline `1789767038139` 在强制深度IDLE中生成ID1于 `1789767038148`（+9ms）；回前台、正式GUI退出重连及再等约14秒，创建/更新时间均不变、无新闹钟；显式cancel全部清空。恢复deviceidle ACTIVE/ACTIVE，无电池模拟改动，关闭自有5556；5554未触碰。
- iOS共享修复已clean构建（Xcode48.5秒、48.3MB），归档后再次验证所有嵌套组件为arm64/iOS设备平台且同Team有效签名；devicectl覆盖安装成功、readback 1.4.2(11)。没有手动终止或启动手机App，不能将安装成功写成真机感知验收。
- 新产物在`outputs/roadmap-2026-09-19-expired-reminder/`，Flutter/Doze过程在`outputs/roadmap-2026-09-19-android-doze/`。Android/iOS产物清单保留previousBuilds。临时probe最初假定零通知仍有Notification List标题导致IndexError；修正为空列表后重新采集，这是取证工具失败，非产品失败。
- 独立iOS只读核对还列出既有边界：后台到点且无新状态时Live Activity可能停留00:00直到恢复/取消；权限拒绝分支可能重复查询；接口无法区分iOS延迟待投递和已送达请求。均未由本次修复引入，未冒称已在新包真机排除。
- 结束状态：真实26.2仍连接原服，helper running/listening及身份1148163683保留，无控制客户端、SHIFT=false、测试timer已清空。没有修改授权开关、提交、远程工作流、Pages/DNS或付费资源。用户GitHub Pages偏好继续作为P4首选。

本次使用的验证入口（APK在iOS clean之前归档）：

```sh
/Users/cusgadmin/if-local/flutter/bin/flutter test
/Users/cusgadmin/if-local/flutter/bin/flutter analyze
/Users/cusgadmin/if-local/flutter/bin/flutter build apk --release
python3 android/third_party/libtailscale/verify_apk.py <archived-apk>
zipalign -c -P 16 -v 4 <archived-apk>
apksigner verify --verbose <archived-apk>
adb -s emulator-5556 install -r <archived-apk>
FLUTTER_BIN=/Users/cusgadmin/if-local/flutter/bin/flutter bash tool/build_ios_device_release.sh
python3 tool/verify_ios_app.py <archived-Runner.app>
xcrun devicectl device install app --device <paired-device-id> <archived-Runner.app>
```

具体SHA、系统时间、采样、安装结果和平台边界见[过期提醒证据](tailscale-integration/evidence/2026-09-19-expired-reminder.md)及[机器可读结果](tailscale-integration/evidence/2026-09-19-expired-reminder.json)。

- 本阶段交付核对：39份文档的68个本地链接有效、所有本轮JSON可解析、归档Android APK与iOS Runner/App.framework哈希匹配最新清单，`git diff --check`通过。结果在`outputs/roadmap-2026-09-19-expired-reminder/final-validation.json`。新iOS包已装机但未启动，感知验收继续列待测。

## 旧版持续运行、窗口限帧与鼠标锁定复核（2026-09-19，后续批次）

- 1.21.11 修复前真实最小化将原版帧率限制由 30 降到 10；本地反编译确认该路径。移植既有 WindowMixin 后，实际原生窗口仍可最小化，但 streaming 时不再命中图标化 10 FPS 限制。请求 20 FPS 的真实十分钟/四次 resize 通过，600,031 ms、6,778 帧/错误 0；最小化区间实达 11.349 FPS，不声称达到请求的 20 FPS。
- 1.19 复用既有独立测试世界 `MonkeyCraft acceptance 2026-09-1`（此前文本误写了末尾 9），实际 600,030 ms、四次 resize、7,971 帧/错误 0。两个旧版均在结束后释放连接/Shift，正常退出，原配置 SHA-256 不变。ImagineFun 对 1.19 的最低版本限制仍保留。
- 两个长测分别对应 d42a65 与 dd3dd0 包，包含 PointerLock Promise 处理修复。并行复核又发现旧式 void 返回接口的晚到锁定边界，已完成清理与两浏览器/Pages重测；[最终产物与结果另列](tailscale-integration/evidence/2026-09-19-pointer-final.md)，不将这些长测归给不同哈希。详见[窗口与输入证据](tailscale-integration/evidence/2026-09-19-window-and-pointer.md)。
- Linux amd64 helper 在已有 arm64 Docker 根文件系统的翻译执行下完成 version、fake JSONL 生命周期，以及不带 fake 的真实 tsnet 后端离线初始化/needsLogin/status/stop/EOF，均 exit 0；无镜像下载、用户身份挂载、网络或遗留容器。这只补充 Linux 翻译执行证据，不等于原生 x86、Tailnet 连通或 Windows 验收。见[生产后端容器证据](tailscale-integration/evidence/2026-09-19-linux-helper-real-backend-container.md)。

### 步骤1完成前的独立工作收尾与外部验收门槛（历史）

最终补丁已完成构建、两浏览器回归、Pages专项、本地四JAR部署与26.2真实恢复；42份Markdown的71个本地链接、证据JSON、最终构建/部署/备份哈希和`git diff --check`通过。1.21.11/1.19最新仅含后续输入兼容修复的包已部署但未启动，前一包十分钟结果独立保留。当前可运行的常用现场为26.2，临时测试浏览器、预览与Linux容器已清理。

Android本人账户授权、26.1会话控制、真实手机声音/锁屏/后台音频、Safari授权以及公开Pages发布门槛在连续多个执行轮次中仍未解除；可独立推进的本轮修改与验证已经收尾。目标记录为等待外部条件的blocked，不标记产品路线完成，也不重复启动相同测试来替代缺失的真实验收。最短恢复动作见[剩余验收步骤](tailscale-integration/REMAINING_ACCEPTANCE_STEPS.md)。

### 用户步骤1前的DebugBridge核验（2026-09-19，只读）

用户所指 `~/if-local/debugbridge` 当前不存在；实际仓库为 `~/if-local/luabridge`，origin为use-ai-for-mc/debugbridge，main HEAD 9eb5052，已跟踪源码无未提交修改。26.1实例的 `debugbridge-26.1-2.1.0.jar` 与该仓库现有26.1构建完全相同，SHA-256 `b8bb941e7f98ae810d76b77e9cedce1e91409d4f882d8bfd296e070b81354363`，7,775,080字节，36个ZIP条目逐项一致。最新26.1源码变更2e4186d的标题页物品组件初始化（COMMON_ITEM_COMPONENTS / ITEM_NAME / ITEM_MODEL / Holder.direct）已在安装包字节码确认。源码文件mtime晚于JAR不能单独判定过期，故补做此项核对。只确认本机源码/产物，不声称已查询线上最新发布；没有重建、替换JAR、修改权限开关或操作游戏。证据在 `outputs/roadmap-2026-09-19-debugbridge-check/`。


## 用户完成步骤1后的26.1验收与旧版补测（2026-09-19）

- 26.1 DebugBridge会话控制读回true；本机已安装最新2a48ef6包，在Java25.0.1启动并进入原ImagineFun。实际HTTPS/WSS普通视频与十分钟用例2 passed / 10.1m。持续600,028ms、解码6,273帧、错误0，四次viewport变更、cfg最终6；请求20FPS，实达约10–11FPS，不能宣称达到20FPS。原生最小化区间平均10.02057FPS，WindowMixin按设计屏蔽iconified节流，恢复窗口后原生图标化归零。
- 26.1的11项Web资源HTTP下载逐字节一致；HEAD返回200、Content-Length1318、空body。按住Shift后直接关闭浏览器，服务端连接与Shift均释放。初次Playwright offline没有真正断开已建立WebSocket，保留为夹具局限；改为offline加服务端受控关闭连接后，断开释放、恢复重连、新帧解码及Shift不粘连通过。此结果不代表物理Wi-Fi/蜂窝切换。
- 26.1 helper从starting到needsLogin，生成一次登录页打开请求；本人授权未确认，未声称远端转发通过。正常退出时游戏53553/helper54131均结束。1.21.11最终b927c80包在真实ImagineFun、1.19最终e9df6d包在既有独立世界分别完成短测与真实Shift释放；各自正常退出。三个旧版配置SHA均与启动前一致，未覆盖用户配置。
- **验收漏洞与修复：** 旧live测试将通用SCREEN_STATE/screen-palette误当背包类型；已有暂停菜单时跳过E，单纯Escape关闭也会通过。截图复核发现1.19为Game Menu，另两版截图早于背包实际渲染。修复 `web/test/browser/live.spec.ts`：先关闭既有Screen、聚焦视频区域、始终发送E、等待重新打开及至少4个新解码帧，再截图。四版均重跑：26.2 5.9s、26.1 5.9s、1.21.11 6.0s、1.19 5.8s，各1 passed / 1 skipped（未请求重复十分钟）；逐张确认前三版ImagineFun背包、1.19创造物品栏。自动协议仍只有通用Screen状态，背包身份包含人工图像复核。原十分钟视频结果独立有效。
- TypeScript通过；Biome首轮仅格式差异，格式化后通过。此次只加强测试，未改发行产品代码或重建JAR，不把历史全套自动化算作再次执行。
- 所有实例均通过正常退出切换；最终恢复26.2游戏68918/helper68983，原服务器、内嵌100.82.132.32、身份指纹1148163683不变。最终无控制客户端且Shift=false，电脑音频active/connected。26.2运行时配置哈希有变化，认证会保存lastPhoneSeenAt；仅保存了旧哈希，不能据此严格断言只有该字段变化，因此没有写字节不变或回滚它。

复现：从`web/`用各实例的`MONKEYCRAFT_CONFIG`运行`MONKEYCRAFT_REUSE_DEV=1 MONKEYCRAFT_LIVE_URL=https://mac.tail977122.ts.net:8443/ PATH=/opt/homebrew/bin:$PATH node tools/run-live-test.ts`；26.1长测另设`MONKEYCRAFT_LIVE_SOAK=1 MONKEYCRAFT_LIVE_MAX_FPS=1`。密码仅从配置读入进程，不写入日志。输入探针为同一证据目录的`input-release-probe.mjs`与`reconnect-probe.mjs`。

原始日志、截图、JSON、进程样本及恢复状态在`outputs/roadmap-2026-09-19-26.1-acceptance/`。版本详情见[26.1](tailscale-integration/evidence/2026-09-19-26-1-runtime.md)、[1.21.11](tailscale-integration/evidence/2026-09-19-1-21-11-runtime.md)、[1.19](tailscale-integration/evidence/2026-09-19-1-19-runtime.md)。剩余门槛仍为本人内嵌节点授权、实体手机/跨网络与平台发布验收；GitHub Pages本地准备继续保留，未公开发布。


## GitHub Pages配置核验与桌面Safari首轮（2026-09-19）

- 用户已允许推进Pages配置；读取远端确认public/ADMIN、默认master、build_type=workflow、https_enforced=true、CNAME=null、部署环境只允许master。设置已符合目标，没有为制造改动而重复修改。公开`https://use-ai-for-mc.github.io/monkeycraft/`当前200，内容仍为旧Flutter网页；其旧flutter_service_worker.js已是自注销版本。新客户端尚未远程发布。
- Pages工作流为手动触发、publish默认false，build仅contents:read，deploy仅pages:write/id-token:write。六个Actions锁定到官方完整提交SHA。新build-provenance.json记录源码commit/dirty、工作流commit/hash、Actions run、Node、精确pnpm声明版本、lockfile hash和11个发布文件hash/大小。dirty工作树默认拒绝冒充源码提交；显式本地验证时写dirty=true/commit=null。
- 本轮实际执行：完整Web单元160通过；provenance最终3通过；typecheck/lint通过；Pages Chromium专项5通过/1因无头通知权限跳过。独立复算所有11个发布文件hash/大小一致，实例密码不在这些文件中。仅凭manifest不构成签名或安全证明；对照GitHub源码、run/artifact并独立复算才有核对意义。Pages项目路径共享同一origin，localStorage不是跨仓库隔离。
- 发布审阅范围在`outputs/roadmap-2026-09-19-pages-safari/pages-release-review.json`：仅Web客户端及Pages工作流，含当前分支已有9个Web功能提交；不包括未提交App/Mod/helper改动。用户已单独确认，`ace51c9` 已推送至master；尚未 dispatch/deploy。产品方向现已确认：Flutter Web共享App UI/业务代码，浏览器仅保留薄适配层，旧独立版保留参考；通过验收后发布Flutter Pages。`flutter build web --release`用时25.9秒、Wasm dry run成功，产物与日志只作为编译证据保留，不表示功能或迁移验收。
- Safari使用系统原生safaridriver，真实Safari26.6.2第二会话已恢复并实测真实26.2：HTTPS/VideoDecoder可用，解码计数达到259、错误0；错误密码拒绝/正确登录、E打开与ESC关闭经原生`InventoryScreen`确认。设施乘坐导致截图时视频暂停，不能把该截图列为背包画面通过。`Notification.permission=granted`；测试音使受控振荡器计数为1，静音真实NUDGE横幅不增计数，有声真实NUDGE横幅使其恰增至2。没有人工听觉确认，未计为可听声音或系统通知投递。首轮权限面板后的WebDriver中断保留为历史；用户关闭测试窗口后第二会话恢复。现已返回登录页、成功删除自有WebDriver会话并停止自有driver，真实游戏保留且`connected=false`、`shift=false`、`hibernating=true`。自动乘坐仍使服务器休眠，十分钟、后台通知和重连未继续，以符合暂停独立版验证的决定。


## Flutter 共用代码恢复实施（2026-09-19，进行中）

用户明确选择 Flutter 作为 App 与浏览器共享界面及业务逻辑，浏览器保留薄适配层；独立版停止验证，Flutter 验收后再发布 Pages。未删除独立实现，未触发 Pages 工作流。基线使用 Flutter 3.41.2 / Dart 3.11.0，release Web 构建 25.9 秒通过（Wasm dry run 通过，未构建生产 Wasm），仅证明可编译。初步核对和边界见 [Flutter Web 可行性证据](tailscale-integration/evidence/2026-09-19-flutter-web-feasibility.md)。

当前并行实施：浏览器通知与声音适配（继续复用 Dart 倒计时协调器）、Pages 目标与凭证隔离、浏览器键鼠与焦点释放、Web 解码与缩放生命周期。现有原生平台保留原实现并安排共享代码回归。此段不表示这些改动已完成浏览器实测。


### Flutter 共用实现的本地验收进展（2026-09-19）

- Flutter 静态分析无问题、完整 Dart/widget 215 项通过；Chrome 浏览器组合 23 项通过（音频 5、通知 11、输入 5、真实录制 H.264 解码 2）。专项与总套件重叠，不相加。日志在 `outputs/flutter-web-feasibility-2026-09-19/`。
- 本轮 Flutter release 的生产 UI 回放通过错误认证、视频、resize 保留解码器/连接、拖动视角、失焦释放 W、菜单 ESC、声音计数与静音横幅、提醒去重、倒计时更新/取消/过期、4000 断开恢复新帧、刷新身份恢复、目标切换隔离。右上角直接共用 App 单色 Material 图标。
- 真实桌面 Safari 26.6.2 使用 Flutter 页面的回放认证与 H.264 解码通过（93 解码/0 错误），不等于本轮实时游戏、实体手机或系统通知声音。Pointer Lock 在 macOS 自动化中仍无法确认，拖动回退通过；localhost 是安全上下文，但 headless Chrome 的通知权限仍为 denied，SW 系统投递如实跳过。
- 已修复 Flutter 跨输出目录增量打包漏文件的问题；先前 21 文件失败产物未部署，新完整 Pages 49 资源 + provenance，独立预览从全新目录复制并通过 smoke。新增产物完整性校验与发布目录原子替换/失败恢复。Pages 构建 25.6 秒、Mod 根路径构建 25.2 秒。
- 26.2 首轮打包及 62 项测试属于 HTTP 生命周期最终修复之前的产物。随后大型 HTTP 资源传输的并发测试通过，但独立审核发现服务关闭可能遗留慢下载；正在补齐资源关闭和超时，再验证及移植其他版本。
- 用户确认自己仍在玩游戏：本阶段未重新登录 Minecraft、未启动第二个游戏、未接管角色，也未重启当前实例；通过 DebugBridge 只读确认 `connected=false, shift=false, hibernating=true, vehicle=true`。生产 UI 的游戏画面来自录制回放。真实 Flutter→Mod 验收等待合适时机，继续独立工作。
- iOS 模拟器和 Android 编译回归另行执行；所有新 Flutter 页面对手机系统权限、后台音频与锁屏的结果不沿用旧版网页结论。没有新 commit、push 或 Pages deployment。

详见 [Flutter 实施证据](tailscale-integration/evidence/2026-09-19-flutter-web-feasibility.md)、[浏览器运行证据](tailscale-integration/evidence/2026-09-19-flutter-browser-runtime.md)、[CI 配置证据](tailscale-integration/evidence/2026-09-19-flutter-browser-ci.md)。

- 共享代码原生编译回归补充：Android debug APK 40.9 秒构建及 v2 签名验证通过；标准 iOS simulator Flutter 命令在 Xcode27 的 `lipo -verify_arch arm64 x86_64` 参数兼容处失败。未修改 SDK/项目配置，改用同一生成 workspace 的 `xcodebuild ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 后成功，产物 Mach-O 明确为 arm64/IOSSIMULATOR。未启动或安装设备，不能替代手机行为回归。见 [原生回归证据](tailscale-integration/evidence/2026-09-19-flutter-native-regression.md)。

- 最终发布工具实跑：Pages 25.3 秒、Mod 根路径 25.4 秒构建完整，通过新增字体/图标引用及 CanvasKit 变体校验；拒绝输出嵌套于 canonical `build/web`，避免自复制。Pages 全49文件 hash/大小与来源 manifest 一致，旧发行目录安全替换成功。全新最终预览的生产 UI smoke 再次通过；最终包包含“this browser / Client Name”等浏览器措辞，原生措辞保留。日志 `flutter-pages-verified-final.log`、`flutter-mod-verified-final.log`；证据 `final-flutter-artifacts.json` 与 `ui-smoke-release/result.json`。最新 analyze 4.5秒无问题。

- HTTP 关闭生命周期修复最终完成：Java17兼容、最多16个守护下载worker，60秒截止，无排队无限堆积；factory停止时关闭全部handoff socket。另修复shutdown期间timeout调度被拒绝导致active集合遗漏清理，以及channel关闭后仍等待selector注销的竞态。7.15MB慢下载不阻塞WebSocket、完整响应字节数、服务停止清理、容量拒绝仍响应WS、超时关闭均有回归。
- 四版本最终构建全部通过：26.2为66 tests，其余各61 tests，0失败/0跳过；各9项HTTP集成测试通过。4个JAR内49项Flutter资源逐字节匹配最终root-base构建，根路径正确且无内嵌Web Tailscale实验目录。最新JAR只保留在仓库构建目录，未替换正在玩的实例。每包SHA、完整命令和日志见 [最终Flutter Mod打包证据](tailscale-integration/evidence/2026-09-19-flutter-mod-packaging.md)。

- 真实桌面 Safari补测：本地Flutter release +独立replay，三次窗口resize后画面/连接持续。首轮键盘探针未得到消息，记录为未分类而非产品通过或纯驱动问题；追加焦点诊断后确认 activeElement=FLUTTER-VIEW、document.hasFocus=true，W3C key actions及element.sendKeys各自成功发送W down/up（约315ms/7ms）。先前脚本失败不能归因产品。登录输入的WebDriver DOM code普遍为KeyA，游戏动作的document capture却未观察到事件而协议实际已发送，保留此诊断局限，不用DOM空日志否认实测协议。Safari ESC、提醒、后台及真实MC仍不在通过范围。自有浏览器、driver、replay及预览清理，未接真实9600。


## Flutter Web 真实26.2接管验收（2026-09-19，进行中）

用户明确将26.2交给代理并授权决定正常关闭/更新/重启。当前分支仍为`claude/web-m2-m3`，保留已有dirty工作；新包在前轮已构建测试通过，本轮先校验SHA而未无理由重复构建。

- 接管前确认原实例ImagineFun Add-Ons、原服mp.imaginefun.net，无远程控制客户端、无乘坐、无休眠、Shift未按下；游戏停留ChatScreen。
- 旧2f6045c JAR另存本地证据目录；配置完整备份到仓库外权限700的临时目录，单文件权限600，未打印密码或写入公开文档。mc_quit_client确认旧PID68918退出，随后原子替换为509ebc70最终Flutter资源包，使用Prism已保存账户正常启动并返回原服；无需用户重新登录。
- 新入口`https://mac.tail977122.ts.net:8443/`已逐项读取49个资源，与已安装JAR完全相同；1.93秒完成，HEAD200、Content-Length1571、body0。没有绕过证书验证。
- 重启后配置SHA逐字节相同；PC内嵌Tailscale自动恢复running/listening，100.82.132.32、身份指纹1148163683未变，无新登录。初次只读探针误用`ipv4`字段报错，改用源码定义的`tailnetIp`后成功；该探针错误不是产品错误。
- Chrome/Safari真实Flutter控制验收继续进行；上述重启/HTTP/身份结果不提前算作视频或输入验收。原始证据在`outputs/flutter-live-26.2-2026-09-19/`。

- 重连后服务器恢复PeopleMover乘坐并触发IMF自动休眠；并未证实存在额外自动乘坐程序。一次350ms普通Shift未退出乘坐，已释放。为保留设施状态并验证移动场景，仅读取并临时在内存将`hibernationWhenRiding`从true设为false，正常IMF handler已恢复视频；不持久化设置，结束后恢复true。
- Web Tailscale范围复核更正：LoginScreen原本已有iOS/Android入口门槛，浏览器未实际显示该按钮；但Web适配器仍宣称支持、可以请求被发布脚本排除的WASM。现将生产Web条件导出改为明确不支持的适配器，保留原探索文件与native实现。浏览器1项/VM widget2项回归和定向分析通过，正在重新打包。

- Web禁用适配器后的最终root/Pages产物分别24.2s/24.7s构建通过；26.2增量build20s通过（测试任务up-to-date，未冒充重跑66项）。JAR更新为`0f0bc8f66dcd43ba8cc5cdea418a4bfb168b9c0419380d15ddec7d9d0c92fbbf`，49资源逐字节匹配。正常退出PID59663再原子安装、原账户重进原服务器，4个关键HTTPS资源再核验一致。Chrome实际认证后配置仅自动更新`lastPhoneName/lastPhoneSeenAt`，设置/密码/配对身份无变化（不能再称整个文件SHA不变）。开始最终包实时Chrome验收。

- 最新主checkout再次执行完整Flutter测试216项通过、analyze无问题。最终26.2只因资源改变做增量build；另外三版顺序build通过并实际执行test，49资源一致，原始日志和SHA在`outputs/flutter-live-26.2-2026-09-19/ports/`。
- Chrome首轮主动中断以改进取证：SCREEN_STATE先于新视频帧导致第一张背包截图仍是world；第二轮等待至少5解码帧后截图确见背包，且MCP独立确认InventoryScreen。不是修产品或忽略失败，首轮中断原因单独保留。第二轮已通过E/ESC、Shift失焦释放、刷新身份与真实服务端socket4000中断后续帧，十分钟观察仍进行。

- Pages最终候选70文件已制作本地patch与逐文件SHA清单；干净HEAD archive仅应用候选后，锁依赖恢复、analyze、196项VM/widget、24项Chrome、Pages release/verifier与6项Node来源测试通过。未伪造archive commit，未改主index/commit/push/deploy。初始72文件候选混入两个对应未选native音频实现的新增VM测试，复验失败后仅从Pages候选移除，主checkout源测试保留且216项全过。完整记录见`outputs/flutter-live-26.2-2026-09-19/pages-candidate-validation/RESULT.md`。


### 26.2共享Flutter网页追加验收与倒计时修复（2026-09-19）

- Chrome对`0f0bc8f6`包的真实600秒测试已完成：40区间均有新增视频，共4878帧、解码错误0、无额外重连；此前E/ESC、Shift失焦释放、刷新身份和真实socket4000重连均通过。长测包含世界和菜单，实际配置10FPS，不转算为20FPS。
- 真实Safari暴露网页没有可见待完成倒计时，原协调器只安排提醒。新增browser-only `TimedReminderCountdown`，共享现有通知模型，按墙钟计算、同截止元数据更新、取消/到点隐藏、IgnorePointer不抢输入，采用单色Material图标。新增3项测试覆盖墙钟变化、更新/取消/替换及窄屏大字体；主checkout完整219项与analyze通过。
- 新26.2 JAR `471ff457d13e19d2a70108555aeacc28baaf0ffb281608c780a5935a25eff438` 49资源完全匹配，旧进程65280正常退出后原子部署，PID84431返回原ImagineFun。4个关键HTTPS资源再验一致。临时乘坐休眠设置在重启前已恢复true，测试期间仅内存false，结束必须恢复。
- Pages候选加入这2个新文件后为72文件；普通HEAD归档（非worktree）只应用候选补丁，依赖锁/analyze/199VM与widget/24真实Chrome/Pages release及独立完整性复核全部通过。归档无Git因此明确禁用provenance，不虚构commit。主checkout和index未改变。
- Safari补测中区分产品与夹具失败：密码DOM赋值未更新Flutter控制器的登录失败、原生焦点/WebDriver读阻塞、静态语义文本只查aria-label导致倒计时漏检均保留独立失败记录。原生AX/截图已实际看到`Live timer A`倒计时，完整更新/取消/到点流程仍在复测，不凭截图提前记全通过。正式当前证据见`2026-09-19-flutter-live-26-2.md`。


### 真实提醒并发覆盖缺陷（2026-09-19）

`471ff457`真实Chrome两分钟回归通过（8个15秒样本，无额外掉线/解码错误），A→B同截止更新、取消、到点消失与独立到点显示也通过；但首次到点横幅未被轮询捕获。保留首次失败，未直接归咎自动化。子代理排除PING清理：截止PING返回同一SERVER_STATUS，不清除定时，backend正常投递。全局Web overlay原来只有一个slot，任意NUDGE立即覆盖TIMED。

随后真实游戏故意在截止后83ms发送普通NUDGE，MutationObserver精确记录：due在1789791479563出现，1789791479644被覆盖，只有81ms。原presence-only断言返回passed，但这不满足可读性；保留原输出并额外写`chrome-reminder-collision-before-fix/readability-evaluation.json`为failed，将实际端到端断言加强为后续提醒到来后至少2秒持续可见。没有伪改历史结果。

正在最小修复Web overlay：timed保留原12秒展示期，期间只暂存最新immediate一条；timed结束/用户关闭后，仅展示12秒内的新鲜pending，新timed替换并清掉旧pending。新增5项VM/widget先记录red失败，再修复green及定向分析通过。原生通知后端未改。此修复需重新构建、部署和真实并发复测，尚未提前记通过。


## 用户暂停断点（2026-09-19 12:22 Asia/Singapore）

用户明确要求暂停，两个活动子代理已中断，goal已标为paused。不继续开发、游戏测试、提交或发布。

暂停前：overlay保护修复与5项新测试完成，主checkout完整224项及analyze通过，Pages/root构建完成；新的26.2包`ee2dbc284e7865dcc06a6a16e524570302f03329afa7dbb373d40a65254dffd9`已原子安装，49资源一致。旧PID84431正常退出，新Prism启动已发出，但等待26.2 DebugBridge 45秒超时；未继续尝试启动/登录，不声称新包完成运行验收。退出前测试timer已取消、Shift=false、screen=null，IMF临时乘坐休眠已恢复true。

待恢复：核对Prism内存警告与启动状态，确认最终包正常入原服后重跑真实collision可读性（新断言至少2秒）及完整timer流程，再跑Chrome核心短测。73文件Pages候选更新/归档复验与三个其他版本overlay资源构建正在进行时被用户暂停；必须读取各自当前产物/日志确认完成程度，不沿用72文件或旧资源hash冒充最终。Safari前台焦点等待本人方便，不能再频繁无前台重试。未新commit/push/deploy。

资源检查只读发现：系统64GiB、top约60GiB使用/28GiB压缩；搜狗输入法top MEM约44GiB、CMPRS约41GiB，是主要异常占用。无需把这次Prism提示误判为MonkeyCraft已证实内存泄漏。用户考虑重启ChatGPT或电脑，尚未关闭任何用户应用。


## 重启后恢复与最终 overlay 实机复测（2026-09-19 12:33 Asia/Singapore）

用户明确恢复执行。重启后只读内存快照约39GiB使用、25GiB空闲、压缩0；26.2最终包 `ee2dbc284e7865dcc06a6a16e524570302f03329afa7dbb373d40a65254dffd9` 成功启动（游戏PID8513）并回到原ImagineFun服务器。电脑内嵌helper保持running/listening及原节点身份（100.82.132.32）；真实HTTPS的index/main/bootstrap/reminder worker与本地最终构建逐字节一致，记录 `outputs/flutter-live-26.2-2026-09-19/overlay-live-https.json`。测试仅临时关闭IMF内存中的乘坐休眠，结束必须恢复true。

真实Chrome并发提醒复测通过：截止1789792405709，到点横幅在5712出现；普通NUDGE在5791（截止后82ms）收到，之后又有ImagineMoreFun提醒，但最终04:33:28.346仍显示到点横幅，持续超过2秒；倒计时消失，实际解码190帧、错误0。与修复前横幅仅81ms可见形成对照。这里只证明实测>=2秒可读性，12秒完整展示逻辑另有widget测试，不混称12秒实机证据。证据为 `chrome-reminder-collision.status.json`、stages和截图。

随后完整真实Chrome静音提醒、同截止A→B更新、取消、到点横幅与倒计时移除均通过，解码308帧、错误0；页面permission=default、tone调用0，仅计入页面静音路径，不代表OS听觉确认。证据 `chrome-reminder-live.status.json` 与 stages/截图。两次脚本退出已释放唯一控制连接，旧包结果均先归档未覆盖。

暂停中的两条独立验证已核实完成：73文件Pages候选补丁独立归档验证204 VM/widget及24 Chrome、Pages release/49资源检查通过；主checkout完整224项及analyze仍为本轮前序结果。26.1、1.21.11、1.19各61测试通过，三JAR的49资源逐字节匹配最终Web，尚未部署/实际运行新包，详细hash见 `ports-overlay/resources.json`。不将构建成功标为版本产品验收完成。当前开始最终26.2 Chrome核心120秒回归；Safari等待前台操作时间。未新commit/push/公开部署。


26.2最终overlay包Chrome核心回归完成：`FLUTTER_WEB_URL=https://mac.tail977122.ts.net:8443/ MONKEYCRAFT_LIVE_DURATION_SEC=120 ... node flutter/monkeycraft/tool/browser_live_smoke.mjs`，日志和结果在 `outputs/flutter-live-26.2-2026-09-19/chrome-overlay/`。错误密码拒绝、正确鉴权、四次resize保留decoder/socket、E打开背包（root MCP确认InventoryScreen并查看真实视频截图）、ESC关闭、Shift失焦释放、刷新身份和真实socket4000重连全部通过。后续120秒8个15秒样本新增969帧、解码错误0、无额外重连；不把它写成十分钟或20FPS验收。结束已取消timer、screen=null、Shift=false、连接释放、IMF内存乘坐休眠恢复true。下一步为三旧版最终包的真实运行，Safari待前台操作时间，原生最新构建独立顺序执行中。


### 最新共享源码原生构建（本轮，仅编译验收）

`outputs/flutter-native-overlay-2026-09-19/RESULT.md`：iOS `flutter build ios --release` 50.6秒成功，arm64、现有Apple Development签名严格校验通过；Runner SHA `47e717ebf7bc210fef7a81ef1ee00d398e68a3696d3db0821c4065f4817ae831`，App.framework SHA `2628b4f6bc4932fb4c404fe89b03bcdf91060e3ca90f4a49cf40bb15fb61fd5b`。Android `flutter build apk --debug` 20.6秒成功，APK SHA `e7249ee27d06263eabc1dc1c1dd29815552923ca0b7ee5094c722b520a82e5f0`，v2 debug签名、16KiB对齐、arm64-v8a/armeabi-v7a及两个ABI的Tailscale native库均验证通过。两个build顺序执行；未安装到手机或模拟器、未启动额外游戏。此次证明当前共享源码仍可构建，不能替代通知、音频、Tailscale和后台真实行为；Android debug产物不可当正式发布包。


上述iOS构建结论已被后续逐嵌套检查收窄：编译与外层codesign虽然成功，`tool/verify_ios_app.py`发现objective_c.framework为Simulator platform7且无同Team签名，当前包标为INVALID，未安装。与本轮早期已定位的shared native_assets缓存污染一致；现有 `tool/build_ios_device_release.sh` 已有clean及完整校验，但AGENTS与根README仍示范普通增量build。现已将这两处入口修正为设备构建包装脚本，说明先保存其他平台build输出。原生代理保存APK/Web及无效包后使用该入口重建；保留失败日志，不改成成功。Pages候选73文件不包含上述两个文档，候选补丁/源哈希未因本次文档修正改变。


### Pages 最终候选本地端到端

73文件archive的Pages产物复制到loopback静态入口 `/monkeycraft/`，逐文件hash相同；通过本地 `ws://localhost:19620` 录像夹具验证错误密码、实际录像H264解码、resize、静音/提示音调用/去重、计时更新取消、4000恢复、刷新与目标变更。记录 `outputs/flutter-live-26.2-2026-09-19/pages-overlay-e2e/RESULT.md`。测试仅使用Flutter共享产物，未恢复独立TS产品测试，也未连接真实MC；无头PointerLock WrongDocumentError与通知denied明确列环境限制，不冒充OS投递或听觉验证。自有loopback静态/replay服务已结束，无生产发布。

用户已同意现在交出前台2–3分钟用于Safari，已协调版本代理完成正在跑的26.1短测后恢复26.2再移交，1.21.11和1.19暂不启动，防止争抢唯一控制会话。


iOS clean包装入口重建现已成功，`verify_ios_app.py`逐嵌套平台/同Team签名全部通过：有效Runner SHA `369feb4e4f8c918e2d69d22e35fa3be7242a211a98113618d7d7ed67408d44c6`，App.framework SHA `0466933f0777371936623c2863b742eba599a7613fb946a7030af7e0924a3473`。旧INVALID包与失败log仍保留；Android APK归档为 `outputs/flutter-native-overlay-2026-09-19/artifacts/app-debug-current-overlay.apk`。主build/web(49)与pages-validation(50，含provenance)清理前保存、清理后确认目录空缺再逐文件恢复，main.dart.js均保持57a798；未覆盖其他新增构建、未改源码/index、未安装或启动设备。完整结果见该目录RESULT.md。


### 真实 Safari 最终包验收（ee2dbc）

用户提供前台操作时间后，Safari已完成真实HTTPS/WSS登录、H.264持续解码、三次resize、E/ESC、Shift成对释放、静音横幅、同deadline A→B、取消、到点横幅及倒计时移除并至少2秒可读。`flutter-safari-live-acceptance.json`记录passed及decoded609/errors0。原JS语义Connect点击没有创建socket，原生AX实际点击成功；后续改为WebDriver原生元素click的交互测试直接登录成功，属于夹具修正而非更改产品绕过。早期5个新帧截图仍是旧世界，后续独立MCP确认InventoryScreen、原生CUA与`inventory-confirmed-later.png`可见真正背包，三种证据区别已记录。

随后真实Safari前台W3C鼠标drag成功：request时hasFocus=true/element connected=true，pointerlockchange=true；Esc后=false，只发LOOK_DELTA，未发CLICK。原生坐标操作会被Safari自动化保护界面拦截，已选择Continue Session，未关闭保护；不把WebDriver鼠标动作称为人工测试。`flutter-safari-interactive-acceptance.json`与sound.json记录真实NUDGE声音调用计数8→静音8→有声9→重复9，permission=granted/hidden=false。其余ImagineMoreFun自动提醒也产生声音，因此最终tone总数不归因于本测试。听感已询问用户待答；系统通知测试新tab后document.hidden仍false，该次通知不能冒充后台系统投递，保留待验。两个Safari会话已正常结束，无控制连接、Shift=false、screen=null，IMF内存乘坐休眠恢复true。用户可以恢复键鼠使用。当前再交MC给版本代理完成1.21.11和1.19。


iPhone覆盖安装前的重新发现显示设备unavailable（Flutter无线发现code -27），故没有执行install、卸载、清数据、手动kill或启动App。有效包再次通过verify，手机当前仍为此前已安装版本；需要用户解锁并恢复同LAN或USB可达后再一次覆盖安装。证据 `outputs/flutter-native-overlay-2026-09-19/ios-device-install-attempt.md`。与此同时Android release包正在构建和归档，之前debug APK仅保留为debug构建证据。

已请求精确Pages发布授权：73文件候选（共享Dart、浏览器适配及工作流），明确排除Swift/Kotlin/Mod/helper/手机二进制并说明共享Dart对App源码的影响；原授权排除了App，所以不自行扩大提交范围。候选逐文件SHA仍匹配，patch SHA `a5b78800f921fee5d6a236af10f405066207717c2332537a8ecae3de753bdd66`。只读确认origin/master仍为ace51c9，尚未发生新commit/push/dispatch/deploy。


### 三个其他版本最终 Flutter 包真实回归完成

26.1 `660d0a50…`、1.21.11 `0063d289…`、1.19 `52fa89f6…` 均已在各自真实Prism实例原子部署并运行。每版通过错误密码拒绝、真实H264、resize、E/ESC、Shift blur释放、刷新身份、socket4000关闭恢复；随后60秒4个15秒区间持续出帧，分别新增521、562、479帧、解码错误0，无额外掉线。前两版回原ImagineFun，1.19只使用已有独立世界 `MonkeyCraft acceptance 2026-09-1`。这是当前Flutter overlay包证据，不沿用旧独立Web测试；各自JAR hash/资源/截图/native菜单及恢复状态见 `outputs/flutter-live-26.2-2026-09-19/legacy-overlay-runtime/` 及各版本runtime证据。

结束恢复26.2最终ee2dbc与原服，helper=running/listening且0 connections，root独立确认screen=null/Shift=false/IMF ridingSleep=true/无控制连接。没有重配系统Tailscale或复制节点身份；旧版各自helper登录/跨设备仍待本人账户授权，短时桌面运行不能代替真机/切网/长时。

最新Android Release `39218eaa4542dce00410e748f3882f52275b4a879c6adaa11b695d879afe5f6f` 已构建（70.1秒）归档，83,686,326字节，v2签名、两ABI/16KiB与Tailscale native库通过；使用本地个人签名，未声明Google Play生产分发。iOS有效包保留且再次verify通过。接下来授权原生代理在保存数据的现有AVD做Release包短回归，当前未记运行通过。


Android模拟器追加进展：旧快照因renderer变化失败，最终使用不读写快照的冷启动保留原userdata，已确认Android16/arm64 boot_completed=1；这不是App崩溃。Release `39218eaa…` 已用覆盖安装保留数据，正式GUI经 `10.0.2.2:9600` 连接真实26.2并进入流界面，后续行为验收仍进行中；未发起Tailscale登录。资源检查发现本次构建遗留Gradle/Kotlin空闲进程合计约6.3GiB RSS，执行正常Gradle stop后两个进程均退出；没有关闭用户应用或更改系统设置。

README最终说明同步：发现根README仍示范历史TypeScript构建并只称26.2实测，已改为共享Flutter根路径构建、独立Pages `/monkeycraft/`候选以及四版本当前实测边界；保留iOS clean入口与原用户修改。没有因此重建或更改73文件Pages候选，逐文件SHA重新核对无差异。


### Android 当前 Release 实际运行及最终收尾

`outputs/flutter-native-overlay-2026-09-19/android-roadmap-release-runtime.md` 已完成本轮独立记录：Android16/API36 ARM64既有AVD保留userdata冷启动，`adb install -r`安装归档Release `39218eaa4542dce00410e748f3882f52275b4a879c6adaa11b695d879afe5f6f`。正式GUI通过LAN `10.0.2.2:9600`真连26.2并显示视频；通知权限实际允许，静音NUDGE和15秒到点提醒出现在系统通知栏。45秒A→B同deadline更新只有一个RTC_WAKEUP alarm，取消后有alarm_cancelled证据。原生Sneak短按释放后Shift=false；受控socket4000关闭后约10秒再次连接并显示游戏控制界面。

展开Android通知栏时，非Web的`didChangeAppLifecycleState`按现有代码进入`_pauseStreaming`并主动stop WebSocket；同一MainActivity进程3870没有fatal日志，以`am start`将已运行实例带回前台后connected=true。这是有证据的生命周期暂停/恢复，不将它或AVD快照renderer不匹配误写成App crash。Android物理KEYCODE_E仅验证打开Inventory，后续E/ESC未关闭，保留Partial，未称完整硬件键验收；桌面浏览器E/ESC结果单独记录。模拟器通知投递不证明实际可听，不代替真机锁屏/后台音频/系统VPN与本人Tailscale登录。

结束使用正式Disconnect回登录页，清理测试timer和界面，恢复乘坐休眠true；模拟器经adb正常关闭且未清数据/保存新快照。root随后独立只读确认26.2：connected=false、screen=null、Shift=false、ridingSleep=true。Git index为空，73文件Pages候选仍逐文件SHA一致；新共享范围授权尚未收到，因此未commit、push或生产部署。真实Safari听感及iPhone可达性仍待用户反馈。


### iPhone逐步人工验收：最新有效包已安装

用户要求一次只引导一个人工步骤，并确认手机已连接、解锁亮屏。devicectl发现物理iPhone available(paired)，安装前再次通过verify_ios_app逐嵌套平台/签名校验，Runner SHA369feb4e…与App.framework SHA0466933f…与已验构建一致。使用devicectl device install app覆盖安装成功，未执行卸载/清数据/手动kill；随后按bundle ID读回Monkeycraft 1.4.2(11)。证据：outputs/flutter-native-overlay-2026-09-19/ios-device-install-connected.json、对应log及readback.json。此时只确认安装，尚未确认启动、登录身份、通知或音频行为；下一步请用户打开App确认首页。

逐步iPhone反馈：最新包启动后出现Keep alerts on screen提示，用户按引导选Later。点击Connect with Tailscale后短暂等待直接显示设备列表，无再次登录要求；这是最新包本人确认的登录持久性证据，尚不是游戏连接证据。用户反馈地址信息太专业、希望不默认显示；核对代码实际为Tailscale IPv4/IPv6而非MAC，当前完整地址与Online/Offline并列。记为后续界面调整：列表以设备名/在线状态为主，地址放详情；先完成当前已安装包的逐项人工验收，避免中途换包混淆结果。

最新iPhone包人工验收：用户选择monkeycraft后确认看到游戏画面，登录持久性与真实游戏连接通过。接下来保持前台，发送sound=false的“静音验收 01”；横幅显示与听感等待用户反馈，尚不计通知通过。

最新iPhone包“静音验收 01”：用户确认前台显示提醒且无声音，通过。同期另有IMF “You are not riding”独立提醒，不将其计为本测试重复，也不把其声音归因于本测试。下一项有声验收先等待用户关闭静音并确认音量。

用户确认有声测试准备完毕；已向当前iPhone会话发送sound=true的“有声验收 02”一次，显示及响铃次数等待用户反馈。同期IMF独立提醒仍需分开判断。

最新iPhone包“有声验收 02”：用户确认显示且只响一次，通过。随后发送五分钟静音倒计时“测试 A”，准备逐步验证显示、同deadline更新和取消；当前等待显示反馈，不要求等待五分钟结束。

最新iPhone包：用户确认看到“测试 A”倒计时。尝试保持原deadline不变更新为“测试 B”时，服务端报告no connected client，因此本次未发送更新；需用户回到游戏画面恢复连接后再试，不能记作B已发出。

用户返回游戏后，服务端确认连接恢复；现已成功将原deadline 1789805105515的“测试 A”更新为“测试 B”，没有延长截止时间，等待用户确认替换且只保留一份。

最新iPhone包：用户确认只剩“测试 B”且约两分半，A→B同deadline更新、单份显示与未重置通过。随后在已连接会话成功发送cancelTimedNotification，等待用户确认倒计时消失。

最新iPhone包：用户确认“测试 B”取消后消失，取消显示通过。接下来发送90秒sound=true的“锁屏验收”倒计时，准备用户确认锁屏保留与到点一次提醒；尚待真机反馈。

最新iPhone设备包（Runner369feb4e…）锁屏验收：用户先确认锁屏可见倒计时，随后确认到点显示提醒且只响一次，通过。本轮真机反馈与此前旧包记录分开；下一步等待解锁回App后的画面恢复、无需重新登录与无到期提醒重复。

最新iPhone包锁屏恢复：用户确认解锁返回MonkeyCraft后画面自动恢复，无需重新登录，且“锁屏验收”未再次响起。当前真机静音/有声、同deadline更新单份、取消、锁屏保留/到点一次与前台恢复均已有本人反馈。接下来仅逐步进行园区音频，不重复已有通过项。

### 人工音频验收发现：PC IMF / 手机缺少音频会话交接

用户指出未点击OpenAudioMc链接，因此手机设置无Audio Connection，并指出PC被断开后会自动重试而与手机争抢。读取IMF OpenAudioMcService确认connectionDesired下server-ended/恢复会请求新会话；MonkeycraftCompatImpl只跟踪连接状态，没有音频所有权协调；当前26.2 WebSocketServerHandler的INFO分支为空，App上报openaudiomc connected并不形成交接。这证明缺少协调机制/存在争抢风险，未刻意制造真实抢占循环。

本次人工测试临时调用运行中IMF既有disconnectViaCommand停止PC音频及自动重试，不修改持久开关、不部署IMF。此前PC active=true/connected=true/pending=false/volume=0；测试结束必须在手机音频明确断开后恢复PC connectViaCommand并保持原音量0。此临时隔离不算产品修复。正式待办：手机明确请求音频时交接，锁屏/短时WebSocket断线不应触发电脑抢回；明确结束手机音频后再恢复电脑原意图，需要协议与IMF双方实现及测试。当前先继续用户要求的逐步手机音频验收。

音频会话生成：手机首次/audio返回generating后报告生成失败；用户第二次尝试成功。保留首次错误，不把短暂失败直接归因为手机缺陷或旧会话未释放（未证实）。第二次成功后PC IMF再次只读核对，仍停止且无待重试/管理会话；下一步请用户点击新鲜音频链接，连接和可听状态尚待确认。

最新iPhone包真实园区音频：用户在MonkeyCraft聊天点击新鲜“Click here to open the web client”后，聊天返回“you are now connected with the audio client”，且用户确认已能听到声音。这是实体iPhone当前包的连接及可听证据；PC IMF已临时停止接管，故不证明自动交接修复。下一步等待约30秒锁屏持续播放反馈。

最新iPhone包园区音频锁屏：用户反馈接近一分钟仍持续播放，通过本次约一分钟真机锁屏持续音频；不是长时/OEM/跨网结论。PC音频临时暂停隔离仍有效，后续需手机明确停止后恢复PC。下一步等待解锁回游戏后的画面/音频连续性反馈。

最新iPhone园区音频恢复失败：用户明确澄清锁屏时持续播放，解锁返回App后声音停止，画面为hibernation。服务端只读确认phoneConnected=true；PC IMF active/connected/pending/managesServerAudio全部false，故本次不能归因为电脑抢回。标记真机失败，尚未重连/重新点链接以保留现场；接下来区分音频会话状态与本机媒体恢复。

音频失败现场补充：聊天、网络连接与倒计时仍正常；设置显示“Connected to OpenAudioMc”，同时有Disconnect/Refresh操作。说明App连接指示仍为true，不能据此认定媒体仍播放（当前指示基于网页range控件）；下一步单次手动刷新区分可恢复性。尚未定位为AVAudioSession或页面媒体暂停。


### iPhone音频恢复缺陷：进入诊断，非通过

用户确认手动Refresh后恢复声音。源码软恢复仅检查range控件，未确认媒体状态，具体打断层尚未确定。新增仅显式dart-define启用的本地有界媒体/原生音频事件诊断，不记录链接或聊天；正常构建默认关闭。9项音频回归与analyze通过，clean诊断Release构建进行中。完整失败序列与证据边界见 tailscale-integration/evidence/2026-09-19-ios-audio-resume.md。原有效包/Web资源已保留。由于当前Dart增加诊断依赖，73文件Pages候选不再代表工作区，后续正式修改后必须重新选择候选并验证；没有提交/推送/发布。PC音频临时断开仍待手机测试结束后恢复。

音频诊断Release已完成clean构建47.8秒/逐嵌套验证，并覆盖安装到本人iPhone；读回1.4.2(11)。Runner bf0ecae…，App.framework80990bc…，显式启用MONKEYCRAFT_AUDIO_DIAGNOSTICS；该包只用于取证，未声称修复。原有效包备份仍在，build/web与pages-validation已按空缺恢复。等待用户重新进入游戏，随后验证诊断输出并逐步复现。

用户明确暂停，携手机离开；立即停止手机/游戏/诊断操作。当前iPhone已安装bf0ecae音频诊断Release，尚待重新连接游戏及新一轮音频复现；PC IMF音频为此前测试而临时停止，保持不动以避免在手机状态未知时抢占。恢复时先核对手机/音频状态再逐步继续；结束测试仍须恢复PC原音频意图与音量0。没有进行新commit/push/deploy。

用户返回并明确恢复音频诊断，仍要求逐步引导。只读预检：物理iPhone available(paired)，26.2仍在游戏世界，无手机控制连接；PC IMF audio active/connected/pending/managesServerAudio均false，维持隔离。下一步在同WiFi、手机亮屏的当前诊断包中重新连接monkeycraft，先不启动音频或锁屏。

音频诊断复现开始：用户恢复连接后请求/audio获得新鲜链接，点击后确认前台有声音。已成功读取设备Library/Caches诊断到outputs/ios-audio-resume-2026-09-19/foreground-baseline.json，采集可用；下一步锁屏约30秒，保持步骤分离。

音频诊断v1真实复现再次失败并读取现场：前台播放→锁屏30秒以上持续→返回App停止。native-active点category/route/volume不变，无同刻原生interruption；HTML元素仍paused=false，但不足代表Web Audio；后21.7秒的interruption单列不能逆推根因。追加弱引用AudioContext观测与仅开发机固定标记触发的一次resume诊断，默认不开启，不刷新页面/自动重试。Node3项、Dart音频9项和analyze通过；v2诊断包构建中。详见ios-audio-resume证据；未声称已定位或修复。

音频v2诊断Release（fa069d28…/App031ab5f2…）已clean构建46秒、验证并覆盖安装/readback。仅新增WebAudio观察与明确请求的单次恢复能力，未执行恢复、未声称修复。下一步仍按用户要求先重新连游戏，再逐步建立新音频会话/采样/复现；PC音频继续隔离关闭。


用户要求减少实体手机打扰，音频诊断已转到 iOS26.5 既有模拟器，经127.0.0.1直连真实26.2、正常GUI配对与/audio会话，用户确认模拟器有声。已取得Web Audio context running/时钟推进基线，准备自主锁屏复现；不能替代iOS26.6.2真机验收。通用模拟器构建架构处理失败已保留，指定设备flutter run成功；另修复debug键盘预热字号0断言，待验证。详情见音频专项证据文档。PC音频仍按既有测试隔离停止，结束须恢复，未操作用户手机。


模拟器音频已定位到网页No Sleep短视频回前台恢复播放时，浏览器原生暂停两条detached音乐元素；AudioContext仍running，所以此前DOM范围诊断漏掉真正音轨。已做原条件失败→只静音No Sleep视频通过→取消静音再失败的单变量对照，且显式仅恢复两条音轨可恢复时钟推进。新增仅iOS原生OpenAudioMc来源/No Sleep VIDEO的play前静音兼容脚本，音乐音量不变，无自动全页刷新。11项Node测试通过，重新构建正常模拟器GUI验证进行中；真机仍是既有失败记录，未覆盖安装修复。详见ios-audio-resume证据。


No Sleep修复已完成本轮模拟器回归：重新构建13.3秒，正式App经LAN保存身份重连26.2；新音频最初出现退回登录/超时，保留失败；最终fresh链接通过调试器调用同一正式服务成功。锁屏71.086秒与Home后台43.151秒后真实两条音轨仍播放状态/时钟推进、无新pause事件；明确Audio Disconnect再Home返回后active/connected/后台租约均false。23项专项测试（JS11、Dart12）、analyze、相关diff检查通过。新正常iPhone Release clean构建50.6秒并逐嵌套平台/签名验证，Runner06c2a363…/App988e6554…，未操作或安装用户手机；真机修复可听仍待最后一次短复验，模拟器结果不冒充真机通过。

收尾已完成：模拟器正式断开游戏并关机保留数据，clientConnected=false；电脑IMF恢复active=true/connected=true/pending=false且volume=0。归档修复模拟器及设备包，Web历史构建按空缺恢复，暂存会话URL文件已清理；8份采样一致性检查通过。支持矩阵、音频架构文档、剩余步骤与专项证据已更新。没有新增commit/push/PR/部署；PC/手机自动音频交接及原计划其他剩余门槛继续保留。


### 2026-09-19 恢复逐项人工验收：桌面 Safari

用户要求回到剩余验收步骤，并继续一次一项。iPhone 修复后最终真机听感仍保留待验，当前转到第 4 项桌面 Safari 提示音、真实后台与系统通知。本轮先确认 26.2 无控制客户端，再用真实 Safari 打开已有 HTTPS 入口，经正常配对后收到实际游戏画面；尚未发送本轮测试提醒，等待用户确认电脑声音可听。此记录不把历史声音调用次数转算为实际听感通过。

用户确认电脑声音已准备好后，向唯一已连接的真实 Safari 会话发送 `Safari 有声测试 01`（NUDGE，sound=true，服务端时间 1789819632688）；服务端调用成功且连接保持。横幅呈现与响声次数等待用户报告，尚未记为通过。

用户报告 `Safari 有声测试 01` 未听到提示音（横幅情况未确认），本项未通过。按用户要求发送新标题/正文的 `Safari 有声复测 02`（sound=true），避免被相同内容去重；等待用户报告。

用户报告第二次仍无声。真实 Safari 设置页 AX 明确显示 `Reminder sounds = off`；当前源码初始值为 false，`_deliver` 在该开关关闭时不会调用 playTone，因此两次无声有明确的设置原因，尚无证据归因 Safari 播放故障。代理此前未核对前置设置，已向用户说明；通过正常设置开关启用，AX 已显示 on，下一步发送新 NUDGE 复测实际听感。

声音开关在异步启用后持续显示 on，无错误文字；返回游戏页后发送 `Safari 有声复测 03`（sound=true），服务端连接正常。实际听感仍待用户确认。

用户明确反馈 `Safari 有声复测 03`“听到了”。本轮真实桌面 Safari 前台提示音可听通过；用户未单独确认响声次数，因此不增加本轮实际一次性/去重结论。前两次未响归因于本轮新会话的声音开关关闭；接下来验收真实后台系统投递。

Safari 设置页点击 Enable reminders 后显示 `System notifications enabled.`；声音开关仍为 on。返回游戏，再通过 Safari 原生窗口最小化按钮发送到后台（本步未读取 document.hidden），随后发送 `Safari 后台通知 04`（sound=true），连接保持。OS 系统横幅呈现和听感等待用户确认；仅权限文字不计投递通过。

用户对 `Safari 后台通知 04` 反馈“又听到了”，确认本次提醒可听；尚未报告 macOS 系统横幅是否出现。本步也未直接读取 document.hidden，因此不把听感单独转算为系统通知投递成功；继续单独确认屏幕右上角系统横幅。

用户补充 `Safari 后台通知 04`“也看到了通知”，确认本轮最小化操作后的真实桌面通知呈现与可听声音。该结论基于用户实际观察；document.hidden 未直接采样，保留证据边界。随后同一连接发送 `Safari 静音后台测试 05`（sound=false），等待确认只出现通知、不发声。

用户未观察 `Safari 静音后台测试 05`，该次不作通过或失败结论。按要求发送新标题 `Safari 静音后台复测 06`（sound=false），连接正常；等待用户确认横幅与静音。

用户确认 `Safari 静音后台复测 06`“有通知，没有声音”，本轮真实后台静音投递通过。继续向同一连接连续发送两份相同标题、正文、sound=true 的 `Safari 重复提醒测试 07`，验证用户实际只收到一次提醒与响声；等待反馈，不以发送调用数认定去重成功。

`Safari 重复提醒测试 07` 两次发送间隔合计 27ms。用户反馈窗口不在最前方时未听到声音，但 macOS 右侧有浏览器通知；没有确认通知次数。故本次后台有声去重不计通过，也不能凭窗口不在最前方就解释无声。此前 04 的用户可听反馈仍保留为单次历史观察，后台声音一致性待核对。下一步由用户将 Safari 游戏页置前，再单独复验前台两份相同提醒。

用户确认 Safari 游戏页已回到前台且准备好。发送两份完全相同的 `Safari 前台去重测试 08`（sound=true）；服务端连接保持，实际横幅和响声次数等待用户确认。

用户确认 `Safari 前台去重测试 08`“只显示一次，响了一次”。两份相同 NUDGE 在 35ms 内发出，本轮真实前台横幅与可听去重通过。后台 07 的无声仍未解释，不被前台通过覆盖；下一步等待用户明确最小化 Safari，再发送一条新的有声 NUDGE 复验后台一致性。

用户明确确认已用黄色按钮最小化 Safari。随后发送单条全新 `Safari 后台有声复测 09`（sound=true），服务端连接保持；等待用户报告系统通知呈现与实际声音，不提前判定通过。

用户未观察后台有声复测09，该次不作通过或失败结论。按要求发送新标题 `Safari 后台有声复测 10`（sound=true，单条），连接保持；等待用户确认。

用户确认后台有声复测10有系统通知但未听到声音。与07一致，后台有声项仍失败；静音投递和前台可听/去重的通过记录不受影响。停止重复听感试验，开始检查 macOS 对该网站的声音设置与后台代码路径。源码在 document.hidden=true 时只请求带 silent 参数的系统通知，不同时播放页面音调。

macOS 原生设置实查：网站 `mac.tail977122.ts.net` 的 Allow Notifications 与 Play sound for notification 均 on；系统 Alert volume=100%、Play user interface sound effects=on。但 Play sound effects through 为 Mac Studio Speakers，普通 Output 为 USB AUDIO（33%、Mute=0）。两类声音输出设备不同，是明确环境差异，尚待单变量复验；因改动会影响全局系统提示音，已询问能否临时统一输出并在测试后恢复。另查到源码固定复用通知 tag 且未设置 renotify，列为独立待核对因素，不在未验证前认定为此次唯一根因。

用户明确授权改为 USB AUDIO，并说明自己平时用 USB AUDIO 听声音、内置扬声器偏低。通过原生设置将 Play sound effects through 从 Mac Studio Speakers 切到 USB AUDIO，AX 读回确认；Alert volume100%、媒体输出33%和静音状态均未更改，未修改应用代码。随后向仍保持连接的后台 Safari 发送单条 `Safari 后台有声复测 11`（sound=true）。本轮为只改变系统提示音输出位置的对照，等待听感反馈。

USB AUDIO 输出下后台有声复测11仍未听到。随后用户两次确认 macOS 声音设置自带 Boop 可听，因此系统提示音通路本身可用；设备路由不是充分解释。真实 Safari Inspector 读回 Notification.permission=granted、renotifySupported=false；getNotifications() 显示最新 `Safari 后台有声复测 11` 的 tag=monkeycraft-immediate、silent=false。源码对所有即时提醒固定复用该tag。WHATWG标准中同tag替换与重新提醒是独立语义，且WebKit当前NotificationOptions.idl的renotify尚注释；仅添加renotify不能假定Safari生效。准备全新tag对照时，CUA最小化/恢复后控制台键盘操作未实际执行，输入仅残留于AX值且未出现执行日志。用户期间说听到一声，但来源无法对应，不计新tag对照成功。已请用户恢复Safari前台以继续受控对照；未改应用代码。

用户恢复Safari后，控制台再次受自动化焦点与粘贴超时报错干扰；最终通过截图坐标聚焦、清空旧输入后，实际执行新tag延时诊断（控制台返回timer ID=2718），并读到 MC_NEW_TAG_SENT。发送时 MC_NEW_TAG_HIDDEN=false，因此这次仅是系统通知新tag诊断，不构成后台hidden验收；已单独询问用户标题 Safari new tag 12 的听感。

决定性系统证据：NotificationCenter / donotdisturbd 明确将该网站通知判为 `reason: display shared`、`muted by display state (displayShared)`；对应声音记录 `isMuted: true, hasSound: true, darkWake: false`，Do Not Disturb 本身为 false。此次看屏/共享状态触发了 macOS 的共享时通知静音策略，不能据此修改应用为绕过系统静音。新tag诊断12也被该规则静音，用户见到通知但未听到；tag假设未证实。已保存仅该网站相关系统日志到 outputs/safari-notification-sound-2026-09-19/system-suppression.log。下一步结束看屏，保持系统隐私设置，再经现有MCP游戏接口发提醒复验；暂不改生产代码。

用户表示 Safari 已无紫色共享图标。停止一切CUA/看屏调用后，仅用系统日志读取最近8分钟，未发现新的共享状态变更或本站点通知事件；当前共享状态不能仅凭图标消失认定已解除。下一步让用户明确最小化Safari，再仅由游戏MCP发送新通知，同时读对应系统判定，避免观察工具再次影响声音验收。

用户再次确认 Safari 已最小化后，仅用游戏 MCP 发送 `Safari 后台有声复测 13`（1789823083126ms），期间无CUA/截图调用。匹配的21:04:43系统日志记录 `outcome: allowed; reason: disabled; interruptionSuppression: none`，并明确 `Playing notification sound ... for _WEB_CENTER_:web.mac.tail977122.ts.net`，与先前displayShared抑制形成对照。输出仍为已授权的USB AUDIO，生产代码未改。原始本站点20条事件保存在 outputs/safari-notification-sound-2026-09-19/test13-system-events.json；用户实际听感尚待确认。

用户确认对照13“看到了系统通知，而且听到了一声提示音”。停止看屏后，系统实际播放日志与用户听感一致，后台单条有声通知通过；本轮无须应用代码修改。为排除早前06被系统整体静音所混淆，再在同样无看屏环境发送 `Safari 静音确认 14`（sound=false），等待用户确认。

用户确认静音14“看到一个通知，但是没声音”。对应21:05:44系统日志为 `Not playing sound` 且 `isMuted:false, hasSound:false`，在无共享静音干扰的环境下静音通过；证据保存于 outputs/safari-notification-sound-2026-09-19/test14-system-events.json。随后同样不调用CUA，20ms内发送两份相同的 `Safari 后台去重确认 15`（sound=true，sentAtMs=1789823327864），等待用户确认通知与声音均只有一次。

用户确认后台去重15“看到了一个通知和听到一次声音”。两份相同有声NUDGE在20ms内发送；21:08:47.993系统仅记录一次本站点 `Playing notification sound`，证据保存为 outputs/safari-notification-sound-2026-09-19/test15-system-events.json。本轮桌面Safari前台有声/去重、后台有声/静音/去重均已有人实际确认；此前07/10/11无声保留为共享环境导致的失败观察，根因以displayShared系统证据及无看屏13–15对照支持。本轮仅更新文档，无生产代码变更，因此未重复构建。系统提示音仍按用户授权使用USB AUDIO。后续先确认Safari回前台恢复，再推进其他剩余验收；真实移动浏览器、iOS音频修复包真机与公开Pages不自动记为通过。

用户随后恢复Safari到前台，确认“画面正常恢复，无需登录”。本轮后台提醒验收结束后，真实Safari画面恢复与会话保留也通过；此时Safari仍占用唯一控制连接，尚未释放。下一项拟补真实手机浏览器验收，先关闭桌面测试标签释放连接。

用户确认已关闭桌面Safari测试标签；MCP读回 isClientConnected=false（1789825031820ms），本机既有HTTPS入口返回200。桌面会话已释放，进入iPhone真实Safari入口验收；尚未收到手机加载结果，不新增移动浏览器通过结论。该tailnet HTTPS入口依赖手机系统Tailscale，MonkeyCraft原生App内嵌节点不会给Safari提供系统路由。

iPhone真实Safari：用户报告HTTPS连接页可见，并发起Pair请求；本机唯一待配对设备名为safari，经正常acceptPairing入口接受，返回accepted=true；即时connected=false，认证完成状态需后续读回。随后已关闭遗留电脑配对弹窗。未读取或展示密码；实际游戏画面与移动浏览器行为仍等待用户观察。

iPhone真实Safari配对接受后再次读回connected=true，用户确认显示休眠界面；游戏现场为同一项目的休眠消息包含倒计时，网页又额外渲染TimedReminderCountdown，重复显示已证实。共享Flutter仅调整附加倒计时显示条件：休眠覆盖层显示时不另加倒计时，保留通知调度与正常视频页计时。13项定向Flutter测试及analyze通过，Web Release和26.2 Gradle build通过；浏览器对照及安装待完成。用户听到ride到点提示但无法确认电脑或手机来源，因此不计iPhoneSafari可听验收通过。

休眠重复倒计时修复已完成：同一Chromium窄屏夹具在旧版复现重复（附加倒计时1份），新版4项回归通过（休眠附加倒计时0份、中央正文截图保留）。13项Flutter定向测试/analyze/Web Release/26.2 build通过，JUnit本轮66项全通过；26.2已正常重启回原服务器，新JAR `bc6f919f02384c028f70c3ca0301bcef85328080e6ade3ca2747ad10136a478e`，main.dart.js `60cbdf2044caa3a8e2d99d6761ae85f594e7874df78fd4784c0e6c1e0a03c145`，49资源及HTTPS采样逐字节一致。手机新包显示待用户刷新确认；旧版本移植与Pages候选须随后更新，不把旧包结果转算。[专项证据](tailscale-integration/evidence/2026-09-19-hibernation-countdown.md)。

用户已刷新iPhone Safari并重新连接，确认游戏画面恢复。MCP复核connected=true、hibernating=false且无现有倒计时；在不覆盖真实ride或提醒的前提下，临时进入“休眠显示测试 / 2m left”并发送同名120秒静音计时，用于手机验证中央提示保留、附加倒计时消失。等待用户观察，下一步撤销测试休眠与计时。

用户在已刷新的真实iPhone Safari确认测试休眠页面无重复倒计时。随后按测试专用文字匹配取消计时并结束休眠，MCP读回timerCleared=true、hibernationEnded=true、connected=true、hibernating=false；未清除其他真实提醒。此项新包真机显示验收通过，下一步手机网页自身的Test sound，之前来源不明的声音仍不计通过。

真实iPhone Safari：用户在网页开启Reminder sounds并点击Test sound后肯定回复（原文“能提到”，按上下文为听到），手机本地测试音通过。随后向唯一连接发送“手机静音测试 01”（NUDGE sound=false），等待网页提示呈现与无声反馈；不把Test sound单独转算为实际NUDGE或系统通知听感通过。

用户未观察“手机静音测试 01”，不判通过或失败。按要求发送新标题“手机静音复测 02”（NUDGE sound=false），避免相同内容去重；等待真实iPhone Safari提示与静音反馈。

用户确认“手机静音复测 02”看到了且没有声音，真实iPhone Safari前台静音NUDGE通过。随后发送单条“手机有声测试 03”（sound=true），等待手机实际提示与一次声音确认；尚未计后台或系统通知通过。

用户确认“手机有声测试 03”提示出现、手机响一声；真实iPhone Safari前台NUDGE有声通过。用户询问Safari后台倒计时，已核对当前实现：Dart页面计时器到点才投递，reminder-sw.js只处理notificationclick，无push订阅/推送处理，不能承诺iPhone Safari切换App或锁屏后的准时提醒。苹果WebKit说明iOS Web Push面向添加到主屏幕的Web App，需实际接入推送；仅添加到主屏幕不等于当前网页获得原生本地定时通知能力。此为实现与平台边界，尚非本轮真机后台实验结论。

用户确认继续真实iPhone Safari逐项验收。准备发送两份相同的“手机去重测试 04”时，MCP读回no_client，未发送任何提醒。先请用户返回Safari并观察连接是否自动恢复，再继续去重测试；当前断开的原因尚未确认。后续仍需手机计时更新/取消、横竖屏触控及后台返回恢复；不承诺普通Safari锁屏准时提醒。

用户返回真实iPhone Safari后确认画面自动恢复、不需要重新登录。此前MCP无连接，返回后读回connected=true，实际会话恢复通过；未记录后台停留时长或锁屏状态，不扩大为长时后台验收。随后于1789830062320ms发送两份相同“手机去重测试 04”（sound=true，合计17ms），等待用户实际一次显示、一次声音反馈。

用户对“手机去重测试 04”确认看到消息，但表示“刚好像没听到声音”，显示次数也未明确，本次不计可听去重通过。按要求以新标题“手机去重复测 05”连续发送两份相同有声NUDGE（1789830097893ms，合计24ms），连接正常；等待实际显示与声音次数反馈。

用户确认“手机去重复测 05”只显示一次但无声；随后声音开关仍开、点击Test sound也无声且显示Test sound played。显示去重通过，返回后的声音恢复失败，不被先前03的通过覆盖。网页发现缺少提示音AudioContext生命周期处理，已改为离开页面释放旧实例、返回或用户交互时按偏好恢复，并防止过期实例复活；恢复过程不补播声音。15项Chrome定向测试（含4项新增）、analyze、真实AudioContext/合成生命周期4项E2E、Web Release和26.2 build通过，66项JUnit通过。新本地运行包 `a56d2814392ef9d9c3b084e3429cbddc1fc2417bfd57cff0c473a281fe0f3927` / Web `ca4d7352918dc38fcca37d9338314f159d48b758e12f7308a933dfcf59f5a0c1`，49资源及HTTPS采样一致，已重启回原服。等待手机刷新后复测，尚不宣称根因/修复获真机最终确认。[证据](tailscale-integration/evidence/2026-09-19-ios-safari-sound-resume.md)。

2026-09-20：用户说明没有刷新Safari页面，而是退出连接后重新进入，此时Test sound可以发声。该观察证明本次声音恢复，但不能确认该页面已加载a56d2814 / ca4d7352的新Web构建，也尚未完成修复后“切后台→返回→提醒”复验。不能把重新连接可听直接计为音频生命周期修复通过。当前明确的证据仍是此前开关开启、Test sound played但实际无声，以及源码缺少音频实例的后台/前台生命周期处理；未直接读取失声时iPhone AudioContext或底层输出状态，具体Safari内部原因仍是有依据的假设。下一步先明确刷新获取新代码，再验证同一页面从后台返回后的新提醒。

2026-09-20 用户睡醒后继续iPhone Safari验收。电脑端MCP可用，当前无控制客户端连接；存在休眠状态及倒计时，本轮不清除真实游戏状态。HTTPS返回200，main.dart.js哈希仍为ca4d7352918dc38fcca37d9338314f159d48b758e12f7308a933dfcf59f5a0c1，与网页音频恢复修复包一致。先引导手机明确刷新后连接，再继续基线声音及后台返回复测；尚无新增手机通过结论。

2026-09-20：用户因ImagineFun服务器今日过载，明确要求明天再继续测试。按用户请求暂停人工验收；过载是用户报告的环境情况，不记作MonkeyCraft缺陷。当前本机26.2音频恢复修复包仍为a56d2814 / Web ca4d7352，HTTPS资源已核验。手机尚未明确完成本次刷新和修复后的前后台声音复测；不将昨夜退出重连后可听计为修复验收通过。下次先确认原服务器恢复，再让iPhone Safari刷新整个页面并连接；依次验证前台Test sound基线、切后台返回后的提示音与去重，随后继续计时更新/取消及横竖屏触控。此次暂停未发送测试提醒或改动游戏/连接状态。


2026-09-21：用户授权优先自主推进本地 Android 模拟器验收，随后要求先落盘已发现问题。已建立 `doc/tailscale-integration/KNOWN_ISSUES_HANDOFF.md`，分别记录 Safari 提示音恢复、iOS 原生 OpenAudioMC 恢复、PC/手机音频抢占、Android E/ESC 未闭环、Live Activity 到点显示边界；列明构建、历史证据、下一步和通过标准。此次交接不新增任何验收通过。当前探测 ADB 无设备、Minecraft DebugBridge 离线，已启动保留数据的 MonkeyCraft_Roadmap_Test（2048MB）并开始当前源码 Android Release 构建，后续结果另记。没有操作实体手机、提交或发布。

2026-09-21 Android 模拟器自主验收：当前源码正式包保留数据升级、连接真实26.2，定位库存键积压导致E无法关闭且ESC后重开的真实问题，四Mod InputHandler最小修复，26.2部署后E→E/E→ESC以及Home释放Sneak通过。同时复现原生重复NUDGE产生两条通知，共享调度层补一秒/32项去重及失败可重试，最终APK 23c543a3系统层重复仅一条、窗口后可再投递。Flutter229、Chrome28、Android JVM11及四版JUnit66/61/61/61通过；四新JAR 49项Web资源一致，旧版三包尚未部署。精确权限default时实际晚约33.885秒；走App Allow授权后，最终包强制深度IDLE中到点+14ms投递、恢复及GUI重连未更新通知；A→B/重复/取消、通知限额、权限拒绝再允许、旋转与4000重连通过。本人Tailscale未授权，仅验启动自动打开登录及Cancel后LAN可用。首次Flutter测试与Release并行导致生成注册器integration_test编译冲突，顺序重建通过并保留失败日志。详细证据及命令见 doc/tailscale-integration/evidence/2026-09-21-android-acceptance.md；十分钟连续观察仍进行中，不提前计通过。

2026-09-21 收尾：Android正式包611.051秒/18次采样保持同进程与连接；系统解码实例5904输入帧、5903延迟配对，应用错误日志为空。Android Chrome共享Flutter网页另在默认模拟器GPU出现VideoDecoder错误及Chrome GPU进程崩溃，保留失败；同AVD保留数据切SwiftShader后1290解码帧/0错误、无Chrome GPU失败日志，旋转/身份保留/后台恢复/触控释放/静音系统通知通过，返回后重复NUDGE提示音调用仅一次，不宣称听感。详细边界、自动化初始失败和软件对照在2026-09-21-android-acceptance.md。测试Chrome标签、ADB映射、旋转及Doze/电池覆盖已清理/恢复，模拟器与本轮启动的26.2正常关闭，无控制连接/待发测试计时/按键残留，保留userdata。下次实体手机验收先启动26.2，再从交接文件继续。
# 2026-09-21 自主收尾续跑（阶段起点记录；结果见顶部最新节）

用户确认按“旧版真实回归 → 音频交接/倒计时 → 统一产物 → Pages候选/发布文档”推进。主checkout `claude/web-m2-m3`，开始时314条dirty/untracked记录；未提交、推送或发布，手机未动。原始输出 `outputs/closeout-2026-09-21/`。

- 原子部署上轮三个旧版背包修复包并备份之前JAR。26.1与1.21.11共享Flutter浏览器通过错误密码拒绝、H264、四次缩放、E/ESC、Shift失焦释放、刷新凭证恢复、code4000受控重连、60秒每15秒有新帧且零解码错误。另以实际InputHandler完成E/E，screen=null、队列0、按键false。1.21.11首次资源包下载超时导致用例未进世界失败，保留后重跑通过。1.19复用既有验收世界，正在进行相同回归。本轮loopback浏览器不等于远端HTTPS或手机。
- 音频发现App INFO状态被四版Mod空分支吞掉，ImagineMoreFun没有音频交接订阅。正在补已有INFO事件转发、App active意图与断开顺序、IMF暂让音频与恢复原意图。修改涉及本仓库及`/Users/cusgadmin/if-local/imf`音频服务/兼容监听/测试；IMF其它dirty文件保留。新逻辑尚未完成真实验收，不算问题关闭。
- iOS Live Activity当前使用系统计时文本；本地通知到点不会自动执行结束Activity。后台显示边界与恢复/取消清理分别验收，不以到点通知替代Activity结束。


2026-09-21 本轮最终收尾：三版最终Mod均已完成实际核心回归；用户追加的1.19 MCParks真实音频路径已由最终Android Release正常GUI及系统层完成，详情见本轮证据。iOS正常签名包、Android正式包、四Mod、配套IMF与Pages候选均已归档并记录SHA。99文件Pages范围和共享App交集已具体化，未提交或发布。游戏和模拟器正常退出，1.19失焦暂停true与音量50%恢复，按键/连接/媒体租约清理，用户数据保留。最终git diff --check通过；历史失败保留。剩余人工步骤已压缩，不把构建/模拟器结果替代真机与公开origin验收。

2026-09-23 iPhone Safari人工复验：当前26.2提供的JS为26bc49dd，用户确认首次Test sound及切其他App返回后新NUDGE可听。锁屏返回复测03明确显示但无声，现有恢复修复尚未闭环；02因用户走神不计结果。保留现场继续诊断，详见tailscale-integration/evidence/2026-09-23-iphone-safari.md。

### 2026-09-23 Safari 提示音候选修正（真机待复验）

用户确认锁屏返回测试03横幅正常但失声；随后Test sound、自动提醒04及IMF ride完成提醒均可听。记录为一次间歇失败，不认定为必现。旧实现每次隐藏close已启用的AudioContext，返回在无手势时新建，可能丢失播放许可；尚未捕获iPhone底层状态，因此不是已证明的WebKit根因。

候选保留原AudioContext，前台resume并进行有界恢复检查；仅当300ms内currentTime不推进且state=running才suspend/resume原实例，1秒补查interrupted状态。后台取消恢复，不在生命周期自动新建，不补播旧提醒，不使用保活音视频。参考Web Audio allowed-to-start规则（https://www.w3.org/TR/webaudio-1.0/）及WebKit历史running/时钟停止报告（https://bugs.webkit.org/show_bug.cgi?id=263627）；历史报告不能当作当前iOS故障的确证。

本轮`python3 tool/run_browser_tests.py --flutter /Users/cusgadmin/if-local/flutter/bin/flutter`：初次编译暴露构造参数pageHidden遮蔽getter，修正this.pageHidden后重测33项通过（音频生命周期9项，模拟授权与时钟，不是真机Safari）。`flutter analyze`无问题。日志在`outputs/safari-audio-2026-09-23/`。Web/26.2构建和运行验收进行中；旧版Mod及Pages仍为此前资源，新候选未经发布，不把Sep21的哈希或发布验证沿用到本次修改。

2026-09-23候选已部署并运行：Chrome自动化33项通过，analyze无问题，Web Release成功，26.2 Gradle build成功且本轮JUnit 66项零失败。构建结束后验证全部49项Web资源逐字节一致、5个nested JAR完整（含monkeycraft-api），备份旧JAR后原子替换。JAR SHA `19ea7e9be774ed3d3d1e1fe7bedddf08a22fb9965b3067b39e52c11cc98945ed`；Web JS SHA `32617edba0a8f442e7e04ee732740a00070a4c89e6560aade5f5994fc1d4a1ae`。旧游戏PID53299正常退出；第一次nohup启动请求没有新进程，45秒等待超时，改为独立会话Popen启动后桥接恢复，真实26.2重新进入mp.imaginefun.net。HTTPS200且实际返回JS与候选一致。当前无客户端连接；接下来只请用户完整刷新手机Safari并连接，真机声音仍待复验。

本轮未修改Java/native音频实现，未重建其余三个Mod或Pages候选，未提交/推送/发布。Sep21的Pages候选归档依然是旧音频代码，不代表本次候选。原生iPhone App园区音频是另一个待验问题。

2026-09-23真机Safari新候选验收进展：完整刷新并连接、Test sound、连续两轮锁屏返回新提醒、静音消息、相同消息去重均获用户确认。用户已关闭Reminder sounds，最后检查09已发送，等待确认。用户明确要求此项之后不追加该部分测试，除非静态检查发现强而具体的未解决风险；已同步到剩余步骤与交接清单。不把取消的偏好关闭跨后台实测写成通过。

2026-09-23 Safari本部分验收关闭：用户确认最后检查09可见但无声；新候选真实手机的基线、连续两次锁屏恢复、静音、去重、声音关闭偏好均通过。已同步TEST_MATRIX、KNOWN_ISSUES_HANDOFF、REMAINING_ACCEPTANCE_STEPS和专项证据。遵照用户要求不追加本部分测试，除非静态检查发现具体且重要的风险；未测项保留事实边界。下一手机待办为原生App园区音频恢复，旧版Mod/Pages资源同步仍待开发收尾。

2026-09-23用户最终验收决定：Safari完整、功能正常，App提醒功能按已通过处理；不在其他Minecraft版本重测，Android最多简短抽查，测试范围删减。TEST_MATRIX已改为简短功能状态表，旧矩阵完整移至evidence/2026-09-23-test-matrix-before-simplification.md仅供追溯；REMAINING_ACCEPTANCE_STEPS及KNOWN_ISSUES_HANDOFF同步，历史长清单不自动恢复为任务。不增加未执行的实测证据。原生园区音乐和平台特有Tailscale问题仍独立收尾。本次仅文档调整，不运行新增测试。

### 2026-09-23 发布验收再次收缩（用户明确决定）

主要功能正常即可，次要功能本轮不再测试；默认不安排用户听感或重复手机操作，取消刚列出的Android提醒抽查。已通过主要路径不因换包、版本或一般性担忧重验。本轮仅静态阅读与文档修改，没有发送更多测试提醒或启动测试套件。

代码核对：iOS OpenAudioMC兼容脚本不依赖diagnostics，正式_initialize在文档启动阶段注入；仅匹配指定域名No Sleep视频，connect先报告active，清理/失败路径归还状态。现有模拟器因果对照及恢复证据支持修复收尾，未发现需要再次占用手机的具体问题；取消最终听感、锁屏/Home、交接强退/重启组合。通知去重共享调度层已有权限后去重、短时上限和异常可重试逻辑及既有测试；不再重复iOS最终包检查。Live Activity00:00边界保留说明，不逐项测试。

TEST_MATRIX、REMAINING_ACCEPTANCE_STEPS、KNOWN_ISSUES_HANDOFF均改为核心功能和最小发布动作；详细交接已存档。P4发布只保留产物/来源核对和公开入口一次主要连接；路线页增加最新用户范围覆盖。真正剩余是资源与正式包整理、Android内嵌首次授权/连接（若本次发布该入口）、发布范围审批及公开入口。取消的环境/次要检查不伪造为通过，也不再作为发布前阻塞清单。

2026-09-23用户进一步明确：此前Windows/Linux联网和原生App声音一直正常，不接受仅因环境覆盖不完整或近期少量改动安排重验。当前未指出具体Windows/Linux联网回归依据，删除原生联网复测；原生App全部声音检查（含播放、听感、静音、锁屏/Home返回）取消。此要求已写入路线最新覆盖、矩阵、剩余事项和交接约束；历史未测事实保留，但不形成待办，不伪造新测试通过。此次仅更新文档，没有运行相关测试。

### 2026-09-23 最终验收范围覆盖

**当前最高优先级范围（2026-09-23用户更新）：只处理和验证直接属于本次Tailscale或新网页端的改动；其余功能按无实质变化、此前正常则继续正常处理，沿用既有结论，不排查、不补测、不列发布门槛。这是验收范围决定，不是声称Git没有其他差异，也不撤销已有代码。范围内仍只确认主要功能，次要功能不测试；已完成的Safari不重测。**

此约束覆盖此前“最终原生包音频”“全平台补验”等待办表述。只保留Tailscale所需产物、尚未走通的主要连接入口、新网页端资源同步与公开入口交付；既有范围外证据直接沿用。已同步路线、TEST_MATRIX、REMAINING_ACCEPTANCE_STEPS、KNOWN_ISSUES_HANDOFF及P4网页发布文档。未运行测试，未撤销代码，未取得新的提交/部署授权。

### 2026-09-23 Android实体手机安装与验收范围

用户选择Android内网连接，明确表示其确认成功后不再深究Android；不再要求内嵌授权，结果仅记LAN。该要求已同步矩阵和交接。检测到唯一USB已授权实体手机REA-AN00/Android15/arm64；原安装1.4.0(8)，使用已归档正常Release 1.4.2(11)，SHA256 906884a725e2a3e8721d850b1696a8ec054a6e14714c2426ef2089f9203b51ab。adb install -r成功，未卸载/清除数据；读回安装base.apk哈希与候选一致，版本11。启动MainActivity返回Status ok。只进行部署必要核对，未运行功能测试；等待用户内网连接确认。安装证据outputs/android-phone-install-2026-09-23/install.json。

2026-09-23用户确认实体Android安装后内网连接成功，按其要求Android验收完成，不再追加测试。用户询问IP连接配对按钮：静态阅读login_screen/login_auth_policy/pairing_eligibility及Mod NetworkUtils，确认RFC1918和100.64/10 IPv4支持配对；Pair instead仅在手机密码输入为空且显示密码模式时出现，有已保存/输入密码会隐藏；并非要求电脑未设置密码。未读取用户密码、未修改代码或进行新的手机测试。

### 2026-09-23 GitHub Pages候选准备完成

按用户要求处理Pages且仅确认主要入口。只读`gh api .../pages`确认已有workflow模式、HTTPS开启；master仍为ace51c9。公开首页200，公开build-provenance.json当前404，仅保存发布前基线，不猜测新版本已上线。

现有99文件候选仅两处源文件变化：已验收的Web通知平台与其生命周期测试。Pages工作流按范围移除flutter test、Chrome功能套件和provenance工具测试；保留依赖锁、analyze、Release和来源记录。新增doc/GITHUB_PAGES.md，共100文件。以独立临时索引生成精确补丁（未修改主索引，无commit），所有已改共享lib文件均包含；未包含原生工程、Mod、helper、输出和账号配置。

命令：`flutter pub get --enforce-lockfile`、`FLUTTER_BIN=... MONKEYCRAFT_PAGES_ALLOW_DIRTY=1 MONKEYCRAFT_FLUTTER_FRAMEWORK_COMMIT=90673a4... bash tool/build_web_release.sh /monkeycraft/ build/pages`均通过。构建在主checkout完成，Mod的root Web资源事先备份并在finally中恢复、逐文件一致。49资源/provenance全部匹配，Pages main.dart.js SHA32617edb与已验收Safari完全一致。未新增功能测试。本地provenance dirty=true/commit=null，未冒充发布提交。

精确范围、补丁、源文件/产物哈希、构建日志和verification.json位于outputs/pages-release-2026-09-23/；补丁SHA f2f377525603e9dc0acfd86f009371c65b7280823b16fce3fb1d70da05116934。主索引仍空，未commit/push/dispatch/deploy。下一步取得此100文件范围的明确发布许可，再发布并核对一次公开入口/真实游戏连接，不重验Safari/Android或声音。

### 2026-09-23 授权后的分组提交

用户明确要求“提交到master”，随后要求其余改动也陆续commit。已按精确批准补丁提交100文件为6a67a9e，并推送origin/master；未触发Pages部署。随后分组提交移动端集成e53d153、helper c2fcc00、四版Mod及资源构建工作流5d0aaff，以及历史Web参考改动。主checkout未切换、未建worktree；构建产物、exports、原始诊断输出和未采用web-tailscale实验留本地，不纳入本批提交。

本轮仅执行Java仓库规定的四树spotlessApply，均成功；未新增或重跑功能验收。原生依赖.patch文本自带统一diff上下文空格与制表符，保留正确补丁格式，没有按普通源代码去剥离它们。Android独立spike脚本引用的标准Gradle wrapper JAR此前被上层忽略，本次随脚本补入，并仅对该文件设置忽略例外；不提交生成的native库、账号状态或安装包。代码候选的凭证特征核对未发现匹配项，日志留outputs/commits-2026-09-23/。后续文档提交包含精简后的验收范围和已完成Safari/Android结论，不能用旧快照复活测试要求。

### 2026-09-23 CI 干净环境修复

用户指出近期 CI 连续失败。本轮读取 GitHub Actions 原始失败日志，不重开 Safari、Android 或声音人工验收。最新 d27eba4 的 Flutter Web analyze、既有测试、Release 构建已通过；Android 在 SDK 安装阶段失败（setup-android 默认请求已不存在的 tools 包），iOS 在 native 构建前因缺少 rg 失败，helper 因 cmd/monkeycraft-tailscale-helper/main.go 未纳入 Git 而失败，四个 Mod 被依赖关系跳过。前一笔 6a67a9 运行的仍是旧 TypeScript lint，失败属于历史工作流，不能混作当前 Flutter Web 失败。

修复提交 279b2be：SDK 明确只请求 platform-tools；固定 native 编译使用已安装 NDK 28.2；iOS 的单个固定文本计数改用系统自带 grep；helper 忽略规则限定根目录二进制并补入现有入口源码。APK release 工作流同样补齐 Java/Go/SDK/NDK 和 native 库编译，未创建 release/tag 或部署 Pages。shell 语法与 diff 检查通过；GitHub 全量构建运行 35821423775 已开始，结果待后续记录。原始日志保存在 outputs/ci-repair-2026-09-23/。

第一轮修复后的云端结果（35821423775）：Flutter Web、Android（含 APK 构建、native 登录单测和打包校验）、iOS 未签名 Release 均成功；helper 四平台编译、单测和 race 检查成功。Linux 隔离 tailnet 集成检查暴露第二层问题：go.mod 未完整记录带 integration 标签的跨平台传递依赖，-mod=readonly 正确拒绝运行。使用仓库要求的 Go 1.26.6 执行 go mod tidy，保留 Tailscale v1.102.3 及原有依赖版本，仅补齐间接依赖和校验和；GOOS=linux CGO_ENABLED=1 go list -mod=readonly -tags=integration -deps -test ./internal/engine 已成功验证依赖解析。实际 Linux 集成执行仍以接下来的 CI 为准，不把本地解析当作测试通过。

APK 发布流程增加与 CI 一致的 native 打包校验，并修正产物重命名的 shell 引号。使用 actionlint v1.7.12 检查 build/release/release-flutter-apk/pages 四个工作流全部通过；本机原有 v1.6.2 不认识现代 runner、Pages 权限及布尔输入，其过期诊断未用于修改有效配置。未发布 App、Mod 或 Pages。

最终结果：修复提交 18a26a6 的 GitHub Actions 运行 [35822251652](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/35822251652) **8/8 全部成功**：Flutter Web、Android、iOS 未签名 Release、helper（四平台构建、常规/race/隔离 tailnet 集成检查）、四个 Minecraft Mod 构建及已有测试。两笔修复 279b2be、18a26a6 已推送 master。明细见 [CI 修复证据](tailscale-integration/evidence/2026-09-23-ci-repair.md)。本次没有扩大人工验收或发布产品。最终结果用仅文档的 [skip ci] 提交记录，不重新触发已通过的构建；原有失败运行仍保留。
