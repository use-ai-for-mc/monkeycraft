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
- 版本提交的 CI 构建结果完成后记录在本文件；需要确认四个构建 JAR 内的 `fabric.mod.json` 版本与文件名一致。
- 从准备完成的 `master` 提交创建并推送 **`v1.4.3`** 会自动触发 `.github/workflows/release.yml`，构建四个 Mod 并创建带附件的 GitHub Release。`flutter-v*` 是另一条 App 发布路径，本次不使用。
- 标签发布工作流会重新生成内置网页和四平台 helper；用户无需自行打包这些资源。正式标签由用户决定并操作，本轮不替用户创建。
