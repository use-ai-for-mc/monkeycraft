import 'dart:async';
import 'dart:collection';

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

  /// Only https URLs on the MCParks domain are loaded into the headless
  /// WebView — a session URL arrives from server chat, so the host/scheme
  /// must be pinned to keep an untrusted server from running arbitrary
  /// pages (with JS) in our hidden, mixed-content-allowed WebView.
  static bool isMcParksUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'mcparks.us' || host.endsWith('.mcparks.us');
  }

  // Document-start user script that monkey-patches window.WebSocket
  // before the MCParks bundle runs, so every inbound audio protocol
  // message is counted against a per-name stats object. The underlying
  // audio plays via Howler inside the page; we don't consume the
  // protocol ourselves, we only observe it.
  //
  // Protocol (from the reference Java impl of MCParks Experience):
  //   "stop"                   — fade all active sounds
  //   "stop-<name>"            — fade one sound
  //   "loop-<seekMs>-<name>"   — looping track
  //   "show-<seekMs>-<name>"   — one-shot
  //   "<name>"                 — bare play
  //
  // Stats shape (window.__mcpStats[name]):
  //   { firstMs, lastMs, count, lastMsg, fading, fadeAtMs }
  //
  // `fading` is best-effort: flipped true on stop-<name>/stop from the
  // server, or on our own stopSoundByName. Howler itself removes the
  // Howl from _howls on unload, which is the source of truth for
  // "still playing."
  static final _statsHookScript = UserScript(
    source: r'''
      (function(){
        if (window.__mcpStatsInstalled) return;
        window.__mcpStatsInstalled = true;
        window.__mcpStats = {};
        var Original = window.WebSocket;
        function Patched(url, protocols){
          var ws = protocols === undefined
            ? new Original(url)
            : new Original(url, protocols);
          try { window.__mcpActiveWs = ws; } catch(e){}
          ws.addEventListener('message', function(ev){
            try {
              var msg = typeof ev.data === 'string' ? ev.data : '';
              if (!msg) return;
              var now = Date.now();
              if (msg === 'stop') {
                for (var k in window.__mcpStats) {
                  window.__mcpStats[k].fading = true;
                  window.__mcpStats[k].fadeAtMs = now;
                }
                return;
              }
              if (msg.indexOf('stop-') === 0) {
                var sname = msg.substring(5);
                var sst = window.__mcpStats[sname];
                if (sst) { sst.fading = true; sst.fadeAtMs = now; }
                return;
              }
              var name = null;
              if (msg.indexOf('loop-') === 0 || msg.indexOf('show-') === 0) {
                var payload = msg.substring(5);
                var dash = payload.indexOf('-');
                if (dash > 0) name = payload.substring(dash + 1);
              } else {
                name = msg;
              }
              if (!name) return;
              var s = window.__mcpStats[name];
              if (!s) {
                window.__mcpStats[name] = {
                  firstMs: now, lastMs: now, count: 1, lastMsg: msg,
                  fading: false, fadeAtMs: 0,
                };
              } else {
                s.lastMs = now;
                s.count += 1;
                s.lastMsg = msg;
                s.fading = false;
                s.fadeAtMs = 0;
              }
            } catch(e){}
          });
          return ws;
        }
        Patched.prototype = Original.prototype;
        try {
          Patched.CONNECTING = Original.CONNECTING;
          Patched.OPEN = Original.OPEN;
          Patched.CLOSING = Original.CLOSING;
          Patched.CLOSED = Original.CLOSED;
        } catch(e){}
        window.WebSocket = Patched;
      })();
    ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
  );

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
      initialUserScripts: UnmodifiableListView([_statsHookScript]),
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
    // localStorage value, which we don't share). IIFE with no return
    // because Howler.volume() returns the Howler singleton (chainable
    // API), which holds a cyclic Web Audio graph — serializing that
    // back across the platform channel blows the main-thread stack
    // inside FlutterStandardCodecHelperWriteUTF8.
    if (howlerReady) {
      await controller.evaluateJavascript(
        source: '(function(){ window.Howler.volume($_volume); })();',
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
          '(function(){ if (window.Howler && typeof window.Howler.volume === "function") { window.Howler.volume($_volume); } })();',
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
      // IIFE with no return — see monitor's Howler.volume() call for why.
      await controller.evaluateJavascript(
        source:
            '(function(){ if (window.Howler && typeof window.Howler.unload === "function") { try { window.Howler.unload(); } catch(e){} } })();',
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

  /// Snapshot of currently-audible MCParks tracks. Merges the live state
  /// of each Howl instance in the page (source URL, looping, volume,
  /// seek position, playing) with the per-name trigger stats collected
  /// by the document-start WebSocket hook. Same shape as the reference
  /// mod's ActiveTrack record.
  Future<List<McParksActiveTrack>> snapshotActive() async {
    final controller = _headlessWebView?.webViewController;
    if (controller == null) return const [];

    final result = await controller.evaluateJavascript(
      source: r'''
        (function(){
          var out = [];
          var howls = window.Howler && window.Howler._howls;
          if (!howls) return out;
          var stats = window.__mcpStats || {};
          for (var i = 0; i < howls.length; i++) {
            var h = howls[i];
            var src = null;
            try { src = Array.isArray(h._src) ? h._src[0] : h._src; } catch(e){}
            if (!src) continue;
            var sstr = String(src);
            var name = null;
            var m = sstr.match(/\/audio_files\/([^./]+)\./);
            if (m) { name = m[1]; }
            else {
              var tail = sstr.split('/').pop();
              var dot = tail.lastIndexOf('.');
              name = dot > 0 ? tail.substring(0, dot) : tail;
            }
            if (!name) continue;
            var playing = false;
            try { playing = !!h.playing(); } catch(e){}
            var vol = 0;
            try { vol = (typeof h.volume === 'function') ? h.volume() : (h._volume || 0); } catch(e){}
            var posMs = 0;
            try {
              var seek = (typeof h.seek === 'function') ? h.seek() : 0;
              if (typeof seek === 'number' && isFinite(seek)) posMs = Math.floor(seek * 1000);
            } catch(e){}
            var s = stats[name];
            out.push({
              name: name,
              url: sstr,
              looping: !!h._loop,
              serverVolume: Math.round((vol || 0) * 100),
              startedAtMs: s ? s.lastMs : null,
              firstTriggerMs: s ? s.firstMs : null,
              lastTriggerMs: s ? s.lastMs : null,
              triggerCount: s ? s.count : 1,
              lastMessage: s ? s.lastMsg : name,
              active: playing,
              fadingOut: !!(s && s.fading),
              positionMs: posMs,
            });
          }
          out.sort(function(a, b){
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
          });
          return out;
        })();
      ''',
    );

    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(McParksActiveTrack.fromJson)
        .toList(growable: false);
  }

  /// Fade out and unload a specific MCParks track by server-assigned
  /// name. Returns true if a matching Howl was found in the page's
  /// Howler registry. Mirrors the reference mod's stopSoundByName
  /// shape (pre-check, fade with the 3s window, drop stats entry).
  Future<bool> stopSoundByName(String name) async {
    final controller = _headlessWebView?.webViewController;
    if (controller == null) return false;

    // The name travels inside a JS string literal; server names are
    // simple [A-Za-z0-9-_] but be defensive about embed hazards.
    final escaped = name
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', '')
        .replaceAll('\r', '');

    final result = await controller.evaluateJavascript(
      source:
          '''
        (function(){
          var target = '$escaped';
          var howls = window.Howler && window.Howler._howls;
          if (!howls) return false;
          for (var i = 0; i < howls.length; i++) {
            var h = howls[i];
            var src = null;
            try { src = Array.isArray(h._src) ? h._src[0] : h._src; } catch(e){}
            if (!src) continue;
            var sstr = String(src);
            var hname = null;
            var m = sstr.match(/\\/audio_files\\/([^./]+)\\./);
            if (m) { hname = m[1]; }
            else {
              var tail = sstr.split('/').pop();
              var dot = tail.lastIndexOf('.');
              hname = dot > 0 ? tail.substring(0, dot) : tail;
            }
            if (hname !== target) continue;
            try {
              var vol = (typeof h.volume === 'function') ? h.volume() : (h._volume || 1);
              h.fade(vol, 0, 3000);
              setTimeout(function(){ try { h.unload(); } catch(e){} }, 3100);
            } catch(e) {
              try { h.stop(); } catch(e2){}
            }
            if (window.__mcpStats && window.__mcpStats[target]) {
              window.__mcpStats[target].fading = true;
              window.__mcpStats[target].fadeAtMs = Date.now();
            }
            return true;
          }
          return false;
        })();
      ''',
    );

    return result == true;
  }
}

/// Snapshot of one active MCParks audio track at a point in time.
/// Mirrors the reference Java mod's ActiveTrack record field-for-field
/// so the two feel like sibling surfaces.
class McParksActiveTrack {
  final String name;
  final String? url;
  final bool looping;
  final int serverVolume;
  final DateTime? startedAt;
  final DateTime? firstTriggerAt;
  final DateTime? lastTriggerAt;
  final int triggerCount;
  final String lastServerMessage;
  final bool active;
  final bool fadingOut;
  final int positionMs;

  const McParksActiveTrack({
    required this.name,
    this.url,
    required this.looping,
    required this.serverVolume,
    this.startedAt,
    this.firstTriggerAt,
    this.lastTriggerAt,
    required this.triggerCount,
    required this.lastServerMessage,
    required this.active,
    required this.fadingOut,
    required this.positionMs,
  });

  factory McParksActiveTrack.fromJson(Map json) {
    DateTime? dt(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return McParksActiveTrack(
      name: (json['name'] as String?) ?? '<unknown>',
      url: json['url'] as String?,
      looping: json['looping'] == true,
      serverVolume: (json['serverVolume'] as num?)?.toInt() ?? 0,
      startedAt: dt(json['startedAtMs']),
      firstTriggerAt: dt(json['firstTriggerMs']),
      lastTriggerAt: dt(json['lastTriggerMs']),
      triggerCount: (json['triggerCount'] as num?)?.toInt() ?? 1,
      lastServerMessage: (json['lastMessage'] as String?) ?? '',
      active: json['active'] == true,
      fadingOut: json['fadingOut'] == true,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Short human-readable diagnosis. Port of the reference mod's
  /// diagnoseTrack rules — same wording so the two surfaces agree on
  /// what counts as a zombie / duplicate / stuck track. Returns null
  /// when nothing noteworthy is going on.
  String? diagnose(DateTime now) {
    if (!active) {
      return 'finished playing; stale entry, safe to stop';
    }
    if (fadingOut) {
      return 'fading out';
    }
    if (looping && triggerCount == 1) {
      return 'server sent one loop command; will play until server says stop';
    }
    if (looping && triggerCount > 1) {
      return 'server re-triggered ${triggerCount}x; possible server-side duplicate';
    }
    if (!looping && startedAt != null) {
      final age = now.difference(startedAt!);
      if (age.inSeconds > 30) {
        return 'one-shot still running after 30s+; long audio or stuck';
      }
    }
    return null;
  }
}
