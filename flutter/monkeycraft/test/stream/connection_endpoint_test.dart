import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/connection_endpoint.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';
import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

class _FakeTailscale implements TailscaleClient {
  _FakeTailscale({this.phase = 'stopped'});

  String phase;
  var startCount = 0;
  var openCount = 0;
  var closeCount = 0;
  final closed = <String>[];

  @override
  bool get isSupported => true;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => const Stream.empty();

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    throw UnimplementedError();
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async {
    return TailscaleEmbeddedSnapshot(phase: phase);
  }

  @override
  Future<List<TailscalePeer>> listPeers() async => const [];

  @override
  Future<void> start() async {
    startCount += 1;
    phase = 'running';
  }

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
    openCount += 1;
    return TailscaleBridgeLease(
      url: 'ws://127.0.0.1:${40000 + openCount}',
      leaseId: 'lease-$openCount',
    );
  }

  @override
  Future<void> closeBridge(String leaseId) async {
    closeCount += 1;
    closed.add(leaseId);
  }
}

void main() {
  test('DirectEndpoint returns the same address', () async {
    final endpoint = DirectEndpoint('192.168.1.8:9600');
    expect(await endpoint.resolve(), '192.168.1.8:9600');
    await endpoint.pause();
    expect(await endpoint.resolve(), '192.168.1.8:9600');
  });

  test('EmbeddedTailscaleEndpoint starts node, closes old lease, opens new', () async {
    final client = _FakeTailscale();
    final endpoint = EmbeddedTailscaleEndpoint(
      client: client,
      nodeId: 'pc1',
      leaseId: 'old',
      lastLoopbackUrl: 'ws://127.0.0.1:9600',
    );
    final url = await endpoint.resolve();
    expect(client.startCount, 1);
    expect(client.closed, ['old']);
    expect(url, 'ws://127.0.0.1:40001');
    expect(endpoint.leaseId, 'lease-1');
    await endpoint.pause();
    expect(client.closed, ['old', 'lease-1']);
    expect(endpoint.leaseId, isNull);
  });

  test('EmbeddedTailscaleEndpoint skips start when already running', () async {
    final client = _FakeTailscale(phase: 'running');
    final endpoint = EmbeddedTailscaleEndpoint(client: client, nodeId: 'pc1');
    await endpoint.resolve();
    expect(client.startCount, 0);
    expect(client.openCount, 1);
  });
}
