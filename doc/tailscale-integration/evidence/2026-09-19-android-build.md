# Android 正式原生构建链（2026-09-19）

本轮修复从干净checkout构建缺少Tailscale的问题：CI新增Go1.26.3、NDK28.2.13676358、CMake3.22.1和两ABI原生构建步骤。原CMake在缺少.so时生成无功能JNI库而仍可成功打包；现改为明确失败，提示先运行依赖构建。Flutter插件在buildTypes设置默认三ABI，仅defaultConfig不能排除x86_64；已在buildTypes明确只支持ARM64/ARMv7，避免无库ABI失败或误报支持。

`build.sh`现在对固定commit使用`git archive`展开到临时目录，不再对源码缓存执行checkout或git clean；既有源码修改和未知文件保留。两个ABI都构建、导出符号检查成功后才替换已生成文件，避免编译失败先删除现有可用库。

使用与iOS相同的最小UserLogf安全补丁，不升级libtailscale或改变注册重试。TS backend的Logf与用户日志是不同通道，原JNI的`tailscale_set_logfd(-1)`并不能禁止默认用户日志打印AuthURL。新增补丁禁止该默认输出。manifest记录上游pin、覆盖层、补丁和实际产物哈希。

## 本轮验证

- `bash -n android/third_party/libtailscale/build.sh`通过。
- `GO_BIN=/opt/homebrew/bin/go android/third_party/libtailscale/build.sh`成功：真实工具链为Go1.26.3、NDK28.2.13676358，Android API24，libtailscale80771313 / Tailscale1.94.1。两ABI符号检查通过。
- 独立CMake配置到缺失native目录按预期失败，信息为`Missing arm64-v8a libtailscale`；测试输出保存在`/tmp/monkeycraft-cmake-missing-native.log`。
- 最终常规`flutter build apk --debug`通过；APK恰含ARM64/ARMv7两套Tailscale/JNI库，Tailscale库哈希与manifest逐项一致。最终新库在API36 ARM64模拟器再次2项integration通过，随后正常关机；未进行账户登录或peer拨号。
- 交叉审查确认ARM64 PT_LOAD对齐16384，ARMv7对齐4096。根据[Android NDK官方构建指南](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md)，16KB要求针对64位ABI，32位4KB不据此判为失败。最终APK的自动化原生库与64位ELF检查已加入CI，最新APK通过；缺ABI、缺JNI与错误manifest SHA三种临时负例均被拒绝；当前模拟器实际页大小不作为16KB设备运行证据。

| ABI | SHA-256 | 字节 |
|---|---|---|
| arm64-v8a | `58a727cf8d8e5a7ecd60c9a0cf83a152d3a9d31aecac2bd79ca2cf0440dffe2a` | 22556056 |
| armeabi-v7a | `2737d4b819f0e13327de5ee593085c024b41d78d79c5c30e0b0e9c353388ae5f` | 21437428 |

尚未在GitHub远程执行CI，也未进行真实Android账户登录、系统VPN共存、音频或锁屏验收。

- Root复验：最终APK `verify_apk.py`通过，SDK36.1.0的`zipalign -c -P 16 4`退出0；工作流YAML可解析。远程CI尚未运行。
