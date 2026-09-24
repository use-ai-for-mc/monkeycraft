import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/connection_endpoint.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';

class _Client implements TailscaleClient {
  int openCount = 0;
  int closeCount = 0;
  bool available = true;
  String phase = 'running';
  Completer<void>? opening;

  @override
  Future<TailscaleEmbeddedSnapshot> status() async =>
      TailscaleEmbeddedSnapshot(phase: phase);

  @override
  Future<void> start() async {}

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async {
    final number = ++openCount;
    await opening?.future;
    if (!available) throw StateError('network recovering');
    return TailscaleBridgeLease(
      url: 'ws://127.0.0.1:${40000 + number}',
      leaseId: 'lease-$number',
    );
  }

  @override
  Future<void> closeBridge(String leaseId) async => closeCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Proxy extends StreamProxy {
  bool connected = false;
  bool rejectPassword = false;
  int starts = 0;

  @override
  bool get isConnected => connected;

  @override
  Future<void> start(
    String server,
    String password, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration authTimeout = const Duration(seconds: 5),
    bool pairIfNeeded = false,
    void Function(PairingCode code)? onPairingCode,
    void Function(String password)? onPairedPassword,
    String? Function(String? keyId)? lookupPassword,
    void Function(String keyId, String password)? onBoundPassword,
  }) async {
    starts++;
    if (rejectPassword) throw AuthFailureException('Invalid signature');
    connected = true;
  }

  @override
  Future<void> stop() async => connected = false;
}

SessionController _session(
  _Client client,
  _Proxy proxy, {
  bool browserSession = false,
}) => SessionController(
  proxy: proxy,
  settingsStore: StreamSettingsStore(),
  browserSession: browserSession,
)..setEndpoint(EmbeddedTailscaleEndpoint(client: client, nodeId: 'pc'), 'pw');

void main() {
  testWidgets('browser resume retains a healthy Tailscale connection', (
    tester,
  ) async {
    final client = _Client();
    final proxy = _Proxy()..connected = true;
    final session = _session(client, proxy, browserSession: true);
    addTearDown(session.dispose);
    session.setForeground(false);
    await tester.pump(const Duration(minutes: 1));
    session.setForeground(true);
    await session.resumeConnection();
    expect(client.openCount, 0);
    expect(client.closeCount, 0);
    expect(proxy.starts, 0);
  });

  testWidgets('browser Tailscale resumes after delayed network recovery', (
    tester,
  ) async {
    final client = _Client()..available = false;
    final proxy = _Proxy();
    final session = _session(client, proxy, browserSession: true);
    addTearDown(session.dispose);
    session.setForeground(false);
    session.handleConnectionLost();
    await tester.pump(const Duration(minutes: 1));
    expect(client.openCount, 0);
    session.setForeground(true);
    final resumed = session.resumeConnection();
    await tester.pump();
    await resumed;
    for (final seconds in [2, 4]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(client.openCount, 3);
    expect(session.state.shouldReturnToLogin, isFalse);
    client.available = true;
    await tester.pump(const Duration(seconds: 8));
    expect(session.state.connected, isTrue);
    expect(session.state.reconnectRetryCount, 0);
  });

  testWidgets('native background never consumes reconnect attempts', (
    tester,
  ) async {
    final client = _Client()..available = false;
    final session = _session(client, _Proxy());
    addTearDown(session.dispose);
    session.handleConnectionLost();
    session.setForeground(false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(client.openCount, 0);
    expect(session.state.shouldReturnToLogin, isFalse);
  });

  testWidgets('resume and pending retry share one Tailscale bridge', (
    tester,
  ) async {
    final client = _Client()..opening = Completer<void>();
    final proxy = _Proxy();
    final session = _session(client, proxy);
    addTearDown(session.dispose);
    session.handleConnectionLost();
    await tester.pump(const Duration(seconds: 1));
    final resumed = session.resumeConnection();
    await tester.pump();
    final opened = client.openCount;
    client.opening!.complete();
    await tester.pump();
    await resumed;
    expect(opened, 1);
    expect(proxy.starts, 1);
    expect(session.state.connected, isTrue);
  });

  testWidgets(
    'Tailscale recovers after three temporary failures without leaving game',
    (tester) async {
      final client = _Client()..available = false;
      final proxy = _Proxy();
      final session = _session(client, proxy);
      addTearDown(session.dispose);
      session.handleConnectionLost();
      for (final seconds in [1, 2, 4]) {
        await tester.pump(Duration(seconds: seconds));
      }
      expect(client.openCount, 3);
      expect(session.state.shouldReturnToLogin, isFalse);
      client.available = true;
      await tester.pump(const Duration(seconds: 8));
      expect(session.state.connected, isTrue);
      expect(session.state.reconnectRetryCount, 0);
    },
  );

  testWidgets('failure arriving in background waits for next foreground', (
    tester,
  ) async {
    final client = _Client()
      ..available = false
      ..opening = Completer<void>();
    final session = _session(client, _Proxy());
    addTearDown(session.dispose);
    final resumed = session.resumeConnection();
    await tester.pump();
    session.setForeground(false);
    client.opening!.complete();
    await tester.pump();
    await resumed;
    expect(session.state.reconnectRetryCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(client.openCount, 1);
    client.available = true;
    session.setForeground(true);
    final recovered = session.resumeConnection();
    await tester.pump();
    await recovered;
    expect(session.state.connected, isTrue);
  });

  testWidgets('expired Tailscale authorization returns to account selection', (
    tester,
  ) async {
    final client = _Client()..phase = 'needsLogin';
    final session = _session(client, _Proxy());
    addTearDown(session.dispose);
    final resumed = session.resumeConnection();
    await tester.pump();
    await resumed;
    expect(session.state.shouldReturnToLogin, isTrue);
    expect(client.openCount, 0);
  });

  testWidgets(
    'returning during an old bridge request discards it and reconnects',
    (tester) async {
      final client = _Client()..opening = Completer<void>();
      final proxy = _Proxy();
      final session = _session(client, proxy);
      addTearDown(session.dispose);
      final first = session.resumeConnection();
      await tester.pump();
      session.setForeground(false);
      session.setForeground(true);
      final second = session.resumeConnection();
      client.opening!.complete();
      await tester.pump();
      await Future.wait([first, second]);
      expect(client.openCount, 2);
      expect(client.closeCount, 1);
      expect(proxy.starts, 1);
      expect(session.state.connected, isTrue);
    },
  );

  testWidgets('a bridge returned after timeout is released before retry', (
    tester,
  ) async {
    final client = _Client()..opening = Completer<void>();
    final session = _session(client, _Proxy());
    addTearDown(session.dispose);
    final resumed = session.resumeConnection();
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    await resumed;
    client.opening!.complete();
    await tester.pump();
    expect(client.closeCount, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state.connected, isTrue);
  });

  testWidgets('actual game authentication failure still returns to login', (
    tester,
  ) async {
    final session = _session(_Client(), _Proxy()..rejectPassword = true);
    addTearDown(session.dispose);
    final resumed = session.resumeConnection();
    await tester.pump();
    await resumed;
    expect(session.state.authFailed, isTrue);
    expect(session.state.shouldReturnToLogin, isTrue);
  });
}
