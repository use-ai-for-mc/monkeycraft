import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class OpenAudioMcService {
  static const _urlPrefix = 'https://session.openaudiomc.net/';
  static const _maxReconnectAttempts = 3;
  static const _monitorIntervalMs = 3000;
  static const _connectionTimeoutMs = 30000;

  HeadlessInAppWebView? _headlessWebView;
  String? _savedSessionUrl;
  bool _isConnected = false;
  bool _hasReportedFailure = false;
  bool _isActive = false;
  int _reconnectAttempts = 0;
  Timer? _monitorTimer;
  int _monitorElapsedMs = 0;
  void Function(Map<String, dynamic> infoPacket)? _onInfoPacket;
  void Function()? _onFailure;

  static bool isOpenAudioMcUrl(String url) {
    return url.startsWith(_urlPrefix);
  }

  void setInfoPacketHandler(
    void Function(Map<String, dynamic> infoPacket) handler,
  ) {
    _onInfoPacket = handler;
  }

  void setOnFailureHandler(void Function() handler) {
    _onFailure = handler;
  }

  void _sendInfoPacket(String title, Map<String, dynamic> data) {
    if (_onInfoPacket != null) {
      final packet = <String, dynamic>{
        'type': 'INFO',
        'title': title,
        'data': data,
      };
      _onInfoPacket!(packet);
    }
  }

  Future<void> initialize() async {
    _headlessWebView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        ignoresViewportScaleLimits: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
    );

    await _headlessWebView!.run();
  }

  Future<void> connect(String sessionUrl) async {
    if (_isActive) {
      await disconnect();
    }
    _isActive = true;

    if (_headlessWebView == null) {
      await initialize();
    }

    _savedSessionUrl = sessionUrl;
    _reconnectAttempts = 0;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;

    _sendInfoPacket('openaudiomc', {'connected': false});

    await _headlessWebView!.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(sessionUrl)),
    );

    _startMonitoring();
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorElapsedMs = 0;
    _monitorTimer = Timer.periodic(Duration(milliseconds: _monitorIntervalMs), (
      _,
    ) async {
      await _monitorSession();
    });
  }

  Future<void> _monitorSession() async {
    if (_headlessWebView == null) return;

    final controller = _headlessWebView!.webViewController;
    if (controller == null) return;

    _monitorElapsedMs += _monitorIntervalMs;

    final result = await controller.evaluateJavascript(
      source: '''
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
    ''',
    );

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
        await controller.evaluateJavascript(
          source: '''
          (function() {
            const buttons = [...document.querySelectorAll('button')];
            const startButton = buttons.find(btn => btn.outerText.trim().toLowerCase() === 'start audio session');
            if (startButton) {
              startButton.click();
              return true;
            }
            return false;
          })();
        ''',
        );
      } else if (!hasSession && _savedSessionUrl != null && _isConnected) {
        if (_reconnectAttempts >= _maxReconnectAttempts) {
          await _handleFailure('max_reconnect');
          return;
        }

        _reconnectAttempts++;
        _isConnected = false;
        _sendInfoPacket('openaudiomc', {'connected': false});
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(_savedSessionUrl!)),
        );
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
    _sendInfoPacket('openaudiomc', {'connected': false, 'error': error});

    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _savedSessionUrl = null;
    _isConnected = false;

    _onFailure?.call();
  }

  Future<void> disconnect() async {
    _monitorTimer?.cancel();
    _isConnected = false;
    _hasReportedFailure = false;
    _isActive = false;
    _sendInfoPacket('openaudiomc', {'connected': false});

    await _headlessWebView?.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
  }

  Future<void> reconnect() async {
    if (_savedSessionUrl == null) return;

    _isActive = true;
    _reconnectAttempts = 0;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;
    _sendInfoPacket('openaudiomc', {'connected': false});

    await _headlessWebView?.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_savedSessionUrl!)),
    );

    _startMonitoring();
  }

  Future<void> dispose() async {
    _monitorTimer?.cancel();
    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _savedSessionUrl = null;
    _isConnected = false;
    _hasReportedFailure = false;
    _isActive = false;
  }

  bool get isConnected => _isConnected;
  bool get isActive => _isActive;
  String? get savedSessionUrl => _savedSessionUrl;

  Future<void> softRefresh() async {
    if (!_isActive || _headlessWebView == null || _savedSessionUrl == null) {
      return;
    }

    final controller = _headlessWebView!.webViewController;
    if (controller == null) {
      return;
    }

    final result = await controller.evaluateJavascript(
      source: '''
      (function() {
        const rangeInput = document.querySelector('input[type="range"]');
        return {
          hasRangeInput: !!rangeInput
        };
      })();
    ''',
    );

    if (result == null) {
      await reconnect();
      return;
    }

    final hasRangeInput = result['hasRangeInput'] == true;

    if (!hasRangeInput) {
      await reconnect();
    }
  }
}
