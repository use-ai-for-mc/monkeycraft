import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';

class HardwareH264Decoder implements MonkeycraftVideoDecoder {
  static const MethodChannel _channel = MethodChannel('monkeycraft/h264_decoder');

  int? _textureId;
  bool _sending = false;
  Uint8List? _pending;
  int _droppedQueued = 0;
  int _pushedToNative = 0;
  bool _disposed = false;

  @override
  int? get textureId => _textureId;
  int get droppedQueued => _droppedQueued;
  int get pushedToNative => _pushedToNative;

  @override
  String? get platformViewType => null;

  @override
  bool get isReady => _textureId != null && !_disposed;

  @override
  String? get lastError => null;

  @override
  VideoDecoderStats get stats => VideoDecoderStats(
    receivedAccessUnits: _pushedToNative + _droppedQueued,
    decodedFrames: _pushedToNative,
    droppedFrames: _droppedQueued,
  );

  @override
  VoidCallback? onKeyframeNeeded;

  @override
  VoidCallback? onChanged;

  @override
  Future<void> initialize({int fps = 20}) async {
    await createDecoder(fps: fps);
  }

  Future<int> createDecoder({int fps = 20}) async {
    _disposed = false;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'createDecoder',
      {'fps': fps},
    );
    final id = result?['textureId'];
    if (id is int) {
      _textureId = id;
      onChanged?.call();
      return id;
    }
    throw StateError('Failed to create decoder');
  }

  @override
  void pushAccessUnit(Uint8List bytes) {
    if (_disposed || _textureId == null) return;
    if (_sending) {
      if (_pending != null) _droppedQueued += 1;
      _pending = bytes;
      return;
    }
    _pending = bytes;
    _sending = true;
    _drain();
  }

  Future<void> _drain() async {
    while (true) {
      final next = _pending;
      if (_disposed || next == null || _textureId == null) break;
      _pending = null;
      try {
        await _channel.invokeMethod<void>(
          'pushAccessUnit',
          {'bytes': next},
        );
        _pushedToNative += 1;
      } catch (_) {
        break;
      }
    }
    _sending = false;
  }

  @override
  Future<void> reset() {
    _pending = null;
    _sending = false;
    _droppedQueued = 0;
    _pushedToNative = 0;
    return _channel.invokeMethod<void>('resetDecoder');
  }

  Future<Map<String, dynamic>> getStats() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getStats');
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> dispose() async {
    if (_textureId == null) return;
    _disposed = true;
    _pending = null;
    _sending = false;
    try {
      await _channel.invokeMethod<void>('disposeDecoder');
    } catch (e) {
      debugPrint('HardwareH264Decoder: dispose error: $e');
    } finally {
      _textureId = null;
    }
  }
}
