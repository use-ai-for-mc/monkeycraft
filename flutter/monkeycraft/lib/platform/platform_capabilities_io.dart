import 'dart:io';

import 'package:monkeycraft_client/platform/platform_capabilities.dart';

final PlatformCapabilities platformCapabilities = PlatformCapabilities(
  isWeb: false,
  isIOS: Platform.isIOS,
  isAndroid: Platform.isAndroid,
  supportsNativeNotifications: Platform.isIOS || Platform.isAndroid,
  supportsLiveActivity: Platform.isIOS || Platform.isAndroid,
  supportsQrScanner: Platform.isIOS || Platform.isAndroid,
  supportsEmbeddedAudioWebView: Platform.isIOS || Platform.isAndroid,
  supportsVideoDecoder: Platform.isIOS || Platform.isAndroid,
  supportsTouchControls: true,
  supportsLocalFiles: true,
);
