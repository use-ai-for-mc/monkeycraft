# Tailnet 节点地址标识

日期：2026-09-19。用户在设备列表中只能看到名称，无法按地址核对电脑系统节点与内嵌节点，本次只修改 Flutter 的 peer 解码和登录选择页；没有部署 App、连接 Minecraft、访问登录 URL 或操作设备。

## 实现

- `TailscalePeer` 读取可选的 `tailscaleIPs`。旧 snapshot 未提供该字段时保持为空，原有名称、DNS 名称和 `nodeId` 行为不变。
- 列表副标题显示在线状态与 tailnet 地址；IPv4 优先，随后显示 IPv6。不会根据 hostname 推断节点类型，也不显示 status 中的其他节点私有字段。
- iOS 的 `TailscalePeerParser` 和 `TailscalePeerInfo.asMap()` 已从 status `Peer.TailscaleIPs` 解析并传递该字段；Android 的 `snapshot()` 亦已从同一字段传递。因此本次没有改变两端原生选择、拨号或身份逻辑。
- 选择结果仍只返回原 peer 的 `nodeId`、名称和端口；没有修改存储或 bridge 的 node identity 契约。

## 验证

执行：

```bash
cd flutter/monkeycraft
/Users/cusgadmin/if-local/flutter/bin/flutter test \
  test/stream/tailscale/tailscale_models_test.dart \
  test/stream/tailscale/tailscale_login_sheet_test.dart
/Users/cusgadmin/if-local/flutter/bin/flutter analyze \
  lib/stream/tailscale/tailscale_models.dart \
  lib/stream/tailscale/tailscale_login_sheet.dart \
  test/stream/tailscale/tailscale_models_test.dart \
  test/stream/tailscale/tailscale_login_sheet_test.dart
```

14 项相关测试通过，静态分析无问题，改动 whitespace 检查通过。widget 回归构造两个同为 `desk` 的节点：它们显示不同的 tailnet 地址；点击第二项后结果仍为 `nodeId=pc2`。模型回归还确认 IPv4 在 IPv6 前显示。
