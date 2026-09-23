# CSP / connect-src 设计（未上线）

```
default-src 'none';
script-src 'self';
worker-src 'self';
connect-src 'self' https://controlplane.tailscale.com https://login.tailscale.com;
img-src 'self';
style-src 'self';
wasm-unsafe-eval  /* Go wasm_exec 需要；尽量限制在 worker */
```

DERP 主机来自动态 DERP map，产品安全评审前不能写死 `*` 通配。POC 不部署到 Pages。

禁止：

- 从 unpinned CDN 加载 `main.wasm` / `wasm_exec.js`
- service worker 缓存覆盖安全升级
- 在文档或 log 里放 auth URL
