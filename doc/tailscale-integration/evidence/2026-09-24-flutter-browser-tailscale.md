# Flutter 浏览器内嵌 Tailscale 接入候选

## 界面与实现

直接复用 Flutter LoginScreen、TailscaleLoginSheet、设备选择、配对及 StreamScreen。浏览器主页把 Connect with Tailscale 作为主要入口，地址连接作为次要入口；电脑列表以名称和在线状态为主，仅重名设备显示地址。桌面表单限宽520，手机使用可用宽度。没有嵌入POC页面、调试日志、WASM按钮或设备密钥。

浏览器实现使用现有TailscaleClient/TransportFactory接口，Go/WASM在Worker内按需启动。JS持久状态采用IndexedDB，初始化先读取再启动节点；Web Locks禁止两个页面同时使用同一身份。Go侧支持非临时节点，并让logout返回可等待的Promise。Cancel/stop释放连接与Worker而保留身份，Sign out清除身份。登录窗口在用户点击时同步创建，异步收到受限的HTTPS Tailscale登录地址后跳转，避免等待启动后被浏览器拦截。

修复现有Dart TCP/WebSocket适配的握手合并HELLO丢失、未监听时消息丢弃、写入未串行化、部分写入、超时迟到连接释放及大帧限额。浏览器资源按document.baseURI解析，支持Pages子目录。成功记住的Tailscale连接会在下次打开时恢复节点并自动选择原电脑；直接连接流程仍保留。此自动恢复真实账户部分尚未验收。

Pages构建固定Go工具链及已有模块锁文件，只打包worker/RPC/存储/WASM/runtime/LICENSE/VERSION；构建与来源校验拒绝不完整运行时和debug页面，并校验二进制哈希。根路径Mod构建默认不启用WASM，保持现有资源包装约束；Pages工作流显式启用。没有修改或部署Mod、原生App或线上Pages。

## 本轮验证

- Flutter工程目录执行flutter analyze --no-pub：无问题。初次误在仓库根运行扫描到了outputs里的历史备份，不能当作工程分析结果；没有为此修改用户备份。
- flutter test --no-pub test/stream/transport/tailscale_web_channel_test.dart test/stream/transport/ws_frame_test.dart test/stream/tailscale/tailscale_login_sheet_test.dart test/auth/login_screen_tailscale_entry_test.dart test/auth/credential_store_test.dart：30项通过，包含18万字节分段视频和与HTTP升级合并的HELLO回归。
- node --test web/tools/write-pages-provenance.test.mjs：7项通过。旧测试仍期待早已移除的setup-chrome，已按当前Pages工作流及新增固定Go动作修正期望，没有放宽固定版本检查。
- Node RPC、WS测试通过，JS/shell语法及diff检查通过；actionlint v1.7.12检查Pages工作流通过。
- 以Go1.26.6、固定Tailscale v1.102.3和readonly模块锁构建WASM及Flutter release成功，main.wasm SHA256 687e547d8217d08bd3fdb1a8a40a9a4f866793a215f22addf598b56736eca246。候选来源记录明确dirty=true、不冒充已发布来源。
- 真实Chrome加载共享Flutter页面；点击Tailscale后依次显示准备连接、登录按钮、外部Tailscale授权页。桌面1920和窄屏390布局已实际查看，无实验页面。窄屏Chrome不是实体iPhone Safari。
- 在浏览器调用state-store-test.js使用独立临时测试数据库：写入/关闭/重开保留最新值，同名并发持有被拒绝，clear后的迟到写入不会恢复身份。测试数据库已清除。这不等同于真实Tailscale账户刷新恢复。

## 当前唯一联调阻塞与接续

新的持久浏览器节点需要用户批准。已打开Tailscale授权页并请求用户批准monkeycraft-web；尚未收到完成确认。此时不刷新正在等待授权的页面，不冒充真实Flutter游戏连接或刷新恢复通过。

用户批准后：让Flutter显示设备列表，确认游戏没有其他控制客户端后选电脑，完成一次配对/鉴权进入共享游戏页；随后刷新一次确认持久身份及已记住的连接恢复。只检查新增Tailscale链路的主要功能，不重新进行声音、倒计时、跨Mod版本或原生App验收。

本地入口http://127.0.0.1:8765/monkeycraft/；服务根outputs/flutter-tailscale-2026-09-24/www，映射候选flutter/monkeycraft/build/tailscale-integration。浏览器授权页及原Flutter页保留以接续；最终候选代码在独立预览页确认布局，原等待授权页仍运行本轮较早候选，批准后应完成身份保存再刷新到最终候选。代码已准备但不发布线上，避免把待验证接入直接替换已验收版本。

日志、结果位于outputs/flutter-tailscale-2026-09-24/，不保存身份密钥、登录URL或用户完整peer列表。
