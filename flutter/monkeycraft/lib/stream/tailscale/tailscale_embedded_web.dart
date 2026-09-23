import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:monkeycraft_client/stream/transport/connection_transport.dart';
import 'package:monkeycraft_client/stream/transport/tailscale_web_transport.dart';
import 'tailscale_models.dart';

class TailscaleEmbeddedClient implements TailscaleClient {
  TailscaleEmbeddedClient();

  web.Worker? _worker;
  int _id = 0;
  final Map<String, Completer<_RpcRes>> _pending = {};
  final StreamController<TailscaleEmbeddedSnapshot> _events =
      StreamController<TailscaleEmbeddedSnapshot>.broadcast();
  TailscaleEmbeddedSnapshot _snapshot = const TailscaleEmbeddedSnapshot(
    phase: 'stopped',
  );
  final Map<String, _LiveConn> _conns = {};
  bool _started = false;
  Future<void>? _starting;
  Future<void>? _stopping;
  int _generation = 0;
  int _leaseSequence = 0;
  String? _activeLease;
  String? _pendingAuthUrl;
  web.Window? _authWindow;

  @override
  bool get isSupported =>
      kIsWeb &&
      web.window.isSecureContext &&
      const bool.fromEnvironment(
        'MONKEYCRAFT_WEB_TAILSCALE',
        defaultValue: false,
      );

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => _events.stream;

  @override
  TransportFactory? get gameTransportFactory =>
      TailscaleWebTransportFactory(_dialFromWsUrl);

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    return TailscaleDiagnostics(
      available: isSupported,
      libtailscaleLinked: true,
      statusJsonAvailable: true,
      reason: isSupported
          ? 'available'
          : 'Open MonkeyCraft over HTTPS to use Tailscale.',
      tailscaleGoModule: 'tailscale.com v1.102.3',
    );
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async => _snapshot;

  @override
  Future<List<TailscalePeer>> listPeers() async => _snapshot.peers;

  @override
  Future<void> start() {
    if (_stopping != null) return _stopping!.then((_) => start());
    if (_started) return Future.value();
    if (_starting != null) return _starting!;
    if (!isSupported) {
      return Future.error(
        StateError('Tailscale is unavailable in this browser.'),
      );
    }
    final generation = _generation;
    late final Future<void> operation;
    operation = _start(generation).whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
    _starting = operation;
    return operation;
  }

  Future<void> _start(int generation) async {
    _ensureWorker();
    _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'starting'));
    final base = Uri.parse(web.document.baseURI);
    try {
      await _request('init', {
        'backend': 'wasm',
        'hostname': 'monkeycraft-web',
        'persistIdentity': true,
        'wasmUrl': base.resolve('tailscale/main.wasm').toString(),
        'wasmExecUrl': base.resolve('tailscale/wasm_exec.js').toString(),
      }, timeout: const Duration(seconds: 120));
      if (generation != _generation) throw StateError('Connection cancelled.');
      _started = true;
    } catch (error) {
      if (generation == _generation) _fail('$error');
      rethrow;
    }
  }

  @override
  Future<void> loginInteractive() async {
    _authWindow = web.window.open(
      'about:blank',
      '_blank',
      'width=480,height=720',
    );
    try {
      _authWindow?.opener = null;
    } catch (_) {}
    await start();
    if (_pendingAuthUrl != null) {
      _navigateAuth(_pendingAuthUrl!);
    } else {
      await _request('login', {});
    }
  }

  @override
  Future<void> cancel() => stop();

  @override
  Future<void> logout() async {
    if (_worker != null) await _request('logout', {});
    await stop();
  }

  @override
  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    late final Future<void> operation;
    operation = _stop().whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
    _stopping = operation;
    return operation;
  }

  Future<void> _stop() async {
    _generation++;
    _started = false;
    _starting = null;
    _pendingAuthUrl = null;
    try {
      _authWindow?.close();
    } catch (_) {}
    _authWindow = null;
    if (_worker != null) {
      try {
        await _request('shutdown', {}, timeout: const Duration(seconds: 5));
      } catch (_) {}
    }
    _terminate();
    _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'stopped'));
  }

  void _terminate() {
    _worker?.terminate();
    _worker = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Tailscale connection closed.'));
      }
    }
    _pending.clear();
    for (final conn in _conns.values) {
      conn.close();
    }
    _conns.clear();
  }

  void _fail(String message) {
    _generation++;
    _started = false;
    _starting = null;
    _terminate();
    _setSnapshot(
      TailscaleEmbeddedSnapshot(phase: 'failed', errorMessage: message),
    );
  }

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async {
    final peer = _snapshot.peers.where((p) => p.nodeId == nodeId).toList();
    if (peer.isEmpty) {
      throw StateError('unknown tailscale node');
    }
    final host = peer.first.dnsName;
    if (host == null || host.isEmpty) {
      throw StateError('peer has no address');
    }
    final url = Uri(scheme: 'ws', host: host, port: port).toString();
    _activeLease = 'web-${++_leaseSequence}';
    return TailscaleBridgeLease(url: url, leaseId: _activeLease!);
  }

  @override
  Future<void> closeBridge(String leaseId) async {
    if (leaseId != _activeLease) return;
    _activeLease = null;
    for (final id in List<String>.from(_conns.keys)) {
      await _closeConn(id);
    }
  }

  Future<TailscaleTcpConn> _dialFromWsUrl(Uri url) async {
    await start();
    final host = url.host;
    final port = url.hasPort ? url.port : 9600;
    final lease = _activeLease;
    final res = await _request('dialTcp', {
      'host': host,
      'port': port,
      'timeoutMs': 15000,
    });
    final connId = res.payload['connId'] as String? ?? '';
    if (connId.isEmpty) throw StateError('dialTcp missing connId');
    if (lease != _activeLease || lease == null) {
      await _closeConn(connId);
      throw StateError('Connection cancelled.');
    }
    final live = _LiveConn(connId);
    _conns[connId] = live;
    return TailscaleTcpConn(
      write: (bytes) async {
        var offset = 0;
        while (offset < bytes.length) {
          final result = await _request('connWrite', {
            'connId': connId,
          }, buffer: Uint8List.sublistView(bytes, offset));
          final n = result.payload['n'];
          if (n is! int || n <= 0 || n > bytes.length - offset) {
            throw StateError('Incomplete Tailscale write.');
          }
          offset += n;
        }
      },
      read: () async {
        if (live.closed) return null;
        final res = await _request('connRead', {
          'connId': connId,
          'max': 65536,
        });
        if (res.buffer != null && res.buffer!.isNotEmpty) {
          return res.buffer;
        }
        if (res.payload['eof'] == true) return null;
        final n = res.payload['n'];
        if (n is int && n == 0 && res.payload['eof'] == true) return null;
        return res.buffer ?? Uint8List(0);
      },
      close: () => _closeConn(connId),
    );
  }

  Future<void> _closeConn(String connId) async {
    final live = _conns.remove(connId);
    live?.close();
    try {
      await _request('connClose', {'connId': connId});
    } catch (_) {}
  }

  void _ensureWorker() {
    if (_worker != null) return;
    final workerUrl = Uri.parse(
      web.document.baseURI,
    ).resolve('tailscale/worker.js').toString();
    _worker = web.Worker(workerUrl.toJS, web.WorkerOptions(type: 'module'));
    final worker = _worker;
    _worker!.addEventListener(
      'error',
      ((web.Event _) {
        _fail('Tailscale stopped unexpectedly. Please reconnect.');
      }).toJS,
    );
    _worker!.addEventListener(
      'messageerror',
      ((web.Event _) {
        _fail('Tailscale connection could not be read. Please reconnect.');
      }).toJS,
    );
    _worker!.addEventListener(
      'message',
      ((web.MessageEvent ev) {
        if (identical(worker, _worker)) _onMessage(ev.data);
      }).toJS,
    );
  }

  void _onMessage(JSAny? data) {
    if (data == null) return;
    final map = _jsToMap(data as JSObject);
    final kind = map['kind'] as String? ?? '';
    if (kind == 'evt') {
      _onEvent(map);
      return;
    }
    if (kind != 'res') return;
    final id = map['id'] as String? ?? '';
    final pending = _pending.remove(id);
    if (pending == null) {
      final payload = map['payload'];
      if (payload is Map && payload['connId'] is String) {
        unawaited(_closeConn(payload['connId'] as String));
      }
      return;
    }
    if (map['ok'] == false) {
      final err = map['error'];
      final message = err is Map ? (err['message'] ?? 'error') : 'error';
      pending.completeError(StateError('$message'));
      return;
    }
    Uint8List? buffer;
    final rawBuf = map['buffer'];
    if (rawBuf is ByteBuffer) {
      buffer = rawBuf.asUint8List();
    } else if (rawBuf is Uint8List) {
      buffer = rawBuf;
    }
    pending.complete(
      _RpcRes(Map<String, dynamic>.from(map['payload'] as Map? ?? {}), buffer),
    );
  }

  void _onEvent(Map<String, dynamic> map) {
    final method = map['method'] as String? ?? '';
    final payload = Map<String, dynamic>.from(map['payload'] as Map? ?? {});
    if (method == 'state') {
      final ipn = payload['ipn'] as String? ?? '';
      final phase = _mapIpn(ipn);
      if (phase == 'running') {
        _pendingAuthUrl = null;
        try {
          _authWindow?.close();
        } catch (_) {}
        _authWindow = null;
      }
      _setSnapshot(
        TailscaleEmbeddedSnapshot(
          phase: phase,
          backendState: ipn,
          peers: _snapshot.peers,
          nodeId: _snapshot.nodeId,
          authUrlHost: _pendingAuthUrl == null
              ? null
              : Uri.tryParse(_pendingAuthUrl!)?.host,
        ),
      );
    } else if (method == 'browseToURL') {
      final url = payload['url'] as String?;
      if (url != null && !_validAuthUrl(url)) {
        _fail('Tailscale returned an invalid sign-in link.');
        return;
      }
      _pendingAuthUrl = url;
      if (url != null) _navigateAuth(url);
      if (_snapshot.phase != 'running') {
        _setSnapshot(
          TailscaleEmbeddedSnapshot(
            phase: 'needsLogin',
            authUrlHost: url == null ? null : Uri.tryParse(url)?.host,
            peers: _snapshot.peers,
          ),
        );
      }
    } else if (method == 'netMap') {
      final peers = <TailscalePeer>[];
      final raw = payload['peers'];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final addrs = item['addresses'];
          String? addr;
          if (addrs is List && addrs.isNotEmpty) {
            addr = addrs
                .map((a) => a.toString())
                .firstWhere(
                  (a) => !a.contains(':'),
                  orElse: () => addrs.first.toString(),
                );
          }
          final id = (item['stableId'] ?? item['nodeId'] ?? '').toString();
          if (id.isEmpty) continue;
          peers.add(
            TailscalePeer(
              nodeId: id,
              hostName: (item['name'] ?? '').toString().split('.').first,
              online: item['online'] == true,
              dnsName: addr,
            ),
          );
        }
      }
      _setSnapshot(
        TailscaleEmbeddedSnapshot(
          phase: _snapshot.phase,
          backendState: _snapshot.backendState,
          authUrlHost: _snapshot.authUrlHost,
          peers: peers,
          nodeId: payload['selfStableId'] as String?,
        ),
      );
    } else if (method == 'panic') {
      _fail(
        payload['message']?.toString() ?? 'Tailscale stopped unexpectedly.',
      );
    } else if (method == 'cleared') {
      _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'stopped'));
    }
  }

  bool _validAuthUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (uri.host == 'tailscale.com' || uri.host.endsWith('.tailscale.com'));
  }

  void _navigateAuth(String url) {
    if (!_validAuthUrl(url)) return;
    final w = _authWindow;
    if (w == null) return;
    try {
      w.location.href = url;
    } catch (_) {}
  }

  String _mapIpn(String ipn) {
    switch (ipn) {
      case 'Running':
        return 'running';
      case 'NeedsLogin':
        return 'needsLogin';
      case 'NeedsMachineAuth':
        return 'needsApproval';
      case 'Starting':
        return 'starting';
      case 'Stopped':
        return 'stopped';
      default:
        return _snapshot.phase;
    }
  }

  void _setSnapshot(TailscaleEmbeddedSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_events.isClosed) _events.add(snapshot);
  }

  Future<_RpcRes> _request(
    String method,
    Map<String, dynamic> payload, {
    Uint8List? buffer,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final id = '${++_id}';
    final completer = Completer<_RpcRes>();
    _pending[id] = completer;
    final msg = <String, dynamic>{
      'protocolVersion': 1,
      'kind': 'req',
      'id': id,
      'method': method,
      'payload': payload,
    };
    final worker = _worker;
    if (worker == null) {
      _pending.remove(id);
      return Future.error(StateError('worker not started'));
    }
    if (buffer != null) {
      worker.postMessage(
        _dartToJs({...msg, 'buffer': Uint8List.fromList(buffer).buffer}),
      );
    } else {
      worker.postMessage(_dartToJs(msg));
    }
    return completer.future
        .timeout(timeout)
        .whenComplete(() => _pending.remove(id));
  }
}

class _RpcRes {
  const _RpcRes(this.payload, this.buffer);
  final Map<String, dynamic> payload;
  final Uint8List? buffer;
}

class _LiveConn {
  _LiveConn(this.id);
  final String id;
  bool _closed = false;
  bool get closed => _closed;
  void close() {
    _closed = true;
  }
}

Map<String, dynamic> _jsToMap(JSObject obj) {
  final dart = obj.dartify();
  if (dart is Map) {
    return dart.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

JSAny? _dartToJs(Object? value) => value.jsify();
