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
      reason: 'embedded Tailscale is iOS-only in this round',
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
  Future<void> loginInteractive() async {}

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
    throw UnsupportedError('embedded Tailscale is iOS-only in this round');
  }

  @override
  Future<void> closeBridge(String leaseId) async {}
}
