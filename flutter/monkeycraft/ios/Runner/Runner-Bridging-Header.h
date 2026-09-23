#import "GeneratedPluginRegistrant.h"
#import "TailscaleKitPin.h"
#if MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE && __has_include("../tailscale_diagnostics/out/tailscale.h")
#import "../tailscale_diagnostics/out/tailscale.h"
#elif __has_include("../third_party/libtailscale/out/tailscale.h")
#import "../third_party/libtailscale/out/tailscale.h"
#endif
