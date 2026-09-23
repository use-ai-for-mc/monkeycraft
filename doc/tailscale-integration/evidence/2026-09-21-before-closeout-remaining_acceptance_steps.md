# 剩余人工验收的最短步骤

2026-09-21：用户睡眠期间已恢复 Android 模拟器自主验收，实体 iPhone 步骤继续等待用户。Android 新正式包已验证权限、精确提醒、Doze、重连、旋转、输入释放，并修复库存键积压及即时提醒重复；详见[本轮记录](evidence/2026-09-21-android-acceptance.md)。下文旧 APK 和未闭环状态属于历史，不覆盖此更新。

已发现问题的可接续交接（2026-09-21）：见 [KNOWN_ISSUES_HANDOFF.md](KNOWN_ISSUES_HANDOFF.md)，包括状态、构建边界、复现、下一步与通过标准。

**暂停点（2026-09-20）：** 用户报告ImagineFun过载，决定明天继续。下一步仍为刷新iPhone Safari并连接，确认声音基线，再测切后台返回后的提示音；音频恢复修复尚未获得真机最终验收。

当前手机验收停在提示音恢复：iPhone Safari返回后画面和登录恢复，但提示音及Test sound均无声。已补网页音频生命周期并本地部署26.2 `a56d2814…` / Web `ca4d7352…`；自动化通过，等待手机刷新、首次发声及后台返回复测。详见[声音恢复证据](evidence/2026-09-19-ios-safari-sound-resume.md)。休眠重复倒计时已经手机确认修复。

最新进展：iPhone Safari 已成功配对并显示休眠界面，发现同一项目倒计时重复。修复已在26.2本地部署并重启回原服，新JAR `bc6f919f…`、Web `60cbdf20…`，用户已刷新并在真实iPhone Safari确认休眠无重复倒计时，测试状态已撤销；下文 `ee2dbc…` 的完整验收仍属于修复前包。前后对照、构建与证据见[休眠倒计时修复](evidence/2026-09-19-hibernation-countdown.md)。手机到点听到的声音来源未确认，不记为手机听感通过。

用户已交出26.2实例供代理接管，并允许必要的正常重启。当前共享 Flutter overlay 包`ee2dbc284e7865dcc06a6a16e524570302f03329afa7dbb373d40a65254dffd9`已安装、重启并返回 ImagineFun 原服务器；JAR 的49项资源与 Flutter root 构建逐字节匹配，HTTPS 取回的关键资源也一致，`main.dart.js`为`57a79829ad188aa530b9ef61e1d3a27dd8a273078822d4939c2c6e169d92e39b`。真实 collision、完整 timer 生命周期和Chrome核心120秒回归已通过：后者8个15秒样本新增969帧、解码错误0，且只保留受控断线后的2个socket。Safari前台有声NUDGE调用计数从8到9且重复不增加，仍只证明调用与去重；本轮开启 Reminder sounds 后，用户已确认前台提示音可听；随后最小化 Safari，用户也确认系统通知出现且可听；用户随后确认后台静音通知出现且无声，前台重复两条只显示一次、响一次；后台无声已定位为看屏共享触发macOS静音；停止看屏后13系统日志及用户均确认通知出现、响一次，无看屏静音14与后台去重15也经用户与系统日志确认通过。电脑内嵌设备仍为`monkeycraft` / `100.82.132.32`，身份未变。无需重买域名或重复授权这个电脑节点。

1. **26.1会话控制步骤已完成，无需再改设置。** 历史26.1包已完成真实ImagineFun十分钟、resize、最小化、输入释放、受控断线恢复与加强背包复验。当前 overlay JAR`660d0a50…`也已在真实ImagineFun完成错误密码、H.264、四次resize、E/ESC、Shift blur释放、刷新、受控断线恢复与60秒回归（121/120/133/147帧、0解码错误），随后已正常退出并恢复26.2；历史与当前记录不互相转算。剩余是三个旧版各自的内嵌Tailscale节点本人授权和跨设备连接。26.1曾打开一次授权页，但最后状态仍为needsLogin；若已完成该页面授权，告知代理即可，由代理重新启动对应实例读回确认。尚未授权则留待下一次切换时继续，无需复制26.2身份或反复打开页面。
2. **Android：准备好时完成自己的Tailscale登录。** 此前5554上的`4f5a225…`与等待授权记录属于历史批次；本轮没有完成本人Tailscale授权。当前overlay源码的Release APK`39218eaa…`已用`adb install -r`保留数据安装到Android 16 AVD并直连真实26.2：通知许可、静音NUDGE通知栏投递、timer更新/取消/到期、通知栏暂停后的同进程前台恢复、4000关闭恢复及Sneak释放均有通过记录；硬件E打开InventoryScreen，但自动化硬件E/ESC未能关闭，不能计作完整硬件键切换。该AVD已关闭、未清数据，无可听声音结论，也未登录或授权Tailscale。下一步仍是在正式手机保留应用数据后完成登录、身份恢复及系统/内嵌混合测试；无需给代理账户密码。
3. **iPhone：提醒与倒计时已完成，本次只留音频修复的最后一次真机复验。** 后续时间方便时由代理覆盖安装已验证的正常Release（Runner`06c2a363…`），你只需进入音频、锁屏约一分钟再返回，确认音乐持续。当前手机仍是此前诊断包，本轮没有再操作手机；No Sleep保活视频冲突已在模拟器复现、修复并完成锁屏/主屏幕返回及断开不复活验证，不能替代iOS26.6.2实际听感。[专项证据](evidence/2026-09-19-ios-audio-resume.md)。
4. **Flutter 网页26.2验收已补齐 Chrome 和桌面Safari。** 当前 overlay 包的真实 collision、完整 timer 生命周期和Chrome核心120秒回归均已通过；核心回归覆盖错误密码、认证解码、resize、E/ESC、Shift blur释放、刷新身份和4000关闭恢复。Safari真实HTTPS/WSS会话也已通过认证、三次resize、E/ESC、Shift成对释放、前台Pointer Lock、静音横幅及A→B/取消/到期后至少2秒；其JS语义Connect点击未建socket，原生AX点击则实际成功认证。Pointer Lock由Safari WebDriver W3C鼠标动作成功取得并由Escape释放；坐标CUA会触发自动化玻璃保护提示，不能写为纯人工鼠标。前台有声NUDGE计数8→9且重复不增，只证明调用与去重。最初五新帧截图仍是旧世界，后续截图和MCP才确认InventoryScreen。主checkout的224项Flutter测试与analyze已通过；73文件Pages候选在独立普通archive中也已完成204项VM/widget（含5项overlay）、24项Chrome和Pages Release核验。本轮真实Safari初始Reminder sounds关闭导致两次无声，开启后用户确认第三次提示音可听；随后最小化Safari，用户确认后台系统通知出现且可听（未直接采样document.hidden）；用户随后确认后台静音通知出现且无声、前台重复两条只显示一次并响一次。后台07/10/11无声已由系统日志定位为displayShared静音策略；停止看屏后13的系统播放日志和用户听感均通过。无看屏条件下静音14与后台去重15均由用户与系统日志确认通过，桌面Safari通知听感验收已完成；用户随后确认返回前台画面正常恢复、无需登录，见[听感证据](evidence/2026-09-19-safari-reminder-audibility.md)。iPhone Safari与Android真机浏览器仍待验。
5. **GitHub Pages：公开入口验收后发布。** 用户已授权的旧Web范围提交`ace51c9`已推送，但未部署；线上仍为旧 Flutter 网页。本轮已把工作流改为 Flutter 共用代码构建，当前 overlay 包的Chrome和桌面Safari真实回归已完成；桌面Safari系统通知/听感已完成；公开Pages入口与移动浏览器仍待验。73文件候选共享Dart范围的发布授权问答仍待回复，因此不新建commit、push、dispatch或deploy；获准后仍需准确审阅其与前轮 App 改动的交集，不把原先排除的 Swift、Kotlin、helper 或 Mod 改动自动纳入。无需购买域名，也不继续发布或验收独立 TypeScript 客户端。

26.1、1.21.11 与 1.19 都继续作为正式支持版本维护。当前 overlay JAR 分别为`660d0a50…`、`0063d289…`和`52fa89f6…`，均完成构建、61项JUnit（0 failed/error/skipped）与49项嵌入资源逐字节核验，并各自完成七项检查的真实60秒回归：26.1为521新帧，1.21.11在ImagineFun为562新帧，1.19在独立测试世界为479新帧，均`errors=[]`且decoder错误0。三版都已正常退出，最终恢复26.2 ee2dbc原服，helper为running/listening，screen=null、Shift=false、ridingSleep=true且无连接。历史b927c80/e9df6d及d42a65/dd3dd0的真实运行和十分钟结果仍只属于各自历史包。旧版内嵌账户授权、跨设备和联网长时仍待验。ImagineFun明确要求1.21+，1.19使用独立世界`MonkeyCraft acceptance 2026-09-1`或兼容1.19的服务器测试，不靠客户端修改绕过服务端版本限制。

[本机既有 HTTPS 入口](https://mac.tail977122.ts.net:8443/)已由新的Mod提供共享Flutter网页。前轮测试连接已释放并恢复26.2；桌面Safari逐项提醒和返回前台恢复验收现已完成；用户已关闭测试标签，MCP确认无客户端连接；现进入真实iPhone Safari入口验收，等待手机结果。

完整结果、构建哈希、失败记录与进一步平台/网络发布门槛见[执行记录](../PRODUCT_ROADMAP_EXECUTION.md)和[支持矩阵](TEST_MATRIX.md)。
