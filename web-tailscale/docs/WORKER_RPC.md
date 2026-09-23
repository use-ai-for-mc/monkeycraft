# Worker RPC v1

Schema: `schema/worker-rpc.v1.json`, `schema/dialtcp.v1.json`

## 传输

- Dedicated Worker（`js/worker.js`，module）
- `postMessage`；二进制用 transferable `ArrayBuffer`
- JSON 上限 64 KiB；写队列上限 32；同时 TCP 连接 **1**
- 取消：`RpcClient.cancelAll`；Worker `shutdown` / `logout` 关闭连接并清 session state
- close 传播：`connClose` 与 Worker 卸载都关掉 live conns

## 方法

| method | 方向 | 说明 |
| --- | --- | --- |
| hello | req | 协议握手 |
| init | req | 启动 fake 或 wasm backend；默认 sessionStorage |
| login | req | `StartLoginInteractive`；页面必须 **同步** 开授权窗 |
| logout | req | 退出并删除 session state |
| status | req | 当前 IPN / conn 计数 |
| dialTcp | req | `{host,port,timeoutMs}` 见 dialtcp.v1 |
| connWrite | req+bin | transferable 负载 |
| connRead | res+bin | 最大 64 KiB |
| connClose | req | |
| wsOpen/wsSend/wsClose | req | RFC 6455 adapter 入口（host 测试已覆盖；Worker 内 fake 走 echo） |
| shutdown | req | 释放一切 |

## 事件

`state`, `browseToURL`（只给 `hasUrl`/`fallback`，**不**带 URL 字符串）, `netMap`（只给 count + stableId）, `panic`, `cleared`

## 错误码

`PROTOCOL UNSUPPORTED NOT_RUNNING NEEDS_LOGIN NEEDS_APPROVAL CANCELLED TIMEOUT QUEUE_FULL CONN_LIMIT INVALID_TARGET CLOSED WORKER_CRASH WASM_LOAD WSS_BLOCKED INTERNAL`
