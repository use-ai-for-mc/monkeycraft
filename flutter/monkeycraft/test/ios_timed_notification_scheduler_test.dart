import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/ios_timed_notification_scheduler.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';

void main() {
  test(
    'shares an in-flight permission request and retries after denial',
    () async {
      final first = Completer<bool>();
      var calls = 0;
      final scheduler = IosTimedNotificationScheduler(
        TimedNotificationService(),
        supportsNativeNotifications: true,
        requestPermission: () {
          calls += 1;
          return calls == 1 ? first.future : Future.value(true);
        },
      );

      final firstWaiter = scheduler.ensurePermission();
      final secondWaiter = scheduler.ensurePermission();
      expect(calls, 1);

      first.complete(false);
      expect(await firstWaiter, isFalse);
      expect(await secondWaiter, isFalse);

      expect(await scheduler.ensurePermission(), isTrue);
      expect(calls, 2);
    },
  );

  test(
    'does not request permission when native notifications are unavailable',
    () async {
      var calls = 0;
      final scheduler = IosTimedNotificationScheduler(
        TimedNotificationService(),
        supportsNativeNotifications: false,
        requestPermission: () async {
          calls += 1;
          return true;
        },
      );

      expect(await scheduler.ensurePermission(), isFalse);
      expect(calls, 0);
    },
  );

  test('shows an immediate notification only after authorization', () async {
    final first = Completer<bool>();
    var permissionCalls = 0;
    final shown = <Map<String, dynamic>>[];
    final scheduler = IosTimedNotificationScheduler(
      TimedNotificationService(),
      supportsNativeNotifications: true,
      requestPermission: () {
        permissionCalls += 1;
        return permissionCalls == 1 ? first.future : Future.value(true);
      },
      showImmediate: ({required title, required body, required sound}) async {
        shown.add({'title': title, 'body': body, 'sound': sound});
      },
    );

    final denied = scheduler.showImmediate('first', 'body', false);
    expect(permissionCalls, 1);
    expect(shown, isEmpty);
    first.complete(false);
    expect(await denied, isFalse);
    expect(shown, isEmpty);

    expect(await scheduler.showImmediate('second', 'body', false), isTrue);
    expect(permissionCalls, 2);
    expect(shown, [
      {'title': 'second', 'body': 'body', 'sound': false},
    ]);
  });
  test(
    'deduplicates concurrent alerts after permission and expires the window',
    () async {
      var now = 10000;
      final permission = Completer<bool>();
      final shown = <(String, String, bool)>[];
      final scheduler = IosTimedNotificationScheduler(
        TimedNotificationService(),
        supportsNativeNotifications: true,
        nowMilliseconds: () => now,
        requestPermission: () => permission.future,
        showImmediate: ({required title, required body, required sound}) async {
          shown.add((title, body, sound));
        },
      );
      final first = scheduler.showImmediate('ride', 'ready', true);
      final duplicate = scheduler.showImmediate('ride', 'ready', true);
      permission.complete(true);
      expect(await first, isTrue);
      expect(await duplicate, isFalse);
      expect(shown.length, 1);
      expect(await scheduler.showImmediate('ride', 'ready', false), isTrue);
      expect(await scheduler.showImmediate('ride', 'different', true), isTrue);
      now += 999;
      expect(await scheduler.showImmediate('ride', 'ready', true), isFalse);
      now += 1;
      expect(await scheduler.showImmediate('ride', 'ready', true), isTrue);
      expect(shown.length, 4);
    },
  );

  test(
    'failed delivery is retryable without waiting for the duplicate window',
    () async {
      var calls = 0;
      final scheduler = IosTimedNotificationScheduler(
        TimedNotificationService(),
        supportsNativeNotifications: true,
        nowMilliseconds: () => 10000,
        requestPermission: () async => true,
        showImmediate: ({required title, required body, required sound}) async {
          if (++calls == 1) throw StateError('native delivery failed');
        },
      );
      await expectLater(
        scheduler.showImmediate('ride', 'ready', true),
        throwsStateError,
      );
      expect(await scheduler.showImmediate('ride', 'ready', true), isTrue);
      expect(calls, 2);
    },
  );
}
