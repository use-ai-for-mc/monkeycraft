import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Headless WebView wrapper for the MCParks v1 audio web client
/// (https://mcparks.us/audio?user=NAME).
///
/// The page is a React SPA that uses Howler.js + a WebSocket to
/// audiossl.mcparks.us. We load the page, auto-click the "Connect"
/// button (the React app gates the WebSocket open behind a click to
/// satisfy browser autoplay policy), and read connection state out of
/// the rendered status text. Volume is bridged through
/// window.Howler.volume(0..1), which Howler self-registers globally
/// even when bundled.
///
/// The page itself has a stale "isHttps" check that reads from React
/// Router's location object (which has no `protocol` property), so
/// the check always evaluates false — both http:// and https:// loads
/// reach the same code path. We therefore pass URLs through unchanged.
class McParksV1Service {
  static const _monitorIntervalMs = 3000;
  static const _connectionTimeoutMs = 30000;

  HeadlessInAppWebView? _headlessWebView;
  String? _savedSessionUrl;
  bool _isConnected = false;
  bool _hasReportedFailure = false;
  bool _isActive = false;
  Timer? _monitorTimer;
  int _monitorElapsedMs = 0;
  double _volume = 0.5;
  void Function(Map<String, dynamic> infoPacket)? _onInfoPacket;
  void Function()? _onFailure;

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
    // Replace any in-flight session — same shape as OpenAudioMC's connect().
    if (_isActive) {
      await disconnect();
    }
    _isActive = true;

    if (_headlessWebView == null) {
      await initialize();
    }

    _savedSessionUrl = sessionUrl;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;

    _sendInfoPacket('mcparks', {'connected': false});

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

    // Auto-click the "Connect" button if it's showing, and probe DOM for
    // the rendered status text. The React app puts status in a <b> child
    // of an item that contains the literal "Status:".
    final result = await controller.evaluateJavascript(
      source: '''
      (function() {
        var clickedConnect = false;
        var btns = document.querySelectorAll('button, .ui.button');
        for (var i = 0; i < btns.length; i++) {
          if (btns[i].textContent.trim() === 'Connect') {
            btns[i].click();
            clickedConnect = true;
            break;
          }
        }

        var status = 'unknown';
        var nodes = document.querySelectorAll('h5, .item');
        for (var i = 0; i < nodes.length; i++) {
          var t = nodes[i].textContent || '';
          if (t.indexOf('Connected!') >= 0) { status = 'connected'; break; }
          if (t.indexOf('Error!') >= 0) { status = 'error'; break; }
          if (t.indexOf('Disconnected') >= 0) { status = 'disconnected'; break; }
          if (t.indexOf('Connecting') >= 0) { status = 'connecting'; }
        }

        var howlerReady = !!(window.Howler && typeof window.Howler.volume === 'function');
        return {
          status: status,
          clickedConnect: clickedConnect,
          howlerReady: howlerReady,
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

    final status = result['status'] as String? ?? 'unknown';
    final howlerReady = result['howlerReady'] == true;

    // Once Howler is on the page, push our cached volume so the slider
    // value actually takes effect (the page's own slider defaults to
    // localStorage value, which we don't share).
    if (howlerReady) {
      await controller.evaluateJavascript(
        source: 'window.Howler.volume($_volume);',
      );
    }

    if (status == 'connected') {
      if (!_isConnected) {
        _isConnected = true;
        _hasReportedFailure = false;
        _sendInfoPacket('mcparks', {'connected': true});
      }
    } else if (status == 'error') {
      if (!_hasReportedFailure) {
        await _handleFailure('error');
      }
    } else if (status == 'disconnected') {
      if (_isConnected) {
        _isConnected = false;
        _sendInfoPacket('mcparks', {'connected': false});
      }
    } else {
      if (_monitorElapsedMs >= _connectionTimeoutMs &&
          !_isConnected &&
          !_hasReportedFailure) {
        await _handleFailure('timeout');
      }
    }
  }

  Future<void> _handleFailure(String error) async {
    _hasReportedFailure = true;
    _isActive = false;
    _monitorTimer?.cancel();
    _sendInfoPacket('mcparks', {'connected': false, 'error': error});

    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _savedSessionUrl = null;
    _isConnected = false;

    _onFailure?.call();
  }

  /// Set the global Howler volume in the WebView. Range 0.0..1.0.
  /// Cached for the next page-load too.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final controller = _headlessWebView?.webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source:
          'if (window.Howler && typeof window.Howler.volume === "function") { window.Howler.volume($_volume); }',
    );
  }

  Future<void> disconnect() async {
    _monitorTimer?.cancel();
    _isConnected = false;
    _hasReportedFailure = false;
    _isActive = false;
    _sendInfoPacket('mcparks', {'connected': false});

    final controller = _headlessWebView?.webViewController;
    if (controller != null) {
      // Politeness: stop audio cleanly before navigating away. unload()
      // tears down all active Howl instances and closes their HTMLAudio.
      await controller.evaluateJavascript(
        source:
            'if (window.Howler && typeof window.Howler.unload === "function") { try { window.Howler.unload(); } catch(e){} }',
      );
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    }
  }

  Future<void> reconnect() async {
    if (_savedSessionUrl == null) return;

    _isActive = true;
    _isConnected = false;
    _hasReportedFailure = false;
    _monitorElapsedMs = 0;
    _sendInfoPacket('mcparks', {'connected': false});

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
  double get volume => _volume;

  /// Cheap liveness probe for the app-resume path. If the WebView lost
  /// state during background (iOS often suspends WebViews and tears down
  /// their WebSockets), full-reload the session URL. Healthy means the
  /// React app is rendering "Connected!" or "Connecting..." — otherwise
  /// the page is gone, broken, or has flipped to a "Disconnected." /
  /// "Error!" state and we should re-establish.
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
        var healthy = false;
        var nodes = document.querySelectorAll('h5, .item, b');
        for (var i = 0; i < nodes.length; i++) {
          var t = nodes[i].textContent || '';
          if (t.indexOf('Connected!') >= 0 || t.indexOf('Connecting') >= 0) {
            healthy = true;
            break;
          }
        }
        return { healthy: healthy };
      })();
    ''',
    );

    if (result == null) {
      await reconnect();
      return;
    }

    if (result['healthy'] != true) {
      await reconnect();
    }
  }
}
