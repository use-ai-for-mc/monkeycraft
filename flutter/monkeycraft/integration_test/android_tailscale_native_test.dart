import 'dart:async';

import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('monkeycraft/tailscale');
  const eventChannel = EventChannel('monkeycraft/tailscale_events');
  const notifications = MethodChannel('monkeycraft/notifications');

  testWidgets(
    'native notification channel accepts both sound modes and countdown updates',
    (_) async {
      final fireAt = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;

      await notifications.invokeMethod<void>('scheduleTimed', {
        'id': 9101,
        'fireAtEpochMs': fireAt,
        'title': 'fixture',
        'body': 'silent',
        'sound': false,
      });
      await notifications.invokeMethod<void>('scheduleTimed', {
        'id': 9102,
        'fireAtEpochMs': fireAt,
        'title': 'fixture',
        'body': 'audible',
        'sound': true,
      });
      await notifications.invokeMethod<void>('startCountdown', {
        'fireAtEpochMs': fireAt,
        'countDownText': 'five minutes',
      });
      await notifications.invokeMethod<void>('updateCountdown', {
        'fireAtEpochMs': fireAt - 1000,
        'countDownText': 'updated',
      });
      await notifications.invokeMethod<void>('cancelCountdown');
      await notifications.invokeMethod<void>('cancelTimed', {'id': 9101});
      await notifications.invokeMethod<void>('cancelTimed', {'id': 9102});
    },
  );

  testWidgets('starts and stops embedded Tailscale without login', (_) async {
    final events = <Map<dynamic, dynamic>>[];
    final stoppedEvent = Completer<void>();
    final failedAfterStop = Completer<void>();
    var waitingForStop = false;
    final subscription = eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      events.add(event);
      if (!waitingForStop) return;
      switch (event['phase']) {
        case 'stopped':
          if (!stoppedEvent.isCompleted) stoppedEvent.complete();
        case 'failed':
          if (!failedAfterStop.isCompleted) {
            failedAfterStop.completeError(
              TestFailure('received failed event after stop: $event'),
            );
          }
      }
    });
    addTearDown(subscription.cancel);

    final diagnostics = await channel
        .invokeMapMethod<String, dynamic>('diagnostics')
        .timeout(const Duration(seconds: 10));
    expect(diagnostics?['available'], isTrue);
    expect(diagnostics?['libtailscaleLinked'], isTrue);
    expect(diagnostics?['statusJsonAvailable'], isTrue);

    await channel
        .invokeMethod<void>('start')
        .timeout(const Duration(seconds: 20));
    Map<dynamic, dynamic>? status;
    for (var i = 0; i < 20; i++) {
      status = await channel
          .invokeMapMethod<dynamic, dynamic>('status')
          .timeout(const Duration(seconds: 5));
      final phase = status?['phase'];
      if (phase == 'needsLogin' || phase == 'running') break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(status?['phase'], anyOf('needsLogin', 'running'));

    final eventCount = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(events.length, greaterThan(eventCount));
    expect(events.last['phase'], anyOf('needsLogin', 'running'));

    waitingForStop = true;
    final eventsBeforeStop = events.length;
    await channel
        .invokeMethod<void>('stop')
        .timeout(const Duration(seconds: 10));
    await Future.any<void>([
      stoppedEvent.future,
      failedAfterStop.future,
    ]).timeout(const Duration(seconds: 5));
    await channel
        .invokeMethod<void>('stop')
        .timeout(const Duration(seconds: 10));
    expect(
      events.skip(eventsBeforeStop).map((event) => event['phase']),
      isNot(contains('failed')),
    );
    final stopped = await channel.invokeMapMethod<dynamic, dynamic>('status');
    expect(stopped?['phase'], 'stopped');

    await channel
        .invokeMethod<void>('start')
        .timeout(const Duration(seconds: 20));
    final restarted = await channel.invokeMapMethod<dynamic, dynamic>('status');
    expect(restarted?['phase'], isNot('stopped'));
    await channel.invokeMethod<void>('cancel');
  });
}
