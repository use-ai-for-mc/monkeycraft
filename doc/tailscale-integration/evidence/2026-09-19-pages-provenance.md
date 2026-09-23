# 2026-09-19 Pages provenance 本地验证

范围：本记录只覆盖本地 Pages 构建和可核验性准备；没有提交、推送、触发远程 Actions 或部署。

## 结果

- `pnpm test:pages-provenance`：通过（2 个 Node 测试）。
- `pnpm typecheck`、`pnpm lint`：通过。
- 脏工作树下不设 `MONKEYCRAFT_PAGES_ALLOW_DIRTY=1` 时，provenance 工具按设计拒绝将产物标记为某个源码提交。
- 设定该显式本地开关后，`pnpm build:pages` 成功；产物 manifest 标记为 `source.dirty: true`、`source.commit: null`，并包含 6 个锁定 Action 引用、实际 Node 版本、精确声明的 pnpm 版本、lockfile SHA-256 和逐文件 SHA-256。
- Chromium Pages 专项 Playwright：通过 2 项，验证项目路径和公开 provenance 文件。

原始本轮命令输出保存在 [validation.log](/Users/cusgadmin/if-local/monkeycraft/outputs/pages-provenance-2026-09-19/validation.log)。当前本地产物的 manifest 位于 `web/dist-pages/build-provenance.json`，该目录被忽略且不代表发布内容。

## 核验边界

manifest 提供可重算的关联记录，不是签名或安全证明；它不会证明跨操作系统的字节级可复现性。公开发布后，审核者须在关联 GitHub Actions run 核对源码/workflow/run，并从该源码提交重建或复算 artifact 清单的 SHA-256；不能把本地脏树或没有关联 run 的 manifest 当作已发布证明。

## Action 来源与锁定提交

初始锁定曾错误使用 `pnpm/action-setup` 的带注释标签对象 `f520eceda224fe1a4aed5a2a27a194379a409996`；GitHub commits API 对该对象返回 HTTP 422，不能作为 `uses:` 提交。已用 `refs/tags/v6^{}` 解引用为实际提交 `0977fd99725f1db4007ccb2928dbb4e90d06cc86` 并替换。其余五个 major tag 本身直接指向提交。本轮同时用 GitHub commits API 对以下六个最终 SHA 分别得到 HTTP 200；链接为可检出的官方提交来源，而非未经确认的 release 页面。

| Action | 固定 SHA | 官方验证来源 |
| --- | --- | --- |
| `actions/checkout` v6 | `d23441a48e516b6c34aea4fa41551a30e30af803` | [commit](https://github.com/actions/checkout/commit/d23441a48e516b6c34aea4fa41551a30e30af803) |
| `pnpm/action-setup` v6 | `0977fd99725f1db4007ccb2928dbb4e90d06cc86` | [commit](https://github.com/pnpm/action-setup/commit/0977fd99725f1db4007ccb2928dbb4e90d06cc86) |
| `actions/setup-node` v6 | `249970729cb0ef3589644e2896645e5dc5ba9c38` | [commit](https://github.com/actions/setup-node/commit/249970729cb0ef3589644e2896645e5dc5ba9c38) |
| `actions/upload-pages-artifact` v4 | `7b1f4a764d45c48632c6b24a0339c27f5614fb0b` | [commit](https://github.com/actions/upload-pages-artifact/commit/7b1f4a764d45c48632c6b24a0339c27f5614fb0b) |
| `actions/configure-pages` v5 | `983d7736d9b0ae728b81ab479565c72886d7745b` | [commit](https://github.com/actions/configure-pages/commit/983d7736d9b0ae728b81ab479565c72886d7745b) |
| `actions/deploy-pages` v4 | `d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e` | [commit](https://github.com/actions/deploy-pages/commit/d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e) |
