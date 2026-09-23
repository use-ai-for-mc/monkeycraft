import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('monkeycraft/audio_background');

  testWidgets(
    'starts and stops the native audio background service idempotently',
    (tester) async {
      addTearDown(() => channel.invokeMethod<void>('stop'));

      await channel.invokeMethod<void>('start');
      await channel.invokeMethod<void>('start');
      debugPrint('AUDIO_BACKGROUND_STARTED');
      await Future<void>.delayed(const Duration(seconds: 20));

      await channel.invokeMethod<void>('stop');
      await channel.invokeMethod<void>('stop');
      debugPrint('AUDIO_BACKGROUND_STOPPED');
      await Future<void>.delayed(const Duration(seconds: 20));
    },
  );
}
