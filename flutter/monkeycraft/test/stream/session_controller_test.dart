import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';

class _FakeDecoder implements MonkeycraftVideoDecoder {
  final pushed = <Uint8List>[];
  var resetCount = 0;

  @override
  int? get textureId => 1;

  @override
  String? get platformViewType => null;

  @override
  bool get isReady => true;

  @override
  String? get lastError => null;

  @override
  VideoDecoderStats get stats => const VideoDecoderStats();

  @override
  VoidCallback? onKeyframeNeeded;

  @override
  VoidCallback? onChanged;

  @override
  Future<void> initialize({int fps = 20}) async {}

  @override
  void pushAccessUnit(Uint8List bytes) => pushed.add(bytes);

  @override
  Future<void> reset() async {
    resetCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionController after dispose', () {
    test('state updates are ignored instead of throwing', () {
      final controller = SessionController(
        proxy: StreamProxy(),
        settingsStore: StreamSettingsStore(),
      );
      controller.dispose();

      // Late async callbacks (in-flight reconnects, listener tails) update
      // state after the screen is gone; they must be no-ops, not
      // use-after-dispose errors on the ChangeNotifier or a closed stream.
      controller.updateConnectionState(true);
      controller.setForeground(false);
      controller.handleConnectionLost();

      expect(controller.state.isReconnecting, isFalse);
    });

    test('reconnect attempts stop once disposed', () async {
      final controller = SessionController(
        proxy: StreamProxy(),
        settingsStore: StreamSettingsStore(),
      );
      controller.setCredentials('127.0.0.1:1', 'pw');
      controller.handleConnectionLost();
      controller.dispose();

      // The first retry fires after 1s; give it time to have fired if the
      // timer survived dispose. resumeConnection must also bail out.
      await controller.resumeConnection();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(controller.state.connected, isFalse);
    });
  });

  test('drops frames until the expected resolution is confirmed', () {
    final decoder = _FakeDecoder();
    final controller = SessionController(
      proxy: StreamProxy(),
      settingsStore: StreamSettingsStore(),
    );
    controller.decoder = decoder;
    controller.updateConnectionState(true);
    controller.setMode(
      ClientMode.streaming,
      resolution: const StreamResolution(640, 360),
    );

    controller.handleAccessUnit(Uint8List.fromList([1]), frameWidth: 320, frameHeight: 180);
    expect(decoder.pushed, isEmpty);

    controller.handleAccessUnit(Uint8List.fromList([2]));
    expect(decoder.pushed, isEmpty);

    controller.dispose();
  });
}
