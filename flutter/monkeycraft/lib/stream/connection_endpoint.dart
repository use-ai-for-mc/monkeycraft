import 'dart:async';

import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';

abstract class ConnectionEndpoint {
  String get displayAddress;

  Future<String> resolve();

  Future<void> pause();
}

class DirectEndpoint implements ConnectionEndpoint {
  DirectEndpoint(this.address);

  final String address;

  @override
  String get displayAddress => address;

  @override
  Future<String> resolve() async => address;

  @override
  Future<void> pause() async {}
}

class TailscaleSignInRequired implements Exception {}

class EmbeddedTailscaleEndpoint implements ConnectionEndpoint {
  static const _runningTimeout = Duration(seconds: 30);
  static const _bridgeTimeout = Duration(seconds: 20);

  EmbeddedTailscaleEndpoint({
    required this.client,
    required this.nodeId,
    this.port = 9600,
    this.leaseId,
    this.lastLoopbackUrl,
  });

  final TailscaleClient client;
  final String nodeId;
  final int port;
  String? leaseId;
  String? lastLoopbackUrl;

  @override
  String get displayAddress => lastLoopbackUrl ?? 'tailscale:$nodeId';

  @override
  Future<String> resolve() async {
    await _ensureRunning();
    await pause();
    final pending = client.openBridge(nodeId: nodeId, port: port);
    final TailscaleBridgeLease lease;
    try {
      lease = await pending.timeout(_bridgeTimeout);
    } on TimeoutException {
      unawaited(
        pending
            .then((lateLease) => client.closeBridge(lateLease.leaseId))
            .catchError((Object _) {}),
      );
      rethrow;
    }
    leaseId = lease.leaseId;
    lastLoopbackUrl = lease.url;
    return lease.url;
  }

  @override
  Future<void> pause() async {
    final id = leaseId;
    leaseId = null;
    lastLoopbackUrl = null;
    if (id == null || id.isEmpty) return;
    try {
      await client.closeBridge(id);
    } catch (_) {}
  }

  Future<void> _ensureRunning() async {
    var snapshot = await client.status();
    if (snapshot.isRunning) return;
    await client.start();
    final deadline = DateTime.now().add(_runningTimeout);
    while (DateTime.now().isBefore(deadline)) {
      snapshot = await client.status();
      if (snapshot.isRunning) return;
      if (snapshot.needsLogin || snapshot.phase == 'needsApproval') {
        throw TailscaleSignInRequired();
      }
      if (snapshot.phase == 'failed' || snapshot.phase == 'unavailable') {
        throw StateError(snapshot.errorMessage ?? 'embedded Tailscale failed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('embedded Tailscale is not running');
  }
}
