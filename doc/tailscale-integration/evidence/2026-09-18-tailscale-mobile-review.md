# 移动端 Tailscale 接入与登录延迟调查

日期：2026-09-18。本轮实测、代码事实与外部报告分开记录。

## 官方组件和现有接入

- 官方[tsnet文档](https://tailscale.com/docs/features/tsnet)支持将Tailscale嵌入Go进程，使用用户态网络栈；官方自身也使用tsnet。
- 官方[libtailscale](https://github.com/tailscale/libtailscale)提供C库与Swift目录。当前项目的iOS采用固定commit `80771313ac4127973677c993889fe215abcf1fbd`、`tailscale.com v1.94.1` 的C archive，Swift及Flutter MethodChannel由MonkeyCraft维护。PC helper使用`v1.102.3`，不是同一运行环境。
- 本轮检索未找到Tailscale官方发布/推荐的Flutter SDK。检索到的[danReynolds/tailscale_dart](https://github.com/danReynolds/tailscale_dart)是第三方项目，当前0.9.0/pre-1.0；不能视为官方SDK或仅凭名称断定比既有集成成熟。本轮未替换依赖或迁移身份。
- 官方仓库[issue #20060](https://github.com/tailscale/tailscale/issues/20060)报告iOS进程挂起后loopback监听失效，并提出内存LocalAPI状态接口。项目当前statusJSON已使用该内存接口，但登录/退出仍经过loopback TCP。它是排查线索，未证明是本次30秒延迟根因。

## 本轮事实

- 用户真机：初次报告10秒以上无页面，随后页面打开；再次操作约30秒，过去较稳定。尚未获得分阶段设备耗时，不能归类为正常等待。
- 首轮已安装包的Swift节点启动/登录代码与仓库HEAD完全一致，本轮首包改动为通知声音处理。后续新增诊断/修复尚未安装。
- PC fresh-state对照：三次needsLogin在0.14–0.16秒，登录地址在4.197、1.134、1.439秒；正常退出。证据未保存登录地址。
- iOS源码：启动与状态调用在串行工作队列；状态原生调用最多10秒；登录通过URLSession发本地HTTP请求，request timeout 15秒、同步等待最多20秒。系统打开浏览器原来无完成回调；相同URL去重也会阻止用户显式重开。这些实现问题需要测试与修正，尚不能把所有问题等同于当前延迟的根因。

## 模拟器完整 AuthURL 计时

- 指定 arm64 iPhone 16 模拟器（iOS 26.5）以固定 v1.94.1 C archive、新临时 state directory 运行原生 XCTest：从 `startNode` 到 `loginInteractive`、随后每 250 ms 读取内存状态，直到首次非空 AuthURL。该测试不授权、不保存 URL/状态 JSON/密钥。
- 2026-09-18 样本通过，总计 20.782 秒：`startMs=78`、本机 loopback LocalAPI `localApiRequestMs=71`、`firstAuthURLMs=20689`。原始脱敏附件：`/tmp/monkeycraft-ios-native-timing-attachments/5527FFC7-40D9-49B1-AF0F-6C6A705AEA0A.json`。
- 这个样本证实 iOS 也存在“POST 很快返回、AuthURL 随后十余秒才出现”的完整链路；它与纯 Go 基线方向一致。故不能将用户约 30 秒等待归因于 Flutter、Swift 串行队列、URLSession 或 `UIApplication.open`。后者仍已修复为异步可报告回调，且新增无敏感阶段日志，供后续独立真机诊断 host 对照。

## 接下来的判定标准

对照原实现测量节点启动、状态读取、登录POST、AuthURL出现和系统打开结果；验证首次启动、已有节点重用、取消重试、前后台恢复。若定位本地HTTP为阻塞点，再评估使用官方内存LocalClient的最小桥接扩展，保持原有账户身份。真实iPhone重测通过前不标记解决。

## 后续真机复核

上述“尚未获得/尚未安装”描述为调查初期状态。现已覆盖安装保留身份的Release诊断包，取得[34条真机数值事件](2026-09-18-ios-phone-login.json)：节点启动34ms，自动注册首次HTTP200、请求耗时3944ms，Swift观察AuthURL在5068ms，系统open成功在5125ms。本样本没有502、没有显式loginInteractive，不支持“节点启动方法导致数十秒等待”。用户报告约8秒到可见网页，超出仪器覆盖的部分未单独定位，系统open回调不等于网页渲染完成。

独立纯Go串行对照曾抓到14次注册502、28.818秒才收到AuthURL，见[源码与对照分析](2026-09-18-ios-authurl-latency-source-analysis.md)。该错误不是正常成功登录的必需步骤；官方重试是异常容错。它解释了一个同量级慢样本，不能反推最早未采集日志的真机30秒一定也是502。

Flutter已避免在登录地址未准备好时诱导重复login（会取消在途register），并按用户请求为此阶段补上转圈。正常等待、失败重试、真实账户授权与后台恢复仍是不同的验收项。
