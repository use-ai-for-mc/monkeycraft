# P4：GitHub Pages 共享 Flutter 入口

**当前最高优先级范围（2026-09-23用户更新）：只处理和验证直接属于本次Tailscale或新网页端的改动；其余功能按无实质变化、此前正常则继续正常处理，沿用既有结论，不排查、不补测、不列发布门槛。这是验收范围决定，不是声称Git没有其他差异，也不撤销已有代码。范围内仍只确认主要功能，次要功能不测试；已完成的Safari不重测。**

更新时间：2026-09-23。当前正式网页从 `flutter/monkeycraft/` 构建，与 iOS、Android 共用界面和业务逻辑。`web/` 的客户端只作历史参考；录像夹具和 provenance 工具继续复用。旧文档已保存在 [历史快照](evidence/2026-09-21-before-closeout-p4_web_hosting_preparation.md)，其中独立客户端、pnpm 构建和存储描述不再代表当前方案。

## 发布范围

使用既有项目地址 `https://use-ai-for-mc.github.io/monkeycraft/`。无需购买域名或开设代理服务。浏览器通过用户系统 Tailscale 或 LAN 连接自己的 Minecraft；托管 HTTPS 页面使用可达且受信任的 HTTPS/WSS 目标，裸 LAN HTTP 或裸 tailnet IP 可达不等于浏览器可安全解码。Mod 内置 Flutter 网页继续保留。

页面不内嵌 Tailscale，不接入 `web-tailscale/` WASM POC，不新增账号、流量中转或多设备控制。更改这些架构或开办服务须另行确认。

## 本地候选

最新候选位于`outputs/pages-release-2026-09-23/`，以远端master当前`ace51c902f906e7ca061e6ee4b5fca94aff9cfb9`为基线，100文件。`RELEASE_SCOPE.md`为具体审批范围，`paths.txt`、`candidate.patch`、`source-manifest.json`分别保存文件清单、补丁及哈希。相对9月21日99文件候选新增公开发布说明，并同步已验收Safari修复、精简Pages工作流。

本轮只执行依赖锁解析、Pages Release构建及产物一致性核对，没有重跑功能套件。49项网页资源完整，main.dart.js为`32617edba0a8f442e7e04ee732740a00070a4c89e6560aade5f5994fc1d4a1ae`，与已通过真实iPhone验收的JS相同。源码、补丁和本地provenance如实记录未提交状态。

共享Dart源代码及其适配依赖属于候选，Swift/Kotlin/Mod/Go helper不包含。原生安装包、诊断输出、账号配置不发布。主索引未变，Mod根路径Web资源在Pages构建后恢复；没有创建worktree。用户已授权提交到master，并随后授权其他仓库改动分组提交。网页100文件已提交为6a67a9e并推送master；其余移动端、Mod/helper、文档另行分组。尚未触发Pages部署，公开站点未宣称已更新。

9月21日99文件候选及测试记录仅为历史证据，不当作此次公开发布。

## 可复查的构建链

`.github/workflows/pages.yml` 只允许手动运行，`publish` 默认 false，部署限 master。它锁定Flutter commit和Action的完整提交SHA，按依赖锁解析、静态分析、构建共享Flutter产物，再上传Pages artifact。按用户收缩后的范围，Pages工作流不再安装测试Chrome，也不重跑Flutter/浏览器/工具全套功能测试；测试源文件仍保留。

`tool/build_web_release.sh /monkeycraft/ build/pages` 生成项目路径产物；`/` 用于 Mod 内置网页。构建验证资源、base path 和浏览器适配边界，并排除 Tailscale 实验资源。`web/tools/write-pages-provenance.mjs` 的 Flutter 模式记录实际 Flutter/Dart 元数据、pubspec.lock、工作流、源码与 Actions run，以及每个产物文件的 SHA-256。6项 provenance 工具测试本轮通过。

本地脏工作区必须显式允许才能生成 provenance，且写入 `source.dirty=true`、`source.commit=null`。本轮候选另有普通副本来源清单，不冒充已发布提交。公开发布应由干净且已审核的源码提交生成；用户可对照对应 Actions run 和文件哈希。该清单便于审阅，不是独立签名或安全证明，也不承诺跨环境逐字节复现。

## 发布前与发布后

发布前：9月23日已验收的Safari修复及Pages候选已提交master；部署动作尚未触发。Safari已完整验收，不重新测试声音或其他次要功能。发布后：读取公开provenance核对来源和资源，只确认页面可打开并完成一次游戏连接；公开origin的实际连接是与本地不同的主要入口。取消配对失败、刷新身份、反复重连及各类提醒的完整重复矩阵。

`/monkeycraft/` 是路径而非 origin 隔离。GitHub Pages 同一 scheme/host/port 的其他页面共享存储安全边界；Flutter credential store 的键命名与按目标隔离不能阻止恶意同源脚本读取。正式凭证行为以 `lib/auth/credential_store.dart` 为准，不再沿用旧 TypeScript 存储描述。
