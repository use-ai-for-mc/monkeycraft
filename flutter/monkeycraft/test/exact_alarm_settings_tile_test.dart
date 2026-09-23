import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/exact_alarm_settings_tile.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';

void main() {
  const channel = MethodChannel('monkeycraft/notifications');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget tile({Future<void> Function()? onGranted, bool isAndroid = true}) {
    return MaterialApp(
      home: Scaffold(
        body: ExactAlarmSettingsTile(
          isAndroid: isAndroid,
          service: TimedNotificationService(isAndroid: true),
          onGranted: onGranted,
        ),
      ),
    );
  }

  testWidgets('shows the delay explanation and opens settings only on tap', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'getExactAlarmAccess') {
            return {'supported': true, 'granted': false};
          }
          if (call.method == 'openExactAlarmSettings') return true;
          return null;
        });

    await tester.pumpWidget(tile());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ride reminders can be delayed unless exact alarms are allowed.',
      ),
      findsOneWidget,
    );
    expect(calls, ['getExactAlarmAccess']);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(calls, ['getExactAlarmAccess', 'openExactAlarmSettings']);
  });

  testWidgets('refreshes after settings and restores a reminder once', (
    tester,
  ) async {
    var granted = false;
    var restores = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getExactAlarmAccess') {
            return {'supported': true, 'granted': granted};
          }
          return null;
        });

    await tester.pumpWidget(
      tile(
        onGranted: () async {
          restores += 1;
        },
      ),
    );
    await tester.pumpAndSettle();
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(restores, 1);
    expect(find.text('Exact ride reminders are enabled.'), findsOneWidget);
  });

  testWidgets('retries restoration after a callback failure', (tester) async {
    var granted = false;
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getExactAlarmAccess') {
            return {'supported': true, 'granted': granted};
          }
          return null;
        });

    await tester.pumpWidget(
      tile(
        onGranted: () async {
          attempts += 1;
          if (attempts == 1) throw StateError('retry');
        },
      ),
    );
    await tester.pumpAndSettle();
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Unable to restore this reminder.'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Exact ride reminders are enabled.'), findsOneWidget);
  });

  testWidgets('shows a safe error when the access query fails', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'failed');
        });

    await tester.pumpWidget(tile());
    await tester.pumpAndSettle();

    expect(find.text('Unable to check exact alarm access.'), findsOneWidget);
  });

  testWidgets('ignores an older access query after a resumed refresh', (
    tester,
  ) async {
    final first = Completer<Map<String, bool>>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'getExactAlarmAccess') return null;
          calls += 1;
          if (calls == 1) return first.future;
          return {'supported': true, 'granted': false};
        });

    await tester.pumpWidget(tile());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    first.complete({'supported': true, 'granted': true});
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ride reminders can be delayed unless exact alarms are allowed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not render or query on non-Android platforms', (
    tester,
  ) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls += 1;
          return null;
        });

    await tester.pumpWidget(tile(isAndroid: false));
    await tester.pumpAndSettle();

    expect(find.text('Exact Ride Reminders'), findsNothing);
    expect(calls, 0);
  });
}
