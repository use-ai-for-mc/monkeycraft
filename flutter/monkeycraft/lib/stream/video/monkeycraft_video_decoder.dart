import 'package:flutter/foundation.dart';

class VideoDecoderStats {
  final int receivedAccessUnits;
  final int decodedFrames;
  final int droppedFrames;
  final int decoderErrors;
  final int keyframeRequests;
  final int decodeQueueSize;

  const VideoDecoderStats({
    this.receivedAccessUnits = 0,
    this.decodedFrames = 0,
    this.droppedFrames = 0,
    this.decoderErrors = 0,
    this.keyframeRequests = 0,
    this.decodeQueueSize = 0,
  });
}

abstract class MonkeycraftVideoDecoder {
  int? get textureId;
  String? get platformViewType;
  bool get isReady;
  String? get lastError;
  VideoDecoderStats get stats;
  VoidCallback? onKeyframeNeeded;
  VoidCallback? onChanged;

  Future<void> initialize({int fps = 20});
  void pushAccessUnit(Uint8List bytes);
  Future<void> reset();
  Future<void> dispose();
}
