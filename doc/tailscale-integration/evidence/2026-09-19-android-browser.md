# Android Chrome 与 Pages 本地浏览器验收

日期：2026-09-19。结构化观察及产物哈希见 [JSON](2026-09-19-android-browser.json)。这是实际 Android 浏览器进程运行于模拟器的证据，不是真实手机或公开 GitHub Pages 的验收。

## 环境与边界

- 隔离 AVD `MonkeyCraft_Audio_Test`，Android API 36 / ARM64，`emulator-5556`，Chrome **133.0.6943.137**；不是当前最新 Chrome。无 Google 账户，使用 `-no-audio`，不证明声音可听。
- 先直接访问现有 Tailscale Serve HTTPS 页面，后访问由 ADB reverse 提供的 `http://localhost:4173/monkeycraft/`。后者因 loopback 是安全上下文，连接不同 origin 的真实 HTTPS/WSS 游戏入口；没有忽略 TLS 错误。AVD 经宿主网络到达系统 Tailscale，不代表 Android 自己的 VPN、切网或内嵌账户已验收。
- 游戏为真实 ImagineFun 26.2，运行的 Mod JAR 为 `097d40d51eaef9452d7f464b0b491b60f7a8a34ab6d4a816f56ee817372b84b5`。新浏览器功能由最终本地 Pages 构建提供；最新四个重新打包的 JAR 尚不能借用此次证据声称已在游戏运行。
- 密码仅由本地配置读取到测试进程内，未输出、截图或放入命令参数；未记住测试密码。保留等待本人 Tailscale 登录的 `emulator-5554`。

## 现场问题与修复

1. 旧代码在权限 `granted` 下调用 `new Notification`，Chrome 实际抛出 `Illegal constructor. Use ServiceWorkerRegistration.showNotification() instead.`。这与 [Chrome 官方 Android 通知说明](https://developer.chrome.com/blog/notifying-you-of-changes-to-notifications) 一致。新增仅负责通知点击的 Service Worker，显示通知使用其 registration；不新增 push 服务或离线缓存。注册和激活有等待上限，路径使用当前 base。旧 Flutter 清理只卸载当前 base 下的已知 worker，不删除同源全局缓存。
2. 实际按 Home 后，旧客户端在后台 socket 断开时耗尽三次重试，回前台停在登录页。新代码暂停后台重试预算，回前台重新连接；generation 防护避免显式断开或新连接被旧异步结果重新启动。认证拒绝仍立即显示错误。
3. 竖屏提醒横幅与顶部按钮同处一行。最小布局调整将其放到工具按钮下方；实测横幅顶部 56 CSS px，工具栏底部 48 px，无重叠。设计限定为高信息密度的游戏操作页，视频/输入优先，提醒次之；保持既有视觉，不新增卡片、装饰标签或页面区域。

## 实际结果

| 项目 | 观察与结论 |
|---|---|
| HTTPS Mod 页面 | 已鉴权并实际解码，504×960，dec 6、err 0；随后继续增加 |
| Pages 子路径 → 真实 WSS | 登录并实际解码，安全上下文成立；没有部署 GitHub Pages |
| 原生旋转 | 412×784 竖屏 → 864×304 横屏 → 竖屏；请求/服务端分辨率依次 504×960 → 960×338 → 504×960；cfg 1→2→3、解码持续增加、err 0 |
| 输入释放 | raw CDP 真实 touchStart 后游戏 SHIFT=true；Android Home 后 SHIFT=false。结束时仍 false |
| 静音通知 | 原生 Allow 后，真实 Mod 的 `Chrome silent D` 在隐藏页面显示，API 中 silent=true；Android 通知服务有对应 Chrome 记录，图标在 `/monkeycraft/icons/` 下 |
| 有声语义 | `Chrome sound F` 实际系统通知存在、silent=false；未证明可听声或系统是否发声，模拟器无音频输出 |
| 通知点击 | 从真实 Android 通知抽屉点 `Chrome tap return`，回到原 Chrome 游戏页面，hidden=false、focus=true、dec 211、err 0 |
| 后台预算 | 记录的两个隐藏样本相隔 **30,006 ms**，都保持 reconnecting attempt=1，没有回登录或消耗到 attempt=3 |
| 前台恢复 | 原生打开 Chrome 后，约 **1,052 ms** 内连接成功并新增解码帧（277→278）、err 0；单次本机观察，不是性能保证 |
| 显式退出 | 点击 Disconnect，再 Home/恢复仍是登录页，服务器 connected=false，不自动重连 |

这不承诺后台 socket 长期存活或页面关闭/锁屏后的实时通知。此次后台 socket 确实会丢失；通知只在仍能收到消息时验证。浏览器内计时去重/更新/取消由单元回归覆盖，此轮没有增加手机浏览器锁屏倒计时承诺。MCParks、真实手机音量与跨移动网络仍待验收。

## 自动化和异常记录

- Web 单元测试最终 160 项、TypeScript、Biome 通过；新增覆盖 SW 等待超时、拒绝、Pages 图标、声音异步去重/静音以及后台和迟到重连结果。
- 首次 Pages 自动化在真实 `showNotification` 因通知权限被无头 Chromium 拒绝而失败；保留 `pages-browser-initial.log`。测试调整为先对当前 origin 明确授权并检查实际 permission，仍被拒绝则单独跳过显示通知场景，不 mock 通知；资源、激活、刷新保留继续强制检查。Android 原生 Chrome 的上述通知结果单独成立。
- Pages 最终 Chromium 19 项通过，6 项明确跳过（2 个 Mod 默认入口场景、3 个未启用 live 场景、1 个该主机无头系统通知权限场景）。Mod 根路径 Chromium20项通过/5项跳过，WebKit19项通过/6项跳过（WebKit不执行两项Chromium通知测试）。
- 初次自动化选错精确 password/Controls 可访问标签，随后修正；原生浏览器 password label 包含显示密码按钮。Playwright 默认启用 focus emulation 的早期 Home 采样不能作为后台或释放证据；最终相关验收改用 raw CDP + Android Home，读取实际 `document.hidden`。没有把工具夹具失败当作产品缺陷。
- 尝试 Playwright Android 自定义 socket 启动未完成，改用 Chrome 标准 DevTools socket；不安装 driver APK。测试结束恢复唯一改动的 command-line flag 为 Default、恢复旋转设置、移除本轮端口映射并关闭隔离 5556。

## 复现入口与文件

常规验证使用 `web` 中的 `typecheck`、`lint`、`test`、`build`、`build:pages` 和 `playwright test --workers=2`；本机使用 Homebrew Node 与本地 node_modules 可执行文件，避免旧 Corepack 入口。实际 Android 首次 Enable reminders 使用浏览器原生 Allow，不以测试注入替代权限。

- 原始自动化日志：`outputs/roadmap-2026-09-19-android-browser/`。
- 后台/恢复原始样本：同目录 `hidden-session.json`、`resumed-session.json`。
- 布局截图：同目录 `pages-stream-portrait.png`（修复前）、`pages-stream-banner-fixed.png`（修复后）。
- 四版本打包校验：[最终资源清单](2026-09-19-browser-mod-artifacts.json)。

最短人工补测：真实手机用可达 HTTPS 入口连接 → Settings / Enable reminders 并允许 → 检查静音与有声 → Home 后返回检查画面和输入释放。真实声音、手机 Safari、最新 Android Chrome、公开 Pages 域名和公网到私网策略仍需独立记录。

## 最终 Mod 设备循环

最终26.2 JAR `6fabc18716455b4e5cc7c9fe965d89c2c360995a894dc5a0ad2498c98fa10b09` 随后原子部署并正常重启。旧游戏70132与helper70207均退出，新游戏46058/helper46362重入同服；内嵌IP与身份指纹保持100.82.132.32/1148163683，无新授权。新Mod提供的JS、CSS与notification-worker.js全部匹配本地dist，真实视频专项1项通过（总5.0秒），10分钟soak明确跳过。日志`mod-live-final.log`与`served-assets.json`。这次不把此前AndroidPages测试重复标作新Mod手机测试。

Pages根路径 `/` 的路径、凭证、worker保留和重连专项4项通过，系统通知权限场景1项跳过；之后将dist-pages恢复为 `/monkeycraft/`，逐文件SHA与现场项目路径产物完全一致。
