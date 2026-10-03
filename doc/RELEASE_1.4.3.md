# Mod 1.4.3 发布记录

更新时间：2026-10-03。**当前状态：已按用户要求撤下 GitHub Release，并删除远端和本地 `v1.4.3` 标签，等待体积优化后的重新发布决定。** 原发布指向 `cada46ffaee6bc78af83fd0a4286a85a1abf913f`；下方发布运行、附件哈希与说明保留作历史记录，不代表当前可下载版本。

## 范围与产物

| Minecraft | Mod 版本 | 安装文件 |
|---|---|---|
| 26.2 | `1.4.3-26.2` | `monkeycraft-1.4.3-26.2.jar` |
| 26.1 | `1.4.3-26.1` | `monkeycraft-1.4.3-26.1.jar` |
| 1.21.11 | `1.4.3-1.21.11` | `monkeycraft-1.4.3-1.21.11.jar` |
| 1.19 | `1.4.3-1.19` | `monkeycraft-1.4.3-1.19.jar` |

Flutter App 版本保持 `1.4.2+12`，不与本轮 Mod 一起发布。GitHub Pages 保持已上线的版本，本轮不触发重新部署。根路径 Mod 内置网页与 Pages 独立打包；Mod 包不包含 Pages 的浏览器 Tailscale WASM。

## 已发布更新说明

MonkeyCraft 1.4.3 adds Minecraft 26.2 support alongside 26.1, 1.21.11 and 1.19. It includes optional embedded Tailscale on Windows x64 and Apple Silicon Macs, a shared Flutter browser client served by the Mod, and updated setup and pairing screens. LAN and system Tailscale connections remain available.

The existing iOS 1.4.1 client can continue using a reachable computer address and the Mod password, including scanning the password QR code. Its connection and video path have been verified using an iOS simulator build of the original 1.4.1 source against the current 26.2 Mod. The old app does not gain embedded Tailscale login or the newer pairing-request interface from a Mod update.

For the hosted browser client with its own Tailscale login, use <https://use-ai-for-mc.github.io/monkeycraft/>. Only one controlling client can connect at a time. Install the JAR matching your Minecraft version; do not install multiple MonkeyCraft version JARs in the same instance.

## 验证与切版

- 四处 `mod_version` 已统一为 1.4.3，26.2 的既有元数据测试断言同步更新。
- [旧版 iOS 兼容测试](tailscale-integration/evidence/2026-10-03-ios-1.4.1-compatibility.md)是本轮此前完成的实际模拟器结果；版本递增不新增手机、声音或跨版本功能验收。
- 版本提交 `cada46ffaee6bc78af83fd0a4286a85a1abf913f` 已推送 master，[CI 37095391727](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/37095391727) **8/8 成功**，包括四个 Mod、共享网页、helper、Android 与 iOS 构建。本轮不发布原生 App。
- 实际下载四个 CI JAR 后核对通过：文件名与 `fabric.mod.json` 版本一致，根路径网页正确且四包一致，不包含 Pages WASM，四平台 helper 的大小及 SHA-256 与各自 manifest 一致。发布工作流经 actionlint 1.7.7 检查通过。旧本机 actionlint 因不认识新 runner 标签报错，未修改工作流去适应旧工具。
- `v1.4.3` 标签已触发 `.github/workflows/release.yml`；[发布运行 37097301291](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/37097301291) 的资源、四个 Mod 和 Release 共六项任务全部成功。标签直接采用实际通过 CI 的版本提交；随后带 `[skip ci]` 的提交仅补充文档。`flutter-v*` 是另一条 App 发布路径，本次未使用。
- 标签发布工作流已重新生成内置网页和四平台 helper。实际下载四个正式安装包后，版本、根路径网页、四包共享网页哈希、无 Pages WASM、四平台 helper 大小与 SHA-256 均核对通过；Release 读回为非草稿、非预发布。

## 已验证的 CI 候选

以下是切版前 CI 产物的 SHA-256；正式标签工作流会重新构建，不预先声称最终 Release 二进制哈希相同。

| Minecraft | SHA-256 |
|---|---|
| 26.2 | `1c0ac09758aedc81bfb73082eac47d04f95a60bcf154ca6a6f1cd85dc39e18f9` |
| 26.1 | `55d924dcf2f181179251c17be5ed3b8f46c8f2b5133b5217ecb0eeca3a9ffce6` |
| 1.21.11 | `2e53ac3b9830f4191a5be6beb95715b48820af68c0cd7eb6a803503c94aa5821` |
| 1.19 | `029863207d3b8286fa7717d30328ca415fc80f0e9e38574c24d708dee4784361` |

本地证据及安装包位于 `outputs/mod-1.4.3-prep-2026-10-03/`，包含 `ci-result.json`、`artifact-verification.json`、四个格式检查日志和 `artifacts/Artifacts-<mc>/`。没有部署到 PrismLauncher 或重新启动游戏。

## 正式 Release 安装包

以下 SHA-256 来自正式发布页重新下载的文件。

| Minecraft | SHA-256 |
|---|---|
| 26.2 | `1c0ac09758aedc81bfb73082eac47d04f95a60bcf154ca6a6f1cd85dc39e18f9` |
| 26.1 | `5d95ab03d43c81ef83518b32ff4b951d412d8b4aaf7731934b3519414fd46f21` |
| 1.21.11 | `2e53ac3b9830f4191a5be6beb95715b48820af68c0cd7eb6a803503c94aa5821` |
| 1.19 | `029863207d3b8286fa7717d30328ca415fc80f0e9e38574c24d708dee4784361` |

正式发布证据和安装包位于 `outputs/mod-1.4.3-release-2026-10-03/`，包含发布运行结果、Release 读回、附件核验结果及四个安装包。

## 撤回后的网页精简

共享网页构建脚本现在先核对实际 Flutter buildConfig，仅对本地 CanvasKit / dart2js 构建移除 skwasm、skwasm_heavy、wimp 以及两套 CanvasKit 的符号文件，共11项。通用与Chromium CanvasKit的JS/WASM均保留。未知或WASM构建、缺失必需渲染文件、service worker仍引用待删文件时会在删除前失败。CI加入两项定向测试，覆盖正常裁剪、重复执行和四类拒绝情形。

本地Flutter release构建、发布目录校验、26.2 spotlessApply/build均通过；内置浏览器实载登录页成功，未观察到控制台错误或警告。26.2本地JAR为44,339,008字节，原正式包50,654,482字节，减少约6.32MB。逐文件比较确认网页仅少11个文件，其余网页字节不变；本地helper来自此前本机构建，元数据/二进制与CI包不同，不把本地JAR当作同源正式候选。没有重新发布或部署到运行中的Minecraft。

## 四平台 helper 分发调研（建议，尚未实施）

以撤回的正式26.2安装包里的四个helper为样本，测量其ZIP内占用与XZ压缩后的占用。x86使用XZ preset 6加BCJ过滤，arm64使用普通XZ preset 6；再计入外层ZIP压缩。四个平台解压后均逐字节与原二进制一致。

| 平台 | 当前ZIP内体积（MB） | XZ后再入ZIP（MB） |
|---|---:|---:|
| Intel Mac | 8.57 | 6.09 |
| Apple Silicon Mac | 7.95 | 5.66 |
| Linux x64 | 8.71 | 6.20 |
| Windows x64 | 8.73 | 6.21 |
| 合计 | 33.95 | 24.17 |

首选建议：保留通用JAR，helper以XZ资源携带，仅解压当前平台并按原始二进制SHA-256/大小验证，然后原子写入既有缓存路径。预计网页裁剪后整个JAR约34.6MB（加Java解压库与打包开销），不用用户选操作系统，也不新增下载依赖。[XZ for Java](https://tukaani.org/xz/java.html)提供纯Java解压，适合现有17/21/25目标。这里仅完成Python/liblzma压缩往返实验，单个样本解压约0.26–0.30秒；未测Java耗时，也未修改helper加载器。实现时需要缓存命中不重复解压、限制解压大小、校验后落盘及保留可执行权限。压缩不减少解压后的本机缓存或运行内存。

替代方案：按需下载平台helper能使基础Mod约10.4MB，首次开启内嵌Tailscale时再下载约5.7–6.2MB并缓存。代价是新增下载可用性、进度/重试、离线导入及分发维护工作；建议版本固定且原始哈希随Mod携带，不能执行未经固定校验的latest文件。也可发行平台专用包，保留离线能力但增加用户选包和维护成本。以上均为模型建议，不是新增项目规则。

功能裁剪未得到可直接采用的结果：现有构建已启用-s -w；本地Tailscale v1.102.3源码明确tsnet不导入完整condregister集合，不能假设移除daemon功能就有同等收益。试编译ts_omit_acme在上游tsnet.go:1423失败（local.Client.GetCertificate未定义），因此没有把该标签或上游补丁加入产品。官方[小体积构建说明](https://tailscale.com/docs/how-to/set-up-small-tailscale)主要讨论tailscaled；其UPX方案还会改变可执行文件形态并可能触发杀毒误报，本轮优先考虑普通资源压缩。

实验数据位于 `outputs/mod-size-investigation-2026-10-03/`，包含网页裁剪对比、Mod构建日志、`research/compression.json`和八个XZ样本；未发布实验二进制。

## 用户确定的平台范围

2026-10-03用户明确排除按需下载，并要求移除Linux x64与Intel Mac的内嵌Tailscale支持。发布脚本和四个Mod只保留Windows x64与Apple Silicon Mac程序；上文四平台XZ方案是此前调研记录，本轮没有实施XZ。平台选择、服务层及登录命令均拒绝不支持的平台，26.2设置面板显示说明与LAN/系统Tailscale替代路径。现有配置即便开启内嵌功能也不会尝试启动已移除的平台程序。Mod本身仍可用于这些电脑。

四个Mod的spotlessApply/build均通过；每棵树新增的平台映射与不支持主机拒绝启动测试通过。实际JAR只含darwin-arm64/windows-amd64，两份helper的大小与SHA-256符合manifest，网页冗余未回流。安装包大小：26.2为27,064,727字节，26.1为27,028,857，1.21.11为27,031,159，1.19为27,027,768。本地日志与附件检查在`outputs/mod-two-platforms-2026-10-03/`。未修改已运行游戏，未新建release/tag。
