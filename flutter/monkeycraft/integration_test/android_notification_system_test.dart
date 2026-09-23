import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel('monkeycraft/notifications');

  testWidgets('holds notification state for Android system inspection', (_) async {
    final granted = await notifications.invokeMethod<bool>('requestPermission');
    expect(granted, isTrue);

    final fireAt = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;

    await notifications.invokeMethod<void>('showImmediate', {
      'title': 'fixture-silent',
      'body': 'sound false',
      'sound': false,
    });
    await notifications.invokeMethod<void>('showImmediate', {
      'title': 'fixture-audible',
      'body': 'sound true',
      'sound': true,
    });
    await notifications.invokeMethod<void>('startCountdown', {
      'fireAtEpochMs': fireAt,
      'countDownText': 'fixture-countdown-first',
    });
    await notifications.invokeMethod<void>('updateCountdown', {
      'fireAtEpochMs': fireAt - 1000,
      'countDownText': 'fixture-countdown-updated',
    });
    await notifications.invokeMethod<void>('scheduleTimed', {
      'id': 9131,
      'fireAtEpochMs': fireAt,
      'title': 'fixture-scheduled-first',
      'body': 'first',
      'sound': false,
    });
    await notifications.invokeMethod<void>('scheduleTimed', {
      'id': 9131,
      'fireAtEpochMs': fireAt - 1000,
      'title': 'fixture-scheduled-updated',
      'body': 'updated',
      'sound': true,
    });

    await Future<void>.delayed(const Duration(seconds: 25));

    await notifications.invokeMethod<void>('cancelCountdown');
    await notifications.invokeMethod<void>('cancelTimed', {'id': 9131});

    await Future<void>.delayed(const Duration(seconds: 20));
  });
}
