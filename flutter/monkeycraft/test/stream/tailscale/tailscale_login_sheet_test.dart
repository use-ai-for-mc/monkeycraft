import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_embedded.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_login_sheet.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';
import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

class _FakeClient implements TailscaleClient {
  _FakeClient({
    this.diagnosticsResult = const TailscaleDiagnostics(
      available: true,
      libtailscaleLinked: true,
      statusJsonAvailable: true,
      reason: 'ok',
    ),
    this.statusResult = const TailscaleEmbeddedSnapshot(phase: 'stopped'),
  });

  final TailscaleDiagnostics diagnosticsResult;
  TailscaleEmbeddedSnapshot statusResult;
  final StreamController<TailscaleEmbeddedSnapshot> controller =
      StreamController<TailscaleEmbeddedSnapshot>.broadcast();
  var startCount = 0;
  var loginCount = 0;
  var cancelCount = 0;
  var logoutCount = 0;

  @override
  bool get isSupported => true;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => controller.stream;

  @override
  Future<TailscaleDiagnostics> diagnostics() async => diagnosticsResult;

  @override
  Future<TailscaleEmbeddedSnapshot> status() async => statusResult;

  @override
  Future<List<TailscalePeer>> listPeers() async => statusResult.peers;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> loginInteractive() async {
    loginCount += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> logout() async {
    logoutCount += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async {
    throw UnsupportedError('not used');
  }

  @override
  Future<void> closeBridge(String leaseId) async {}
}

void main() {
  testWidgets('shows unavailable reason without starting a node', (tester) async {
    final client = _FakeClient(
      diagnosticsResult: const TailscaleDiagnostics(
        available: false,
        libtailscaleLinked: false,
        statusJsonAvailable: false,
        reason: 'libtailscale archive missing',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TailscaleLoginSheet(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('libtailscale archive missing'), findsOneWidget);
    expect(client.startCount, 0);
  });

  testWidgets('running state lists peers and returns the selected node', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'running',
        peers: [
          TailscalePeer(nodeId: 'pc1', hostName: 'desk', online: true),
        ],
      ),
    );
    TailscaleLoginResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await TailscaleLoginSheet.show(context, client: client);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('desk'), findsOneWidget);
    await tester.tap(find.text('desk'));
    await tester.pumpAndSettle();
    expect(result?.nodeId, 'pc1');
    expect(result?.displayName, 'desk');
  });

  testWidgets('needsApproval offers sign out and retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(phase: 'needsApproval'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign out and retry'), findsOneWidget);
    await tester.tap(find.text('Sign out and retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out and delete'));
    await tester.pumpAndSettle();
    expect(client.logoutCount, 1);
    expect(client.loginCount, 1);
  });

  testWidgets('starting phase shows a progress indicator', (tester) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(phase: 'starting'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
