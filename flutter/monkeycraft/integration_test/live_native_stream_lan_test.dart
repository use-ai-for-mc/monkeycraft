import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

const _configUrl = String.fromEnvironment('liveConfigUrl');
const _resolution = StreamResolution(360, 640);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'authenticates and decodes a live LAN stream (requires dart defines)',
    (tester) async {
      final proxy = StreamProxy();
      final session = SessionController(
        proxy: proxy,
        settingsStore: StreamSettingsStore(),
      );
      final surfaceDecoder = ValueNotifier<HardwareH264Decoder?>(null);
      StreamSubscription<Uint8List>? frames;

      Future<void> detachPipeline() async {
        await frames?.cancel();
        frames = null;
        surfaceDecoder.value = null;
        await tester.pump();
        await session.disposeDecoder();
      }

      Future<Map<String, dynamic>> attachAndDecode() async {
        final next = HardwareH264Decoder();
        await next.initialize(fps: 10);
        surfaceDecoder.value = next;
        session.decoder = next;
        frames = proxy.accessUnits.listen((data) {
          session.handleAccessUnit(
            data,
            frameWidth: proxy.lastFrameWidth,
            frameHeight: proxy.lastFrameHeight,
          );
        });
        session.setMode(ClientMode.streaming, resolution: _resolution);
        await tester.pump();
        return _waitForNativeFrames(tester, next, atLeast: 5);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: ValueListenableBuilder<HardwareH264Decoder?>(
                valueListenable: surfaceDecoder,
                builder: (_, value, _) => VideoSurface(decoder: value),
              ),
            ),
          ),
        ),
      );

      addTearDown(() async {
        await detachPipeline();
        await proxy.stop();
        await tester.pumpWidget(const SizedBox.shrink());
        surfaceDecoder.dispose();
        session.dispose();
      });

      final config = await _loadLiveConfig();
      session.initialize();
      session.setCredentials(config.server, config.password);
      await proxy
          .start(config.server, config.password)
          .timeout(const Duration(seconds: 10));
      session.reattachToProxy();
      session.updateConnectionState(true);
      final first = await attachAndDecode();
      final firstDecoded = first['decodedFrames'] as int;
      final firstDecoder = session.decoder as HardwareH264Decoder;
      final firstAdvanced = await _waitForNativeFrames(
        tester,
        firstDecoder,
        atLeast: firstDecoded + 3,
      );
      expect(proxy.isConnected, isTrue);
      expect(first['inputAccessUnits'], greaterThanOrEqualTo(5));
      expect(first['decodedFrames'], greaterThanOrEqualTo(5));
      expect(first['width'], greaterThan(0));
      expect(first['height'], greaterThan(0));
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(first['decoding'], isTrue);
      }
      debugPrint(
        'Live native stream: input=${firstAdvanced['inputAccessUnits']} '
        'decoded=${firstAdvanced['decodedFrames']} '
        'size=${firstAdvanced['width']}x${firstAdvanced['height']}',
      );

      if (!config.exerciseReconnect) return;

      await detachPipeline();
      expect(await firstDecoder.getStats(), isEmpty);
      debugPrint('Live native stream released: stats=empty');
      await proxy.stop();
      session.handleConnectionLost();
      await _waitForReconnect(session, proxy);
      final afterReconnect = await attachAndDecode();
      final reconnectDecoded = afterReconnect['decodedFrames'] as int;
      final reconnectDecoder = session.decoder as HardwareH264Decoder;
      final reconnectAdvanced = await _waitForNativeFrames(
        tester,
        reconnectDecoder,
        atLeast: reconnectDecoded + 3,
      );
      expect(afterReconnect['decodedFrames'], greaterThanOrEqualTo(5));
      debugPrint(
        'Live native reconnect: input=${reconnectAdvanced['inputAccessUnits']} '
        'decoded=${reconnectAdvanced['decodedFrames']} '
        'size=${reconnectAdvanced['width']}x${reconnectAdvanced['height']}',
      );
    },
    skip: _configUrl.isEmpty,
  );
}

Future<Map<String, dynamic>> _waitForNativeFrames(
  WidgetTester tester,
  HardwareH264Decoder decoder, {
  required int atLeast,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final stats = await decoder.getStats();
    if ((stats['decodedFrames'] as int? ?? 0) >= atLeast) return stats;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  throw TestFailure('native decoder did not produce enough live frames');
}

Future<void> _waitForReconnect(
  SessionController session,
  StreamProxy proxy,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (proxy.isConnected && session.state.connected) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('live reconnect did not restore the session');
}

class _LiveConfig {
  const _LiveConfig({
    required this.server,
    required this.password,
    required this.exerciseReconnect,
  });

  final String server;
  final String password;
  final bool exerciseReconnect;
}

Future<_LiveConfig> _loadLiveConfig() async {
  try {
    final uri = Uri.parse(_configUrl);
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.path.isEmpty) {
      throw const FormatException();
    }
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        uri,
      )).close().timeout(const Duration(seconds: 3));
      if (response.statusCode != HttpStatus.ok) throw const FormatException();
      final body = await utf8.decoder.bind(response).join();
      final value = jsonDecode(body);
      if (value is! Map) throw const FormatException();
      final server = value['server'];
      final password = value['password'];
      final exerciseReconnect = value['exerciseReconnect'];
      if (server is! String ||
          server.isEmpty ||
          password is! String ||
          password.isEmpty) {
        throw const FormatException();
      }
      return _LiveConfig(
        server: server,
        password: password,
        exerciseReconnect: exerciseReconnect == true,
      );
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    throw TestFailure('live configuration is unavailable');
  }
}
