import 'package:flutter/foundation.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';

class NoopH264Decoder implements MonkeycraftVideoDecoder {
  bool _disposed = false;

  @override
  int? get textureId => null;

  @override
  String? get platformViewType => null;

  @override
  bool get isReady => false;

  @override
  String? get lastError =>
      'Video decoding is not available on this platform.';

  @override
  VideoDecoderStats get stats => const VideoDecoderStats();

  @override
  VoidCallback? onKeyframeNeeded;

  @override
  VoidCallback? onChanged;

  @override
  Future<void> initialize({int fps = 20}) async {
    if (_disposed) return;
    onChanged?.call();
  }

  @override
  void pushAccessUnit(Uint8List bytes) {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
