import 'dart:async';
import 'dart:io' show Platform;

import 'package:monkeycraft_client/audio/audio_operation_queue.dart';
import 'package:monkeycraft_client/audio/audio_playback_diagnostics.dart';
import 'package:monkeycraft_client/audio/openaudiomc_webview_script.dart';
import 'package:monkeycraft_client/audio/openaudiomc_url.dart';
import 'package:monkeycraft_client/audio/audio_background_session.dart';
import 'package:monkeycraft_client/audio/audio_web_view.dart';

class OpenAudioMcService {
  static const _maxReconnectAttempts = 3;
  static const _monitorIntervalMs = 3000;
  static const _connectionTimeoutMs = 30000;

  OpenAudioMcService({AudioWebViewFactory? webViewFactory})
    : _webViewFactory = webViewFactory ?? createAudioWebView;

  final AudioWebViewFactory _webViewFactory;
  AudioWebView? _headlessWebView;
  String? _savedSessionUrl;
  bool _isConnected = false;
  bool _hasReportedFailure = false;
  bool _isActive = false;
  int _reconnectAttempts = 0;
  Timer? _monitorTimer;
  int _monitorElapsedMs = 0;
  void Function(Map<String, dynamic> infoPacket)? _onInfoPacket;
  void Function()? _onFailure;
  final _operations = AudioOperationQueue();
  bool _monitorScheduled = false;
  final _backgroundSessionOwner = Object();
  bool _backgroundSessionHeld = false;

  static bool isOpenAudioMcUrl(String url) {
    return isOpenAudioMcSessionUrl(url);
  }

  void setInfoPacketHandler(
    void Function(Map<String, dynamic> infoPacket) handler,
  ) {
    _onInfoPacket = handler;
    reportState();
  }

  void setOnFailureHandler(void Function() handler) {
    _onFailure = handler;
  }

  void _sendInfoPacket(String title, Map<String, dynamic> data) {
    if (_onInfoPacket != null) {
      final packet = <String, dynamic>{
        'type': 'INFO',
        'title': title,
        'data': {'active': _isActive, ...data},
      };
      _onInfoPacket!(packet);
    }
  }

  void reportState() {
    _sendInfoPacket('openaudiomc', {'connected': _isConnected});
  }

  Future<void> initialize() => _operations.enqueue(_initialize);

  Future<void> _initialize() async {
    if (_headlessWebView != null) return;
    final webView = _webViewFactory(
      initialScript: openAudioMcWebViewScript(
        isIOS: Platform.isIOS,
        diagnostics: AudioPlaybackDiagnostics.enabled,
      ),
    );
    _headlessWebView = webView;
    try {
      await webView.run();
    } catch (_) {
      if (identical(_headlessWebView, webView)) {
        _headlessWebView = null;
      }
      rethrow;
    }
  }

  Future<void> connect(String sessionUrl) {
    return _operations.enqueue(() => _connect(sessionUrl));
  }

  Future<void> _connect(String sessionUrl) async {
    if (_isActive && _savedSessionUrl == sessionUrl) {
      return;
    }
    if (_isActive) {
      await _disconnect();
    }
    _isActive = true;
    _savedSessionUrl = sessionUrl;
    _reconnectAttempts = 0;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;

    reportState();
    try {
      if (_headlessWebView == null) {
        await _initialize();
      }
      _sendInfoPacket('openaudiomc', {'connected': false});
      await _headlessWebView!.loadUrl(sessionUrl);
      await _acquireBackgroundSession();
      _startMonitoring();
    } catch (_) {
      _isActive = false;
      _isConnected = false;
      _monitorTimer?.cancel();
      await _headlessWebView?.dispose();
      _headlessWebView = null;
      await _releaseBackgroundSession();
      reportState();
      rethrow;
    }
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorElapsedMs = 0;
    _monitorTimer = Timer.periodic(Duration(milliseconds: _monitorIntervalMs), (
      _,
    ) async {
      _scheduleMonitor();
    });
  }

  void _scheduleMonitor() {
    if (_monitorScheduled) return;
    _monitorScheduled = true;
    unawaited(
      _operations
          .enqueue(_monitorSession)
          .then<void>(
            (_) {
              _monitorScheduled = false;
            },
            onError: (Object error, StackTrace stackTrace) {
              _monitorScheduled = false;
              _handleMonitorError();
            },
          ),
    );
  }

  void _handleMonitorError() {
    if (!_isActive) return;
    _isConnected = false;
    try {
      _sendInfoPacket('openaudiomc', {'connected': false, 'error': 'monitor'});
    } catch (_) {}
  }

  Future<void> _monitorSession() async {
    if (!_isActive || _headlessWebView == null) return;
    await _capturePlayback('monitor');
    if (!_isActive) return;

    final controller = _headlessWebView!;

    _monitorElapsedMs += _monitorIntervalMs;

    final result = await controller.evaluateJavascript('''
      (function() {
        const rangeInput = document.querySelector('input[type="range"]');
        const hasRangeInput = !!rangeInput;
        
        const buttons = [...document.querySelectorAll('button')];
        const startButton = buttons.find(btn => btn.outerText.trim().toLowerCase() === 'start audio session');
        const hasStartButton = !!startButton;
        
        const currentUrl = window.location.href;
        
        return {
          hasRangeInput: hasRangeInput,
          hasStartButton: hasStartButton,
          currentUrl: currentUrl,
          hasSession: currentUrl.includes('session=')
        };
      })();
    ''');

    if (!_isActive) {
      return;
    }

    if (result == null) {
      if (_monitorElapsedMs >= _connectionTimeoutMs &&
          !_isConnected &&
          !_hasReportedFailure) {
        await _handleFailure('timeout');
      }
      return;
    }

    final hasRangeInput = result['hasRangeInput'] == true;
    final hasStartButton = result['hasStartButton'] == true;
    final hasSession = result['hasSession'] == true;
    final currentUrl = result['currentUrl'] as String?;

    if (hasRangeInput) {
      if (!_isConnected) {
        _isConnected = true;
        _hasReportedFailure = false;
        _reconnectAttempts = 0;
        _sendInfoPacket('openaudiomc', {'connected': true});
      }

      if (currentUrl != null && currentUrl.contains('session=')) {
        if (_savedSessionUrl != currentUrl) {
          _savedSessionUrl = currentUrl;
        }
      }
    } else {
      if (hasStartButton) {
        await controller.evaluateJavascript('''
          (function() {
            const buttons = [...document.querySelectorAll('button')];
            const startButton = buttons.find(btn => btn.outerText.trim().toLowerCase() === 'start audio session');
            if (startButton) {
              startButton.click();
              return true;
            }
            return false;
          })();
        ''');
        if (!_isActive) {
          return;
        }
      } else if (!hasSession && _savedSessionUrl != null && _isConnected) {
        if (_reconnectAttempts >= _maxReconnectAttempts) {
          await _handleFailure('max_reconnect');
          return;
        }

        _reconnectAttempts++;
        _isConnected = false;
        _sendInfoPacket('openaudiomc', {'connected': false});
        await controller.loadUrl(_savedSessionUrl!);
        _monitorElapsedMs = 0;
      } else if (_monitorElapsedMs >= _connectionTimeoutMs &&
          !_isConnected &&
          !_hasReportedFailure) {
        await _handleFailure('timeout');
      }

      if (_isConnected) {
        _isConnected = false;
        _sendInfoPacket('openaudiomc', {'connected': false});
      }
    }
  }

  Future<void> _handleFailure(String error) async {
    _hasReportedFailure = true;
    _isActive = false;
    _monitorTimer?.cancel();
    await _releaseBackgroundSession();
    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _savedSessionUrl = null;
    _isConnected = false;

    _sendInfoPacket('openaudiomc', {'connected': false, 'error': error});
    _onFailure?.call();
  }

  Future<void> disconnect() {
    _isActive = false;
    _monitorTimer?.cancel();
    return _operations.enqueue(_disconnect);
  }

  Future<void> _disconnect() async {
    _monitorTimer?.cancel();
    _isConnected = false;
    _hasReportedFailure = false;
    _isActive = false;
    await _releaseBackgroundSession();
    await _headlessWebView?.loadUrl('about:blank');
    reportState();
  }

  Future<void> reconnect() => _operations.enqueue(_reconnect);

  Future<void> _reconnect() async {
    if (_savedSessionUrl == null) return;

    _isActive = true;
    _reconnectAttempts = 0;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;
    _sendInfoPacket('openaudiomc', {'connected': false});

    try {
      if (_headlessWebView == null) await _initialize();
      await _headlessWebView!.loadUrl(_savedSessionUrl!);
      await _acquireBackgroundSession();
      _startMonitoring();
    } catch (_) {
      _isActive = false;
      _isConnected = false;
      _monitorTimer?.cancel();
      await _headlessWebView?.dispose();
      _headlessWebView = null;
      await _releaseBackgroundSession();
      reportState();
      rethrow;
    }
  }

  Future<void> dispose() {
    _isActive = false;
    _monitorTimer?.cancel();
    return _operations.enqueue(_dispose);
  }

  Future<void> _dispose() async {
    _monitorTimer?.cancel();
    try {
      await _headlessWebView?.dispose();
    } finally {
      _headlessWebView = null;
      _savedSessionUrl = null;
      _isConnected = false;
      _hasReportedFailure = false;
      _isActive = false;
      await _releaseBackgroundSession();
      reportState();
    }
  }

  bool get isConnected => _isConnected;
  bool get isActive => _isActive;
  String? get savedSessionUrl => _savedSessionUrl;

  Future<void> softRefresh() => _operations.enqueue(_softRefresh);

  Future<void> _softRefresh() async {
    await _capturePlayback('foreground-before');
    if (!_isActive || _headlessWebView == null || _savedSessionUrl == null) {
      return;
    }

    final controller = _headlessWebView!;

    final result = await controller.evaluateJavascript('''
      (function() {
        const rangeInput = document.querySelector('input[type="range"]');
        return {
          hasRangeInput: !!rangeInput
        };
      })();
    ''');

    if (!_isActive) {
      return;
    }

    if (result == null) {
      await _reconnect();
      return;
    }

    final hasRangeInput = result['hasRangeInput'] == true;

    if (!hasRangeInput) {
      await _reconnect();
    }
    await _capturePlayback('foreground-after');
  }

  Future<void> _capturePlayback(String event) =>
      AudioPlaybackDiagnostics.capture(
        event,
        _headlessWebView,
        active: _isActive,
        connected: _isConnected,
      );

  Future<void> _acquireBackgroundSession() async {
    if (_backgroundSessionHeld) return;
    _backgroundSessionHeld = await AudioBackgroundSession.acquire(
      _backgroundSessionOwner,
    );
  }

  Future<void> _releaseBackgroundSession() async {
    if (!_backgroundSessionHeld) return;
    _backgroundSessionHeld = !await AudioBackgroundSession.release(
      _backgroundSessionOwner,
    );
  }
}
