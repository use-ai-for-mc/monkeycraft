# iOS 正式 Release 覆盖安装（2026-09-19）

## 较早正式包

已核对正式签名 Release 的 `Runner.app` 主二进制 SHA-256 为 `c972475f0bcebf192d7630203466cce8c0d8269eab61ffe2727d2d8216cdbb17`，与 `2026-09-19-ios-formal-release.json` 历史记录一致。bundle ID、版本和构建号也与该记录一致。

通过 Xcode 的设备工具对已配对的物理 iPhone 执行覆盖安装；工具报告安装成功。随后读取已安装应用清单，确认 Monkeycraft 的版本为 `1.4.2`、构建号为 `11`。

本轮没有卸载 App、手动结束 App、启动 App、登录 Tailscale 或连接游戏，因此此记录只证明正式签名产物能够覆盖安装到该物理设备，不证明运行时连接、账户或游戏行为。


## 此前通知、设备地址与后台媒体修复包

第一次最新归档安装失败：内嵌 `objective_c.framework` 是此前模拟器的x86_64+arm64/platform7/adhoc产物。外层签名通过未识别这个生成缓存问题；失败包已在formal-release JSON历史中标INVALID。原有App仍在，未卸载、未清空数据。

使用 `flutter clean` 清除 build 和 .dart_tool，重新 pub get、串行 build ios --release 后，`tool/verify_ios_app.py` 核对所有Mach-O均arm64/iOS device platform2、所有嵌套bundle签名同Team且严格校验通过，再由ditto复制归档并复核。

该轮 Runner SHA-256：`e6d44e2800da94c7b34ad10890f2f0f467c8c39df3a54bbf842a4970bb9f4a50`。`devicectl device install app` 成功覆盖安装到同一物理iPhone，bundle为com.chenweikeng.monkeycraft / 1.4.2(11)。日志 `/tmp/monkeycraft-ios-device-clean-install.log`。没有手动杀App、卸载、清身份或启动新包。此前用户反馈的声音/锁屏/恢复结果不冒称新包感知测试；首次NUDGE授权修复与新后台音频仍需按新包做真机复验。


## 当前 OpenAudio 链接修复包

同一设备构建脚本再次执行clean→pub get→signed release→平台/嵌套签名校验，Xcode构建47.8秒。归档为 `outputs/roadmap-2026-09-19-audio-link/Runner.app`，复制后复核通过。当前Runner SHA-256为 `36e8c0d49cab460e527e344080d0a3d2cf1b272de132b386bb4c79b4098cb291`，App.framework SHA-256为 `e83b892abd130a90ded41c58af5a9ee31a065ac377151313d0124875dc2eee23`。

再次覆盖安装成功，devicectl apps读取确认同bundle、1.4.2(11)；未卸载、清数据、手动结束或启动手机App。安装日志 `/tmp/monkeycraft-ios-audio-link-install.log`。真实OpenAudio页面在iOS模拟器通过的结果不等于该设备包已通过真机声音、锁屏或后台验收；详见[链接与双模拟器证据](2026-09-19-audio-link.md)。
