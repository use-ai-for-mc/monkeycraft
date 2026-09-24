# Flutter 浏览器内嵌 Tailscale 接入候选

## 界面与实现

直接复用 Flutter LoginScreen、TailscaleLoginSheet、设备选择、配对及 StreamScreen。浏览器主页把 Connect with Tailscale 作为主要入口，地址连接作为次要入口；电脑列表以名称和在线状态为主，仅重名设备显示地址。桌面表单限宽520，手机使用可用宽度。没有嵌入POC页面、调试日志、WASM按钮或设备密钥。

浏览器实现使用现有TailscaleClient/TransportFactory接口，Go/WASM在Worker内按需启动。JS持久状态采用IndexedDB，初始化先读取再启动节点；Web Locks禁止两个页面同时使用同一身份。Go侧支持非临时节点，并让logout返回可等待的Promise。Cancel/stop释放连接与Worker而保留身份，Sign out清除身份。登录窗口在用户点击时同步创建，异步收到受限的HTTPS Tailscale登录地址后跳转，避免等待启动后被浏览器拦截。

修复现有Dart TCP/WebSocket适配的握手合并HELLO丢失、未监听时消息丢弃、写入未串行化、部分写入、超时迟到连接释放及大帧限额。浏览器资源按document.baseURI解析，支持Pages子目录。成功记住的Tailscale连接会在下次打开时恢复节点并自动选择原电脑；直接连接流程仍保留。此自动恢复已在本轮真实Chrome、真实账户和26.2游戏连接中验收。

Pages构建固定Go工具链及已有模块锁文件，只打包worker/RPC/存储/WASM/runtime/LICENSE/VERSION；构建与来源校验拒绝不完整运行时和debug页面，并校验二进制哈希。根路径Mod构建默认不启用WASM，保持现有资源包装约束；Pages工作流显式启用。没有修改或部署Mod、原生App或线上Pages。

## 本轮验证

- Flutter工程目录执行flutter analyze --no-pub：无问题。初次误在仓库根运行扫描到了outputs里的历史备份，不能当作工程分析结果；没有为此修改用户备份。
- flutter test --no-pub test/stream/transport/tailscale_web_channel_test.dart test/stream/transport/ws_frame_test.dart test/stream/tailscale/tailscale_login_sheet_test.dart test/auth/login_screen_tailscale_entry_test.dart test/auth/credential_store_test.dart：30项通过，包含18万字节分段视频和与HTTP升级合并的HELLO回归。
- node --test web/tools/write-pages-provenance.test.mjs：7项通过。旧测试仍期待早已移除的setup-chrome，已按当前Pages工作流及新增固定Go动作修正期望，没有放宽固定版本检查。
- Node RPC、WS测试通过，JS/shell语法及diff检查通过；actionlint v1.7.12检查Pages工作流通过。
- 以Go1.26.6、固定Tailscale v1.102.3和readonly模块锁构建WASM及Flutter release成功，main.wasm SHA256 687e547d8217d08bd3fdb1a8a40a9a4f866793a215f22addf598b56736eca246。候选来源记录明确dirty=true、不冒充已发布来源。
- 真实Chrome加载共享Flutter页面；点击Tailscale后依次显示准备连接、登录按钮、外部Tailscale授权页。桌面1920和窄屏390布局已实际查看，无实验页面。窄屏Chrome不是实体iPhone Safari。
- 在浏览器调用state-store-test.js使用独立临时测试数据库：写入/关闭/重开保留最新值，同名并发持有被拒绝，clear后的迟到写入不会恢复身份。测试数据库已清除。这不等同于真实Tailscale账户刷新恢复。

## 用户授权后的真实联调与修复

用户批准持久浏览器节点后，共享Flutter设备列表显示电脑名称，选择PC内嵌节点monkeycraft并完成游戏配对，进入共享StreamScreen。先观察到PeopleMover休眠页，ride自然结束后看到真实游戏视频。没有发送游戏操作、重启Minecraft或改变系统Tailscale/Funnel。

首次刷新保留了Tailscale身份并自动选择原电脑，但再次请求游戏配对。检查只读取凭据条目数量和是否存在keyId绑定，不输出密码或身份密钥。确认CredentialStore.put的两个并发读改写（AUTH_OK保存keyId绑定、登录成功保存legacy条目）会互相覆盖，只剩legacy；HELLO含非空keyId时无法找回密码。新增concurrent bound and legacy writes retain both credentials测试在修复前失败（绑定项为null），串行化put后12项CredentialStore测试全部通过，Flutter分析无问题，Go/WASM和Flutter release重建成功。

初次重测仍加载旧浏览器缓存：main.dart.js实际资源大小3049036字节，新构建3049348字节。重新取得本地资源并正常刷新后，确认运行新构建；重新配对后保存2条凭据，其中1条为keyId绑定。随后再次刷新，未出现Tailscale授权或配对要求，自动进入游戏页并显示真实视频；DebugBridge读回connected=true、inWorld=true。这个结果与修复前后单测一致，关闭了本轮重复配对问题。

最终实际浏览器候选：main.dart.js SHA256 `37910e6df13231b3e1599262122429da933a47b36b2bb5c3bd7f81a469dd3768`；main.wasm SHA256 `156dd2a861cb4fa1bd2ba4dd5a7c43b262482753ad580fcf2ab835e07ba18625`。前文687e开头的WASM为前一轮构建记录，不混作本次最终候选。身份和游戏凭据均保留，测试结束主动Disconnect，回到登录页。调试接口批准配对遗留的电脑确认框已恢复到原页面。

修复命令（在flutter/monkeycraft目录）：

```sh
/Users/cusgadmin/if-local/flutter/bin/flutter test --no-pub test/auth/credential_store_test.dart
/Users/cusgadmin/if-local/flutter/bin/flutter analyze --no-pub
GOMAXPROCS=2 GOFLAGS=-p=2 GO_BIN=/opt/homebrew/bin/go \
  FLUTTER_BIN=/Users/cusgadmin/if-local/flutter/bin/flutter \
  MONKEYCRAFT_PAGES_ALLOW_DIRTY=1 \
  bash tool/build_web_release.sh /monkeycraft/ build/tailscale-integration
```

只检查新增Tailscale链路的主要功能，没有重新验收声音、倒计时、其他Mod版本或原生App。真实Chrome通过不等于手机Safari的WASM链路通过；旧Safari声音验收仍有效，不应因此重开旧矩阵。当前没有账户或授权阻塞，线上Pages仍是原已发布版本，本候选尚未部署。

本地入口http://127.0.0.1:8765/monkeycraft/；服务根outputs/flutter-tailscale-2026-09-24/www，映射候选flutter/monkeycraft/build/tailscale-integration。日志、结果位于outputs/flutter-tailscale-2026-09-24/，含credential-race修复前失败、修复后通过、分析及构建记录，不保存身份密钥、登录URL或用户完整peer列表。
