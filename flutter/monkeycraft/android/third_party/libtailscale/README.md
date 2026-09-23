# Android 内嵌 Tailscale 原生依赖

正式 App 使用固定 `libtailscale` commit `80771313ac4127973677c993889fe215abcf1fbd` 和 `tailscale.com v1.94.1`，通过 C shared library / JNI 接入，不创建 Android `VpnService`。用户在 App 内登录自己的账户；这些构建步骤不包含 auth key。

## 重建

需要 Go 1.25.5 或以上（本轮与 CI 使用 1.26.3）、Python 3、Git，以及 Android SDK 的 NDK `28.2.13676358`。从仓库根目录执行：

```sh
sdkmanager 'ndk;28.2.13676358' 'cmake;3.22.1'
flutter/monkeycraft/android/third_party/libtailscale/build.sh
cd flutter/monkeycraft
/Users/cusgadmin/if-local/flutter/bin/flutter build apk --debug
```

其他机器使用其本地 Flutter 命令。脚本从 `ANDROID_HOME/ndk/28.2.13676358` 查找 NDK；也可以显式传入 `ANDROID_NDK_HOME`。本机 macOS 另支持默认 Android SDK 路径。只有在已确认目标可执行文件满足版本要求时才设置 `GO_BIN=/absolute/path/to/go`；不应把 PATH 中第一个未知版本固定为 `GO_BIN`。

`LIBTAILSCALE_SRC` 可以指定已有 Git 源码缓存。脚本获取固定 commit 后将 `git archive` 展开到临时目录；不会 checkout、clean 或覆盖缓存目录中的修改。两个 ABI 都编译和符号检查成功后才替换 `out/` 中产物；失败保留原有二进制。

产物为 `out/arm64-v8a/` 与 `out/armeabi-v7a/` 下的 `.so`、C header 和 SHA-256。`out/MANIFEST.json` 记录上游 commit、Go、NDK、Android API、覆盖层、日志补丁与产物哈希。二进制与源码缓存被忽略，不纳入 Git。App 的 CMake 在缺少任一目标库时明确失败，避免打出悄悄缺失内嵌功能的包。

## 本地适配

- `overlay/android_netmon.go` 使用 `getifaddrs`，避免 Android App SELinux 不允许的 route netlink；设置 App 私有日志目录，并提供有限时拨号。
- `product-userlog-discard.patch` 禁止 tsnet 的默认用户日志输出认证 URL。原生插件也通过 `tailscale_set_logfd(-1)` 禁用独立的 backend 日志；两个日志通道都需要覆盖。
- 保留上游许可证 `LICENSE`。没有改变注册重试、认证时限或升级 Tailscale 版本。

最终APK可以运行`python3 android/third_party/libtailscale/verify_apk.py build/app/outputs/flutter-apk/app-debug.apk`检查双ABI/Tailscale和JNI库、manifest哈希及所有ARM64 ELF段的16KB对齐；CI在构建后执行此项。还应使用Android SDK的`zipalign -c -P 16 4 <apk>`检查ZIP内对齐。ARMv7维持4KB段对齐；[NDK官方说明](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md)的16KB要求针对64位ABI。这里的静态检查不代表已经在16KB内核设备运行。

跨编译成功与符号存在不代表真机登录、系统 VPN 共存、后台恢复或账户身份持久化已完成；验收结果见产品执行记录与 Android 证据。
