# Mod 1.4.3 发布记录

更新时间：2026-10-03。用户授权切版后，已创建并推送 `v1.4.3` 标签，指向通过完整 CI 的版本提交 `cada46ffaee6bc78af83fd0a4286a85a1abf913f`。[GitHub Release](https://github.com/use-ai-for-mc/monkeycraft/releases/tag/v1.4.3) 已正式发布，包含四个安装 JAR 和四个源码 JAR。

## 范围与产物

| Minecraft | Mod 版本 | 安装文件 |
|---|---|---|
| 26.2 | `1.4.3-26.2` | `monkeycraft-1.4.3-26.2.jar` |
| 26.1 | `1.4.3-26.1` | `monkeycraft-1.4.3-26.1.jar` |
| 1.21.11 | `1.4.3-1.21.11` | `monkeycraft-1.4.3-1.21.11.jar` |
| 1.19 | `1.4.3-1.19` | `monkeycraft-1.4.3-1.19.jar` |

Flutter App 版本保持 `1.4.2+12`，不与本轮 Mod 一起发布。GitHub Pages 保持已上线的版本，本轮不触发重新部署。根路径 Mod 内置网页与 Pages 独立打包；Mod 包不包含 Pages 的浏览器 Tailscale WASM。

## 已发布更新说明

MonkeyCraft 1.4.3 adds Minecraft 26.2 support alongside 26.1, 1.21.11 and 1.19. It includes optional embedded Tailscale on the game computer, a shared Flutter browser client served by the Mod, and updated setup and pairing screens. LAN and system Tailscale connections remain available.

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
