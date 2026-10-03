# Mod 1.4.3 发布准备

更新时间：2026-10-03。用户决定先发布新版 Mod；本轮只准备版本和发布说明，由用户切出正式版本。尚未创建或推送 `v1.4.3` 标签，也未发布 GitHub Release。

## 范围与产物

| Minecraft | Mod 版本 | 安装文件 |
|---|---|---|
| 26.2 | `1.4.3-26.2` | `monkeycraft-1.4.3-26.2.jar` |
| 26.1 | `1.4.3-26.1` | `monkeycraft-1.4.3-26.1.jar` |
| 1.21.11 | `1.4.3-1.21.11` | `monkeycraft-1.4.3-1.21.11.jar` |
| 1.19 | `1.4.3-1.19` | `monkeycraft-1.4.3-1.19.jar` |

Flutter App 版本保持 `1.4.2+12`，不与本轮 Mod 一起发布。GitHub Pages 保持已上线的版本，本轮不触发重新部署。根路径 Mod 内置网页与 Pages 独立打包；Mod 包不包含 Pages 的浏览器 Tailscale WASM。

## 更新说明草稿

MonkeyCraft 1.4.3 adds Minecraft 26.2 support alongside 26.1, 1.21.11 and 1.19. It includes optional embedded Tailscale on the game computer, a shared Flutter browser client served by the Mod, and updated setup and pairing screens. LAN and system Tailscale connections remain available.

The existing iOS 1.4.1 client can continue using a reachable computer address and the Mod password, including scanning the password QR code. Its connection and video path have been verified using an iOS simulator build of the original 1.4.1 source against the current 26.2 Mod. The old app does not gain embedded Tailscale login or the newer pairing-request interface from a Mod update.

For the hosted browser client with its own Tailscale login, use <https://use-ai-for-mc.github.io/monkeycraft/>. Only one controlling client can connect at a time. Install the JAR matching your Minecraft version; do not install multiple MonkeyCraft version JARs in the same instance.

## 验证与切版

- 四处 `mod_version` 已统一为 1.4.3，26.2 的既有元数据测试断言同步更新。
- [旧版 iOS 兼容测试](tailscale-integration/evidence/2026-10-03-ios-1.4.1-compatibility.md)是本轮此前完成的实际模拟器结果；版本递增不新增手机、声音或跨版本功能验收。
- 版本提交 `cada46ffaee6bc78af83fd0a4286a85a1abf913f` 已推送 master，[CI 37095391727](https://github.com/use-ai-for-mc/monkeycraft/actions/runs/37095391727) **8/8 成功**，包括四个 Mod、共享网页、helper、Android 与 iOS 构建。本轮不发布原生 App。
- 实际下载四个 CI JAR 后核对通过：文件名与 `fabric.mod.json` 版本一致，根路径网页正确且四包一致，不包含 Pages WASM，四平台 helper 的大小及 SHA-256 与各自 manifest 一致。发布工作流经 actionlint 1.7.7 检查通过。旧本机 actionlint 因不认识新 runner 标签报错，未修改工作流去适应旧工具。
- 从准备完成的 `master` 提交创建并推送 **`v1.4.3`** 会自动触发 `.github/workflows/release.yml`，构建四个 Mod 并创建带附件的 GitHub Release。`flutter-v*` 是另一条 App 发布路径，本次不使用。
- 标签发布工作流会重新生成内置网页和四平台 helper；用户无需自行打包这些资源。正式标签由用户决定并操作，本轮不替用户创建。

## 已验证的 CI 候选

以下是切版前 CI 产物的 SHA-256；正式标签工作流会重新构建，不预先声称最终 Release 二进制哈希相同。

| Minecraft | SHA-256 |
|---|---|
| 26.2 | `1c0ac09758aedc81bfb73082eac47d04f95a60bcf154ca6a6f1cd85dc39e18f9` |
| 26.1 | `55d924dcf2f181179251c17be5ed3b8f46c8f2b5133b5217ecb0eeca3a9ffce6` |
| 1.21.11 | `2e53ac3b9830f4191a5be6beb95715b48820af68c0cd7eb6a803503c94aa5821` |
| 1.19 | `029863207d3b8286fa7717d30328ca415fc80f0e9e38574c24d708dee4784361` |

本地证据及安装包位于 `outputs/mod-1.4.3-prep-2026-10-03/`，包含 `ci-result.json`、`artifact-verification.json`、四个格式检查日志和 `artifacts/Artifacts-<mc>/`。没有部署到 PrismLauncher 或重新启动游戏。
