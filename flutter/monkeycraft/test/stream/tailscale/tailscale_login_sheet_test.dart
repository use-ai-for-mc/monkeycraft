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
  var statusCount = 0;
  Completer<void>? startCompleter;
  Completer<void>? loginCompleter;

  @override
  bool get isSupported => true;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => controller.stream;

  @override
  Future<TailscaleDiagnostics> diagnostics() async => diagnosticsResult;

  @override
  Future<TailscaleEmbeddedSnapshot> status() async {
    statusCount += 1;
    return statusResult;
  }

  @override
  Future<List<TailscalePeer>> listPeers() async => statusResult.peers;

  @override
  Future<void> start() async {
    startCount += 1;
    await startCompleter?.future;
  }

  @override
  Future<void> loginInteractive() async {
    loginCount += 1;
    await loginCompleter?.future;
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
  testWidgets('shows unavailable reason without starting a node', (
    tester,
  ) async {
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
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('libtailscale archive missing'), findsOneWidget);
    expect(client.startCount, 0);
  });

  testWidgets('same-name peers show addresses and return the selected node', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'running',
        peers: [
          TailscalePeer(
            nodeId: 'pc1',
            hostName: 'desk',
            online: true,
            tailscaleIPs: ['100.64.1.2'],
          ),
          TailscalePeer(
            nodeId: 'pc2',
            hostName: 'desk',
            online: true,
            tailscaleIPs: ['fd7a:115c:a1e0::3', '100.64.1.3'],
          ),
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
    expect(find.text('desk'), findsNWidgets(2));
    expect(find.text('Online · 100.64.1.2'), findsOneWidget);
    expect(
      find.text('Online · 100.64.1.3 · fd7a:115c:a1e0::3'),
      findsOneWidget,
    );
    await tester.tap(
      find.ancestor(
        of: find.text('Online · 100.64.1.3 · fd7a:115c:a1e0::3'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();
    expect(result?.nodeId, 'pc2');
    expect(result?.displayName, 'desk');
    expect(client.cancelCount, 0);
  });

  testWidgets(
    'dismissing while start is in flight cancels once and ignores late status',
    (tester) async {
      final client = _FakeClient();
      client.startCompleter = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  TailscaleLoginSheet.show(context, client: client),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(client.startCount, 1);
      expect(find.byType(TailscaleLoginSheet), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(client.cancelCount, 1);
      expect(find.byType(TailscaleLoginSheet), findsNothing);

      client.controller.add(
        const TailscaleEmbeddedSnapshot(
          phase: 'needsLogin',
          authUrlHost: 'login.tailscale.com',
        ),
      );
      client.startCompleter!.complete();
      await tester.pump();
      expect(client.statusCount, 0);
      expect(client.cancelCount, 1);
    },
  );

  testWidgets('Cancel button requests one cancellation before closing', (
    tester,
  ) async {
    final client = _FakeClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => TailscaleLoginSheet.show(context, client: client),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.cancelCount, 1);
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

  testWidgets('bootstrap starts without repeating an existing login request', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'needsLogin',
        authUrlHost: 'login.tailscale.com',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.startCount, 1);
    expect(client.loginCount, 0);
    expect(find.text('Open Tailscale login again'), findsOneWidget);
  });

  testWidgets('needsLogin waits without claiming that a page opened', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(phase: 'needsLogin'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Preparing Tailscale sign-in'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Open Tailscale login'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 35));
    expect(client.startCount, 1);
    expect(client.loginCount, 0);
    client.controller.add(
      const TailscaleEmbeddedSnapshot(
        phase: 'needsLogin',
        authUrlHost: 'login.tailscale.com',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open Tailscale login again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(client.loginCount, 0);
  });

  testWidgets('needsLogin with an auth host offers a safe reopen action', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'needsLogin',
        authUrlHost: 'login.tailscale.com',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Finish signing in with Tailscale'),
      findsOneWidget,
    );
    expect(find.textContaining('login.tailscale.com'), findsNothing);
    await tester.tap(find.text('Open Tailscale login again'));
    await tester.pumpAndSettle();
    expect(client.startCount, 2);
    expect(client.loginCount, 1);
  });

  testWidgets('auth URL presentation failure stays retryable in needsLogin', (
    tester,
  ) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'needsLogin',
        errorCode: 'auth_url_open_failed',
        errorMessage:
            'Could not open the Tailscale sign-in page. Tap to try again.',
        authUrlHost: 'login.tailscale.com',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open the Tailscale sign-in page. Tap to try again.'),
      findsOneWidget,
    );
    expect(find.text('Open Tailscale login again'), findsOneWidget);

    await tester.tap(find.text('Open Tailscale login again'));
    await tester.pumpAndSettle();
    expect(client.startCount, 2);
    expect(client.loginCount, 1);
  });

  testWidgets('rapid reopen taps issue only one login request', (tester) async {
    final client = _FakeClient(
      statusResult: const TailscaleEmbeddedSnapshot(
        phase: 'needsLogin',
        authUrlHost: 'login.tailscale.com',
      ),
    );
    client.loginCompleter = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TailscaleLoginSheet(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Tailscale login again'));
    await tester.tap(find.text('Open Tailscale login again'));
    await tester.pump();
    expect(client.startCount, 2);
    expect(client.loginCount, 1);
    client.loginCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
