# 2026-09-19 Pages 不可达目标验证

## 范围

使用既有 `web/dist-pages`，通过本机静态服务器映射到 GitHub Pages 项目路径 `/monkeycraft/`，在独立 Chromium context 打开 `http://127.0.0.1:4190/monkeycraft/`。GitHub Pages 是当前首选的后续静态托管方式；自有域名尚未购买或确认，且不影响本地项目路径验证。没有访问 Minecraft、9600、真实公网 Pages 或移动设备。

## 结果

- 本机 `localhost` 安全上下文为 `true`。
- 输入 `wss://monkeycraft-test.invalid` 与固定测试密码后，五秒内显示 `Connection failed: Connection closed (1006)`；浏览器网络层记录的是名称无法解析。
- 失败后 Connect 按钮恢复，服务器地址和密码输入框均可编辑；改写服务器地址后可再次提交。
- 结果日志已保存为 `outputs/roadmap-2026-09-19-pages-unreachable/result.json`，其中不含测试密码，目标域名已脱敏。

这证明当前静态 Pages 产物能向用户反馈不可达目标并允许重试。远程 Pages 工作流和公网部署尚未获授权且未运行；本结果不证明公网 GitHub Pages、真实网络策略或移动浏览器行为。
