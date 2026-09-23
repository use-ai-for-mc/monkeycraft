# iOS 内嵌 Tailscale 出口合规事实复核

日期：2026-09-19。本文是当前源码与构建配置的技术事实备忘，不是法律意见、出口分类、App Store Connect 申报，也不替发布人选择问卷答案。

## 当前可复核事实

- Runner 的 `Info.plist` 含有 `ITSAppUsesNonExemptEncryption = false`。内嵌 Live Activity 的 Widget `Info.plist` 也有相同值。
- Runner 的 Release 配置包含 `third_party/libtailscale/Link.xcconfig`；该配置在 `iphoneos` 构建中以 `-force_load` 链接 `out/libtailscale_ios.a`。当前 Runner bundle identifier 是 `com.chenweikeng.monkeycraft`，部署目标是 iOS 16.6。
- 固定输入为 libtailscale commit `80771313ac4127973677c993889fe215abcf1fbd` 和 `tailscale.com v1.94.1`。现有产物 manifest 记录设备 archive 为 `libtailscale_ios.a`，并记录构建依赖清单的摘要。
- 该依赖清单包含 `github.com/tailscale/wireguard-go`、`golang.org/x/crypto` 与 `github.com/ProtonMail/go-crypto`。这是当前打入 Runner 的 Go C archive 的构建输入，而不是仅由 iOS 系统提供的 HTTPS/TLS 调用。
- Runner 通过 libtailscale 创建节点并调用其 `tailscale_start` 和 `tailscale_dial` C API；随后本地 bridge 使用该连接。源码没有把该功能限制为仅 HMAC 或仅平台 HTTPS。
- Tailscale 的官方技术文档说明其 data plane 以 WireGuard 加密设备间通信，且其客户端带有其 `wireguard-go` fork；官方加密说明还列出了 WireGuard、TLS、Curve25519、ChaCha20-Poly1305 等相关机制。[Tailscale WireGuard 概览](https://tailscale.com/docs/concepts/wireguard)；[Tailscale encryption](https://tailscale.com/docs/concepts/tailscale-encryption)。

这些事实足以表明，旧的“只使用系统网络与安全存储、没有 VPN/proxy tunneling、没有用于保密性的 bundled crypto”的技术基础，不能覆盖当前含内嵌 Tailscale 的 Runner。

## 现有声明与文档的状态

`Runner/Info.plist` 的 `false` 值本身不说明其一定错误：Apple 允许在应用不使用加密，或仅使用可免于提交文档的加密形式时使用该值。但 Apple 明确要求在应用使用、访问、包含、实现或合并加密时，由发布人确定出口合规要求；Apple 也明确把“非 Apple 操作系统提供的行业标准算法”与“仅使用系统提供加密”区分开来。[Apple 出口合规概览](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)；[Apple 加密出口说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。

仓库中 `doc/APP_ENCRYPTION_DOCUMENTATION.md` 的旧版曾以无 VPN/隧道和仅系统网络/HMAC 为依据，确定宣称“不使用非豁免加密”。本轮已将该文件更新为当前技术事实和待发布人核实的状态；旧结论不能作为内嵌 Tailscale 版本的发布依据。`doc/tailscale-integration/MOBILE.md` 已较准确地要求在嵌入 WireGuard/Tailscale 后每次发布前重新完成 App Store Connect 问卷；本备忘为该步骤补充当前代码依据。

本次复核没有读取 App Store Connect 的实际声明、已批准文档、销售区域或发布主体信息，也没有检查最终上传 archive 的签名内容。因此无法验证现有 `false` 是否对应某份仍适用的批准结论，更不能得出是否需要 CCATS、法国材料或其他申报的结论。

## 发布人仍需确认的事项

1. 以本页的 Runner 事实为输入，在 App Store Connect 为本次新版本完成加密问卷；不要机械沿用旧版答案。
2. 确认发布地区，包括法国是否在销售范围内，以及发布主体是否已有可复用、仍适用的 Apple 加密声明或批准代码。
3. 由负责出口合规的发布人或法律顾问判断内嵌 WireGuard/Tailscale、第三方 crypto 依赖和实际功能如何对应 Apple 问卷与适用法规；若 Apple 流程要求材料，按其要求提交。
4. 核对将上传的实际 device archive：Runner 是否仍链接同一设备 `libtailscale_ios.a`，最终 bundle 的 Info.plist、版本号和签名是否与将作出的 App Store Connect 声明一致。Widget 的 plist 应随同 bundle 一并核对，但本次的核心加密功能在 Runner。

## 最短发布前检查

1. 固定将上传 archive 的 libtailscale commit、Go module、archive SHA-256 和依赖 manifest 摘要。
2. 复查 Runner 与嵌入 extension 的最终 Info.plist 中 `ITSAppUsesNonExemptEncryption` 及任何 `ITSEncryptionExportComplianceCode`；只在发布人完成当前版本评估后保留或变更。
3. 在 App Store Connect 绑定本次构建前完成加密问卷；如平台要求文件或批准代码，保存其记录并关联到构建。
4. 复查 App Store 元数据中任何“仅 HMAC、无 VPN/隧道、无 bundled crypto”表述，避免它们与当前功能冲突。

Apple 将最终申报责任留给开发者/发布人，并说明其评估按个案进行；本备忘只提供可审计的技术事实与操作检查项。[Apple：确定并上传加密文档](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
