import 'dart:io';

import 'package:flutter/services.dart';

import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

import 'tailscale_models.dart';

class TailscaleEmbeddedClient implements TailscaleClient {
  TailscaleEmbeddedClient({
    MethodChannel? methods,
    EventChannel? events,
  }) : _methods = methods ?? const MethodChannel('monkeycraft/tailscale'),
       _events = events ?? const EventChannel('monkeycraft/tailscale_events');

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  bool get isSupported => Platform.isIOS;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events {
    if (!isSupported) return const Stream.empty();
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return TailscaleEmbeddedSnapshot.fromMap(event);
      }
      return const TailscaleEmbeddedSnapshot(phase: 'unavailable');
    });
  }

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    if (!isSupported) {
      return const TailscaleDiagnostics(
        available: false,
        libtailscaleLinked: false,
        statusJsonAvailable: false,
        reason: 'embedded Tailscale is iOS-only in this round',
      );
    }
    final raw = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'diagnostics',
    );
    return TailscaleDiagnostics.fromMap(raw ?? const {});
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async {
    if (!isSupported) {
      return const TailscaleEmbeddedSnapshot(phase: 'unavailable');
    }
    final raw = await _methods.invokeMethod<Map<dynamic, dynamic>>('status');
    return TailscaleEmbeddedSnapshot.fromMap(raw ?? const {});
  }

  @override
  Future<List<TailscalePeer>> listPeers() async {
    if (!isSupported) return const [];
    final raw = await _methods.invokeMethod<List<dynamic>>('listPeers');
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(TailscalePeer.fromMap)
        .where((p) => p.nodeId.isNotEmpty)
        .toList();
  }

  @override
  Future<void> start() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('start');
  }

  @override
  Future<void> loginInteractive() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('loginInteractive');
  }

  @override
  Future<void> cancel() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('cancel');
  }

  @override
  Future<void> logout() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('logout');
  }

  @override
  Future<void> stop() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('stop');
  }

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('embedded Tailscale is iOS-only in this round');
    }
    final raw = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'openBridge',
      {'nodeId': nodeId, 'port': port},
    );
    final lease = TailscaleBridgeLease.fromMap(raw ?? const {});
    if (lease.url.isEmpty || lease.leaseId.isEmpty) {
      throw StateError('bridge did not return a loopback url');
    }
    if (!lease.url.startsWith('ws://127.0.0.1:')) {
      throw StateError('bridge url was not loopback');
    }
    return lease;
  }

  @override
  Future<void> closeBridge(String leaseId) async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('closeBridge', {'leaseId': leaseId});
  }
}
