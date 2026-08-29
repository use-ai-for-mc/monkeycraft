import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:monkeycraft_client/stream/h264_nal.dart';
import 'package:monkeycraft_client/stream/video/decode_queue_policy.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';
import 'package:web/web.dart' as web;

class WebH264Decoder implements MonkeycraftVideoDecoder {
  static const String defaultCodec = 'avc1.420028';
  static int _nextViewId = 1;

  final DecodeQueuePolicy _policy;
  final web.HTMLCanvasElement _canvas;
  final String _viewType;
  web.CanvasRenderingContext2D? _ctx;
  web.VideoDecoder? _decoder;
  bool _disposed = false;
  bool _ready = false;
  bool _waitingForKey = true;
  bool _viewRegistered = false;
  int _fps = 20;
  int _frameIndex = 0;
  int _received = 0;
  int _decoded = 0;
  int _dropped = 0;
  int _errors = 0;
  int _keyframeRequests = 0;
  int _consecutiveDrops = 0;
  String? _codec = defaultCodec;
  String? _error;

  WebH264Decoder({DecodeQueuePolicy policy = const DecodeQueuePolicy()})
    : _policy = policy,
      _canvas = web.HTMLCanvasElement(),
      _viewType = 'monkeycraft-video-${_nextViewId++}' {
    _canvas.style.pointerEvents = 'none';
    _canvas.style.width = '100%';
    _canvas.style.height = '100%';
    _canvas.style.objectFit = 'contain';
    _ctx = _canvas.context2D;
  }

  @override
  int? get textureId => null;

  @override
  String? get platformViewType => _viewRegistered ? _viewType : null;

  @override
  bool get isReady => _ready && !_disposed;

  @override
  String? get lastError => _error;

  @override
  VideoDecoderStats get stats => VideoDecoderStats(
    receivedAccessUnits: _received,
    decodedFrames: _decoded,
    droppedFrames: _dropped,
    decoderErrors: _errors,
    keyframeRequests: _keyframeRequests,
    decodeQueueSize: _decoder?.decodeQueueSize ?? 0,
  );

  @override
  VoidCallback? onKeyframeNeeded;

  @override
  VoidCallback? onChanged;

  @override
  Future<void> initialize({int fps = 20}) async {
    if (_disposed) return;
    _fps = fps > 0 ? fps : 20;
    if (!_viewRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => _canvas,
      );
      _viewRegistered = true;
    }
    await _createDecoder();
    onChanged?.call();
  }

  Future<void> _createDecoder({String? codec}) async {
    _closeDecoder();
    _codec = codec ?? _codec ?? defaultCodec;
    _waitingForKey = true;
    _frameIndex = 0;
    _consecutiveDrops = 0;

    final config = web.VideoDecoderConfig(codec: _codec!)
      ..optimizeForLatency = true
      ..hardwareAcceleration = 'no-preference';

    try {
      final support = await web.VideoDecoder.isConfigSupported(config).toDart;
      if (support.supported != true) {
        _error =
            'This browser cannot decode $_codec. Use a recent desktop Chrome or Edge.';
        _ready = false;
        debugPrint('WebH264Decoder: config not supported: $_codec');
        onChanged?.call();
        return;
      }
    } catch (e) {
      _error = 'WebCodecs is not available in this browser ($e).';
      _ready = false;
      debugPrint('WebH264Decoder: isConfigSupported failed: $e');
      onChanged?.call();
      return;
    }

    final decoder = web.VideoDecoder(
      web.VideoDecoderInit(
        output: _onOutput.toJS,
        error: _onDecoderError.toJS,
      ),
    );
    decoder.configure(config);
    _decoder = decoder;
    _ready = true;
    _error = null;
    debugPrint('WebH264Decoder: configured $_codec');
  }

  void _onOutput(web.VideoFrame frame) {
    try {
      final width = frame.displayWidth;
      final height = frame.displayHeight;
      if (width > 0 && height > 0) {
        if (_canvas.width != width) _canvas.width = width;
        if (_canvas.height != height) _canvas.height = height;
      }
      _ctx?.drawImage(frame, 0, 0);
      _decoded += 1;
    } catch (e) {
      debugPrint('WebH264Decoder: draw failed: $e');
    } finally {
      frame.close();
    }
  }

  void _onDecoderError(web.DOMException error) {
    _errors += 1;
    _ready = false;
    _waitingForKey = true;
    debugPrint('WebH264Decoder: decoder error: ${error.name} ${error.message}');
    _requestKeyframe();
    unawaited(_createDecoder());
  }

  void _requestKeyframe() {
    _keyframeRequests += 1;
    onKeyframeNeeded?.call();
  }

  @override
  void pushAccessUnit(Uint8List bytes) {
    if (_disposed) return;
    _received += 1;
    if (!_ready || _decoder == null) {
      if (_error != null) return;
      return;
    }

    final isKey = containsIdrNal(bytes);
    if (isKey) {
      final sps = parseSpsCodec(bytes);
      if (sps != null && sps.codecString != _codec) {
        debugPrint(
          'WebH264Decoder: SPS codec ${sps.codecString} (was $_codec)',
        );
        unawaited(_reconfigure(sps.codecString, bytes, isKey: true));
        return;
      }
    }

    final action = _policy.decide(
      isKey: isKey,
      waitingForKey: _waitingForKey,
      queueSize: _decoder!.decodeQueueSize,
      consecutiveDrops: _consecutiveDrops,
    );

    switch (action) {
      case DecodeAction.waitForKey:
        _dropped += 1;
        return;
      case DecodeAction.drop:
        _dropped += 1;
        _consecutiveDrops += 1;
        return;
      case DecodeAction.resetAndWaitForKey:
        _dropped += 1;
        _consecutiveDrops = 0;
        _waitingForKey = true;
        unawaited(_createDecoder());
        _requestKeyframe();
        return;
      case DecodeAction.decode:
        _decode(bytes, isKey: isKey);
    }
  }

  Future<void> _reconfigure(
    String codec,
    Uint8List bytes, {
    required bool isKey,
  }) async {
    await _createDecoder(codec: codec);
    if (_ready && isKey) {
      _decode(bytes, isKey: true);
    }
  }

  void _decode(Uint8List bytes, {required bool isKey}) {
    final decoder = _decoder;
    if (decoder == null || _disposed) return;
    try {
      final duration = (1000000 / _fps).round();
      final chunk = web.EncodedVideoChunk(
        web.EncodedVideoChunkInit(
          type: isKey ? 'key' : 'delta',
          timestamp: _frameIndex * duration,
          duration: duration,
          data: bytes.toJS,
        ),
      );
      decoder.decode(chunk);
      _frameIndex += 1;
      _consecutiveDrops = 0;
      if (isKey) _waitingForKey = false;
    } catch (e) {
      _errors += 1;
      _waitingForKey = true;
      debugPrint('WebH264Decoder: decode failed: $e');
      _requestKeyframe();
      unawaited(_createDecoder());
    }
  }

  void _closeDecoder() {
    final decoder = _decoder;
    _decoder = null;
    _ready = false;
    if (decoder == null) return;
    try {
      decoder.close();
    } catch (_) {}
  }

  @override
  Future<void> reset() async {
    _waitingForKey = true;
    _frameIndex = 0;
    _consecutiveDrops = 0;
    await _createDecoder();
    _requestKeyframe();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _closeDecoder();
    _ready = false;
  }
}
