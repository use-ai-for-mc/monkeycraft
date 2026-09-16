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
  String? _pendingAuthUrl;
  web.Window? _authWindow;

  @override
  bool get isSupported => kIsWeb;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => _events.stream;

  @override
  TransportFactory? get gameTransportFactory =>
      TailscaleWebTransportFactory(_dialFromWsUrl);

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    return const TailscaleDiagnostics(
      available: true,
      libtailscaleLinked: true,
      statusJsonAvailable: true,
      reason: 'web wasm worker',
      tailscaleGoModule: 'tailscale.com v1.102.3',
    );
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async => _snapshot;

  @override
  Future<List<TailscalePeer>> listPeers() async => _snapshot.peers;

  @override
  Future<void> start() async {
    if (_started) return;
    _ensureWorker();
    _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'starting'));
    final origin = web.window.location.href;
    final wasmUrl = Uri.parse(origin).resolve('tailscale/main.wasm').toString();
    final execUrl = Uri.parse(
      origin,
    ).resolve('tailscale/wasm_exec.js').toString();
    await _request('init', {
      'backend': 'wasm',
      'hostname': 'monkeycraft-web',
      'wasmUrl': wasmUrl,
      'wasmExecUrl': execUrl,
    }, timeout: const Duration(seconds: 120));
    _started = true;
  }

  @override
  Future<void> loginInteractive() async {
    await start();
    _authWindow = web.window.open('about:blank', 'ts-auth', 'width=480,height=720');
    if (_pendingAuthUrl != null && _authWindow != null) {
      _navigateAuth(_pendingAuthUrl!);
    }
    await _request('login', {});
  }

  @override
  Future<void> cancel() async {
    await logout();
  }

  @override
  Future<void> logout() async {
    if (_worker == null) return;
    try {
      await _request('logout', {});
    } catch (_) {}
    _pendingAuthUrl = null;
    _started = false;
    _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'stopped'));
  }

  @override
  Future<void> stop() async {
    await logout();
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
    final url = 'ws://$host:$port';
    return TailscaleBridgeLease(url: url, leaseId: nodeId);
  }

  @override
  Future<void> closeBridge(String leaseId) async {
    for (final id in List<String>.from(_conns.keys)) {
      await _closeConn(id);
    }
  }

  Future<TailscaleTcpConn> _dialFromWsUrl(Uri url) async {
    await start();
    final host = url.host;
    final port = url.hasPort ? url.port : 9600;
    final res = await _request('dialTcp', {
      'host': host,
      'port': port,
      'timeoutMs': 15000,
    });
    final connId = res.payload['connId'] as String? ?? '';
    if (connId.isEmpty) throw StateError('dialTcp missing connId');
    final live = _LiveConn(connId);
    _conns[connId] = live;
    return TailscaleTcpConn(
      write: (bytes) async {
        await _request('connWrite', {'connId': connId}, buffer: bytes);
      },
      read: () async {
        if (live.closed) return null;
        final res = await _request('connRead', {'connId': connId, 'max': 65536});
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
      web.window.location.href,
    ).resolve('tailscale/worker.js').toString();
    _worker = web.Worker(workerUrl.toJS, web.WorkerOptions(type: 'module'));
    _worker!.addEventListener(
      'message',
      ((web.MessageEvent ev) {
        _onMessage(ev.data);
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
    if (pending == null) return;
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
      _RpcRes(
        Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
        buffer,
      ),
    );
  }

  void _onEvent(Map<String, dynamic> map) {
    final method = map['method'] as String? ?? '';
    final payload = Map<String, dynamic>.from(map['payload'] as Map? ?? {});
    if (method == 'state') {
      final ipn = payload['ipn'] as String? ?? '';
      final phase = _mapIpn(ipn);
      _setSnapshot(
        TailscaleEmbeddedSnapshot(
          phase: phase,
          backendState: ipn,
          peers: _snapshot.peers,
          nodeId: _snapshot.nodeId,
        ),
      );
    } else if (method == 'browseToURL') {
      final url = payload['url'] as String?;
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
            addr = addrs.first.toString();
          }
          final id = (item['stableId'] ?? item['nodeId'] ?? '').toString();
          if (id.isEmpty) continue;
          peers.add(
            TailscalePeer(
              nodeId: id,
              hostName: (item['name'] ?? '').toString(),
              online: item['online'] == true,
              dnsName: addr,
            ),
          );
        }
      }
      _setSnapshot(
        TailscaleEmbeddedSnapshot(
          phase: _snapshot.phase == 'stopped' ? 'running' : _snapshot.phase,
          peers: peers,
          nodeId: payload['selfStableId'] as String?,
        ),
      );
    } else if (method == 'cleared') {
      _setSnapshot(const TailscaleEmbeddedSnapshot(phase: 'stopped'));
    }
  }

  void _navigateAuth(String url) {
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
      return Future.error(StateError('worker not started'));
    }
    if (buffer != null) {
      worker.postMessage(_dartToJs({...msg, 'buffer': buffer}));
    } else {
      worker.postMessage(_dartToJs(msg));
    }
    return completer.future.timeout(timeout);
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
