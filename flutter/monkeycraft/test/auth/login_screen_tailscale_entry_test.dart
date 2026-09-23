import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/login_screen.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_embedded.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_login_sheet.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';
import 'package:monkeycraft_client/stream/transport/connection_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const androidCapabilities = PlatformCapabilities(
    isWeb: false,
    isIOS: false,
    isAndroid: true,
    supportsNativeNotifications: true,
    supportsLiveActivity: true,
    supportsQrScanner: true,
    supportsEmbeddedAudioWebView: true,
    supportsVideoDecoder: true,
    supportsTouchControls: true,
    supportsLocalFiles: true,
  );

  const browserCapabilities = PlatformCapabilities(
    isWeb: true,
    isIOS: false,
    isAndroid: false,
    supportsNativeNotifications: false,
    supportsLiveActivity: false,
    supportsQrScanner: true,
    supportsEmbeddedAudioWebView: false,
    supportsVideoDecoder: true,
    supportsTouchControls: true,
    supportsLocalFiles: false,
  );

  testWidgets('Android exposes and opens the production embedded login sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeTailscaleClient();
    addTearDown(client.controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          platformCapabilitiesOverride: androidCapabilities,
          tailscaleClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect with Tailscale'));
    await tester.pumpAndSettle();

    expect(find.byType(TailscaleLoginSheet), findsOneWidget);
    expect(client.diagnosticsCalls, 1);
    expect(client.startCalls, 1);
  });

  testWidgets('browser does not expose the embedded Tailscale entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeTailscaleClient();
    addTearDown(client.controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          platformCapabilitiesOverride: browserCapabilities,
          tailscaleClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect with Tailscale'), findsNothing);
    expect(client.diagnosticsCalls, 0);
    expect(client.startCalls, 0);
  });
}

class _FakeTailscaleClient implements TailscaleClient {
  final controller = StreamController<TailscaleEmbeddedSnapshot>.broadcast();
  int diagnosticsCalls = 0;
  int startCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<TailscaleEmbeddedSnapshot> get events => controller.stream;

  @override
  TransportFactory? get gameTransportFactory => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> closeBridge(String leaseId) async {}

  @override
  Future<TailscaleDiagnostics> diagnostics() async {
    diagnosticsCalls += 1;
    return const TailscaleDiagnostics(
      available: true,
      libtailscaleLinked: true,
      statusJsonAvailable: true,
      reason: 'available',
    );
  }

  @override
  Future<void> loginInteractive() async {}

  @override
  Future<List<TailscalePeer>> listPeers() async => const [];

  @override
  Future<void> logout() async {}

  @override
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  }) async =>
      const TailscaleBridgeLease(url: 'ws://127.0.0.1:9600', leaseId: 'lease');

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<TailscaleEmbeddedSnapshot> status() async =>
      const TailscaleEmbeddedSnapshot(phase: 'stopped');

  @override
  Future<void> stop() async {}
}
