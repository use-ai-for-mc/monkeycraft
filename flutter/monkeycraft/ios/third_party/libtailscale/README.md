# iOS 内嵌 libtailscale

正式 iOS App 使用固定的 `libtailscale` commit `80771313ac4127973677c993889fe215abcf1fbd`，以 C archive 链接，不使用 `TailscaleKit.framework`。完整固定信息、许可证和登录语义见 `VERSION.json`、`LICENSE` 与 `product-userlog-discard.patch`。

## 重建

构建脚本要求 Xcode 16.1+、Git、Python 3、`rg`，以及**精确**的 Go 1.26.3。默认 PATH 的 Go 必须正好是该版本；否则设置 `LIBTAILSCALE_GO` 为其 `bin/go` 的绝对路径。脚本检查源码缓存未修改后才检出固定 commit，并在临时副本应用产品日志补丁。它会生成依赖和哈希 manifest，但不会写入账户、auth key 或节点身份。

```sh
cd flutter/monkeycraft
LIBTAILSCALE_GO="$(go env GOROOT)/bin/go" \
  ./ios/third_party/libtailscale/build.sh ios
flutter pub get
flutter build ios --release --no-codesign
```

`ios` 仅生成 `out/libtailscale_ios.a`，用于设备和 App Store archive；`ios-sim` 仅生成 `out/libtailscale_ios_sim.a`，用于 simulator。不可把两种 slice 混合为正式 archive。每次构建结束都会写入 `Link.xcconfig`，使 device 与 simulator 分别链接正确 archive；也可单独运行 `./ios/third_party/libtailscale/build.sh link-config` 恢复该文件。

`ios/tailscale_diagnostics/` 是独立的诊断构建输入与产物，不能替代或覆盖此目录的正式 archive，也不能进入正式发布流程。正式构建使用 `product-userlog-discard.patch`，禁止 tsnet 默认日志输出认证 URL。

GitHub Actions 的 macOS job 只执行无签名 `flutter build ios --release --no-codesign`，用于验证固定 archive 能在干净环境编译。它不产生可安装 App，也不验证 provisioning profile、签名、真实设备安装、账户登录或 App Store 提交；这些由受控的真实签名发行验收单独完成。
