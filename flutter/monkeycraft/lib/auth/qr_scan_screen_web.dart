import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('BarcodeDetector')
external JSFunction? get _barcodeDetectorCtor;

@JS('jsQR')
external JSFunction? get _jsQrFn;

@JS()
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector(JSObject options);
  external JSPromise<JSArray<_DetectedBarcode>> detect(JSAny source);
}

@JS()
extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}

@JS()
extension type _JsQrResult._(JSObject _) implements JSObject {
  external String get data;
}

@JS('jsQR')
external _JsQrResult? _jsQr(
  JSUint8ClampedArray data,
  int width,
  int height,
);

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  static int _nextViewId = 1;

  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true');
  final web.HTMLCanvasElement _scratch = web.HTMLCanvasElement();
  final String _viewType;
  Timer? _poll;
  web.MediaStream? _stream;
  bool _cameraOn = false;
  bool _didPop = false;
  bool _busy = false;
  String? _error;

  _QrScanScreenState() : _viewType = 'monkeycraft-qr-${_nextViewId++}';

  bool get _canDecode =>
      _barcodeDetectorCtor != null || _jsQrFn != null;

  @override
  void initState() {
    super.initState();
    _video.style.width = '100%';
    _video.style.height = '100%';
    _video.style.objectFit = 'cover';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    if (!_canDecode) {
      _error =
          'QR decoding is not available yet. Wait a moment, type the password, or retry.';
    }
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  void _complete(String value) {
    if (_didPop) return;
    _didPop = true;
    _stopCamera();
    Navigator.of(context).pop(value);
  }

  Future<String?> _decodeFromCanvasSource(JSAny source) async {
    if (_barcodeDetectorCtor != null) {
      try {
        final detector = _BarcodeDetector(
          {'formats': <String>['qr_code']}.jsify()! as JSObject,
        );
        final results = (await detector.detect(source).toDart).toDart;
        for (final barcode in results) {
          final value = barcode.rawValue.trim();
          if (value.isNotEmpty) return value;
        }
      } catch (_) {}
    }
    return _decodeWithJsQr(source);
  }

  String? _decodeWithJsQr(JSAny source) {
    if (_jsQrFn == null) return null;
    final ctx = _scratch.context2D;
    var width = 0;
    var height = 0;
    if (source.isA<web.HTMLVideoElement>()) {
      final video = source as web.HTMLVideoElement;
      width = video.videoWidth;
      height = video.videoHeight;
    } else if (source.isA<web.HTMLImageElement>()) {
      final image = source as web.HTMLImageElement;
      width = image.naturalWidth;
      height = image.naturalHeight;
    }
    if (width <= 0 || height <= 0) return null;
    const maxEdge = 720;
    final scale = width > maxEdge || height > maxEdge
        ? maxEdge / (width > height ? width : height)
        : 1.0;
    final drawWidth = (width * scale).round();
    final drawHeight = (height * scale).round();
    _scratch.width = drawWidth;
    _scratch.height = drawHeight;
    ctx.drawImage(source as web.CanvasImageSource, 0, 0, drawWidth, drawHeight);
    final imageData = ctx.getImageData(0, 0, drawWidth, drawHeight);
    final result = _jsQr(imageData.data, drawWidth, drawHeight);
    final value = result?.data.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _startCamera() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              video: {
                'facingMode': 'environment',
              }.jsify()!,
              audio: false.toJS,
            ),
          )
          .toDart;
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      _cameraOn = true;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 350), (_) {
        unawaited(_scanVideo());
      });
    } catch (e) {
      _error = 'Camera unavailable ($e). Choose a screenshot instead.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanVideo() async {
    if (_didPop || !_cameraOn) return;
    try {
      final value = await _decodeFromCanvasSource(_video);
      if (value != null) _complete(value);
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*';
    final completer = Completer<web.File?>();
    input.addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        completer.complete(
          files != null && files.length > 0 ? files.item(0) : null,
        );
      }).toJS,
    );
    input.click();
    final file = await completer.future;
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = web.URL.createObjectURL(file);
      final image = web.HTMLImageElement()..src = url;
      final loaded = Completer<void>();
      image.addEventListener(
        'load',
        ((web.Event _) => loaded.complete()).toJS,
      );
      image.addEventListener(
        'error',
        ((web.Event _) => loaded.completeError('Could not read image')).toJS,
      );
      await loaded.future;
      final value = await _decodeFromCanvasSource(image);
      web.URL.revokeObjectURL(url);
      if (value != null) {
        _complete(value);
        return;
      }
      setState(() => _error = 'No QR code found in that image.');
    } catch (e) {
      setState(() => _error = 'Could not read QR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stopCamera() {
    _poll?.cancel();
    _poll = null;
    _cameraOn = false;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      final tracks = stream.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
    }
    _video.srcObject = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Password QR')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'On iPhone Safari, allow the camera or choose a screenshot of the in-game QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_cameraOn)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: HtmlElementView(viewType: _viewType),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : (_cameraOn ? _stopCamera : _startCamera),
                    child: Text(_cameraOn ? 'Stop camera' : 'Use camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _pickImage,
                    child: const Text('Choose image'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
