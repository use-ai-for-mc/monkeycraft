import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';

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
}
