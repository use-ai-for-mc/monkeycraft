export 'platform_capabilities_stub.dart'
    if (dart.library.io) 'platform_capabilities_io.dart';

class PlatformCapabilities {
  final bool isWeb;
  final bool isIOS;
  final bool isAndroid;
  final bool supportsNativeNotifications;
  final bool supportsLiveActivity;
  final bool supportsQrScanner;
  final bool supportsEmbeddedAudioWebView;
  final bool supportsVideoDecoder;
  final bool supportsTouchControls;
  final bool supportsLocalFiles;

  const PlatformCapabilities({
    required this.isWeb,
    required this.isIOS,
    required this.isAndroid,
    required this.supportsNativeNotifications,
    required this.supportsLiveActivity,
    required this.supportsQrScanner,
    required this.supportsEmbeddedAudioWebView,
    required this.supportsVideoDecoder,
    required this.supportsTouchControls,
    required this.supportsLocalFiles,
  });
}
