import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

import 'tailscale_models.dart';

class TailscaleEmbeddedClient implements TailscaleClient {
  const TailscaleEmbeddedClient();

  @override
  bool get isSupported => false;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => const Stream.empty();

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    return const TailscaleDiagnostics(
      available: false,
      libtailscaleLinked: false,
      statusJsonAvailable: false,
      reason: 'browser uses LAN or system Tailscale',
    );
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async {
    return const TailscaleEmbeddedSnapshot(phase: 'unavailable');
  }

  @override
  Future<List<TailscalePeer>> listPeers() async => const [];

  @override
  Future<void> start() async {}

  @override
  Future<void> loginInteractive() async {
    throw UnsupportedError('browser uses LAN or system Tailscale');
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async {
    throw UnsupportedError('browser uses LAN or system Tailscale');
  }

  @override
  Future<void> closeBridge(String leaseId) async {}
}
