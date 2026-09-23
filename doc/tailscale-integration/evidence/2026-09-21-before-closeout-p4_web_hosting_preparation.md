# P4：托管 Web 入口准备

日期：2026-09-19。用户已授权推进 GitHub Pages 的本地可核验发布配置。只读核对的当前仓库事实是：Pages 使用 Actions 作为构建类型、强制 HTTPS、仅 `master` 可部署、没有自定义域名。公开站点 `https://use-ai-for-mc.github.io/monkeycraft/` 当前返回 HTTP 200，但仍是历史 Flutter 产物；本轮新的 `web/` 尚未提交或发布。

`www.monkeycraft.com` 可能尚未购买、也可能不可用，用户会自行确认。下文名称只是候选入口，不代表已拥有域名；本地实现与验证可使用预览地址，最终域名不作为客户端开发门槛。当前首选 GitHub Pages 静态入口，沿用现有 HTTPS/WSS 直连方式；本地 `web/dist-pages` 已按项目路径 `/monkeycraft/` 构建并完成针对不可达目标的重试验证。提交、推送、触发远程工作流、公开部署、域名或 Pages 设置变更仍需要单独授权；本轮均未执行。

## 可复用基础

正式浏览器客户端在 `web/`，已由 26.2 Mod 从 jar 静态提供。它已经具备配对、HMAC、WSS、视频、输入、聊天、地图、页面提醒和重连能力。当前浏览器可直接访问 LAN 或系统 Tailscale 可达地址；它不自行运行 Tailscale。

`web-tailscale/` 是未跟踪 WASM POC。它可作为未来研究材料，不能直接纳入托管入口：实际 tailnet 登录、DERP 视频性能、移动浏览器和安全审计都没有产品证据，且Worker向页面传递登录URL与现有文档承诺不一致，需先明确登录交互与凭证边界；该行为本身还不足以证明跨信任边界泄漏。

## 架构选项

| 选项 | 连接路径 | 优点 | 主要代价 / 依赖 |
| --- | --- | --- | --- |
| A. 托管静态网页，浏览器直连用户提供的 LAN 或 tailnet HTTPS/WSS 地址 | `www.monkeycraft.com` → 用户浏览器 → 用户自己的 Minecraft | 最大化复用现有 `web/`；没有代理保存游戏流量或用户凭证；保留现有 Mod 网页路径 | 用户浏览器必须能到达目标，需明确 HTTPS/WSS、地址输入与配对体验；手机浏览器限制仍存在 |
| B. 托管网页加受控连接代理 | `www` → 代理 → 用户的 Minecraft / tailnet | 可隐藏目标地址并集中做发现、TLS 与兼容处理 | 需要长期服务、账号、成本、流量与安全运营；代理如何安全进入每位用户 tailnet 是核心未解问题 |
| C. 浏览器内 WASM Tailscale 节点 | `www` → Worker/WASM 自己登录用户 tailnet → Minecraft | 目标是浏览器无需系统 Tailscale | 当前 POC 约 43 MB，使用窄上游补丁；需要用户登录、节点生命周期、DERP 性能、移动兼容与高风险安全审计 |

推荐先选择 A。它不扩大服务端信任边界，复用已经验证的 Web 协议和 MonkeyCraft 配对/HMAC，并让系统 Tailscale 与 LAN 用户继续按现有模式工作。B 与 C 都是独立产品项目，不应作为静态网站发布的隐含实现。

## 方案 A 的当前验证

- 静态构建、项目子路径与站点根路径、配对凭证隔离和手动工作流已实现；工作流的公开发布默认关闭。
- Android Chrome 133 / API 36 模拟器已从本地 Pages 构建连接真实 26.2 WSS，完成视频、系统通知、旋转、后台恢复与输入释放；见[现场证据](evidence/2026-09-19-android-browser.md)。这是模拟器和本地托管构建结果，尚非公开 Pages 或实体手机验收。
- 实际 Chromium 对不可达目标显示错误，恢复地址/密码编辑及连接重试；见[不可达目标证据](evidence/2026-09-19-pages-unreachable.md)。
- Mod 内置网页入口继续保留。公开 Pages 地址的端到端连接、真实手机 Safari 与最新版 Android Chrome 仍待完成。

用户已表达 GitHub Pages 偏好，本地静态入口和手动发布配置已就绪。默认项目地址可先使用 `<owner>.github.io/<repository>`，自有域名以后可选接入；域名尚未购买或确认不阻塞本地实现。仓库 Pages 设置和账户权限已按本文顶部事实完成只读核对；提交、推送、远程工作流、公开部署或 DNS 修改仍没有授权或执行。

工作流采用官方静态产物上传/部署机制。依据：[默认地址](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)、[自定义工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

## 发布产物可核验性

每次 `build:pages` 都会生成公开静态文件 `build-provenance.json`。它记录构建所对应的源码提交、工作流提交、Actions 仓库/运行 ID/重试次数、Pages base path、工作流文件 SHA-256、完整提交 SHA 锁定的 Action 引用、实际 Node 版本、精确声明的 pnpm 版本、`pnpm-lock.yaml` SHA-256，以及除 provenance 文件自身外每个发布文件的路径、字节数和 SHA-256。公开站点可下载该文件并复算文件 hash，再在对应 Actions run 核对源码与工作流。

CI 仅在检出目录干净且 `GITHUB_SHA` 与实际检出提交一致时，才会把源码提交写入 provenance；GitHub Actions 默认提供 `GITHUB_WORKFLOW_SHA`。本地脏工作树必须显式设定 `MONKEYCRAFT_PAGES_ALLOW_DIRTY=1`，产物会写入 `dirty: true` 和 `commit: null`，避免将本地未提交修改冒充为已发布提交。没有这个显式开关时构建失败。

Pages 工作流仍只允许手动触发，`publish` 默认 `false`。所有 Action 都锁定到完整提交 SHA，并在生成 provenance 时验证；没有远程工作流、提交、推送、Pages 设置或部署操作。

### 验证步骤与安全边界

`build-provenance.json` 不是签名、证明书或独立安全保证。审核者应在 GitHub Actions 的对应 run 中核对 `source.commit`、`workflow.commit` 和 run ID；检出该源码提交后，对 artifact 清单中每个文件重新计算 SHA-256，并与站点下载的 manifest 比对。只有在同时信任 GitHub 仓库、该 Actions run 与下载内容时，这些记录才能帮助发现源码、工作流或产物不一致。它们便于使用同一工具链复建，但不证明不同操作系统或环境会产生字节级相同的产物。

### 同源存储边界

`/monkeycraft/` 是项目路径和资源 base path，不是浏览器 origin 隔离。部署到 `https://use-ai-for-mc.github.io/monkeycraft/` 时，任何相同 scheme、host、port 的页面都与它共享 `localStorage` 边界。当前凭证存储仅以 `monkeycraft.*` 命名空间隔离，并且不读取旧 Flutter 的 `flutter.*` 键；命名空间避免键冲突，但不能阻止同源脚本读取。此处只记录发布前应评估的边界，不改变既有凭证默认行为。
