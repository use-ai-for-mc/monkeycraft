import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';
import 'package:monkeycraft_client/stream/widgets/video_surface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const server = String.fromEnvironment(
    'replayServer',
    defaultValue: 'ws://127.0.0.1:9601',
  );
  const password = String.fromEnvironment(
    'replayPassword',
    defaultValue: 'test',
  );
  const resolution = StreamResolution(360, 640);

  testWidgets('decodes replay frames, releases, and reconnects', (
    tester,
  ) async {
    final proxy = StreamProxy();
    final session = SessionController(
      proxy: proxy,
      settingsStore: StreamSettingsStore(),
    );
    session.initialize();
    final surfaceDecoder = ValueNotifier<HardwareH264Decoder?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 640,
            child: ValueListenableBuilder<HardwareH264Decoder?>(
              valueListenable: surfaceDecoder,
              builder: (_, decoder, _) => VideoSurface(decoder: decoder),
            ),
          ),
        ),
      ),
    );
    StreamSubscription<Uint8List>? frames;
    var connected = false;

    Future<void> release() async {
      surfaceDecoder.value = null;
      await tester.pump();
      await frames?.cancel();
      frames = null;
      if (connected) {
        await proxy.stop();
        connected = false;
      }
      await session.disposeDecoder();
    }

    addTearDown(() async {
      await release();
      await tester.pumpWidget(const SizedBox.shrink());
      surfaceDecoder.dispose();
      session.dispose();
    });

    Future<HardwareH264Decoder> connectAndDecode() async {
      await proxy.start(server, password).timeout(const Duration(seconds: 10));
      connected = true;
      session.reattachToProxy();

      final nextDecoder = HardwareH264Decoder();
      await nextDecoder.initialize(fps: 10);
      surfaceDecoder.value = nextDecoder;
      await tester.pump();
      session.decoder = nextDecoder;
      frames = proxy.accessUnits.listen((data) {
        session.handleAccessUnit(
          data,
          frameWidth: proxy.lastFrameWidth,
          frameHeight: proxy.lastFrameHeight,
        );
      });
      session.setMode(ClientMode.streaming, resolution: resolution);

      final stats = await _waitForDecodedFrames(
        tester,
        nextDecoder,
        atLeast: 5,
      );
      final decodedFrames = stats['decodedFrames'] as int;
      final advancingStats = await _waitForDecodedFrames(
        tester,
        nextDecoder,
        atLeast: decodedFrames + 1,
      );
      expect(nextDecoder.textureId, isNotNull);
      expect(stats['inputAccessUnits'], greaterThan(0));
      expect(stats['decodedFrames'], greaterThanOrEqualTo(5));
      expect(advancingStats['decodedFrames'], greaterThan(decodedFrames));
      expect(stats['width'], 360);
      expect(stats['height'], 640);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(stats['decoding'], isTrue);
      }
      debugPrint('H264 replay stats: $advancingStats');
      return nextDecoder;
    }

    final firstDecoder = await connectAndDecode();
    await release();
    expect(await firstDecoder.getStats(), isEmpty);

    await connectAndDecode();
  });
}

Future<Map<String, dynamic>> _waitForDecodedFrames(
  WidgetTester tester,
  HardwareH264Decoder decoder, {
  required int atLeast,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  Map<String, dynamic> stats = <String, dynamic>{};
  while (DateTime.now().isBefore(deadline)) {
    stats = await decoder.getStats();
    if ((stats['decodedFrames'] as int? ?? 0) >= atLeast) return stats;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  throw TestFailure('native decoder did not produce a frame: $stats');
}
