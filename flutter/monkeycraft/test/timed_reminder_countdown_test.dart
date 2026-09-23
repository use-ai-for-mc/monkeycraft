import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/stream/widgets/timed_reminder_countdown.dart';

void main() {
  testWidgets('uses the wall clock and removes an elapsed countdown', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 19);
    await tester.pumpWidget(
      MaterialApp(
        home: TimedReminderCountdown(
          notification: TimedNotification(
            sound: false,
            body: null,
            title: null,
            fireAtEpochMs: now.millisecondsSinceEpoch + 65000,
            countDownText: 'Ride',
          ),
          now: () => now,
        ),
      ),
    );
    expect(find.text('01:05'), findsOneWidget);
    now = now.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('01:01'), findsOneWidget);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ride'), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets('updates the existing reminder and removes it on cancellation', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 19);
    Widget view(TimedNotification? reminder) => MaterialApp(
      home: TimedReminderCountdown(notification: reminder, now: () => now),
    );
    final deadline = now.millisecondsSinceEpoch + 10000;
    await tester.pumpWidget(
      view(
        TimedNotification(
          sound: false,
          body: null,
          title: null,
          fireAtEpochMs: deadline,
          countDownText: 'Live timer A',
        ),
      ),
    );
    now = now.add(const Duration(seconds: 3));
    await tester.pumpWidget(
      view(
        TimedNotification(
          sound: false,
          body: null,
          title: null,
          fireAtEpochMs: deadline,
          countDownText: 'Live timer B',
        ),
      ),
    );
    expect(find.text('Live timer A'), findsNothing);
    expect(find.text('Live timer B'), findsOneWidget);
    expect(find.text('00:07'), findsOneWidget);
    await tester.pumpWidget(view(null));
    expect(find.text('Live timer B'), findsNothing);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    await tester.pumpWidget(
      view(
        TimedNotification(
          sound: false,
          body: null,
          fireAtEpochMs: now.millisecondsSinceEpoch + 2000,
          title: 'Replacement',
        ),
      ),
    );
    expect(find.text('Replacement'), findsOneWidget);
    expect(find.text('00:02'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow enlarged-text layout and exposes the full label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime(2026, 9, 19);
    const label = 'A long attraction name that must remain accessible';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Center(
            child: SizedBox(
              width: 240,
              child: TimedReminderCountdown(
                notification: TimedNotification(
                  sound: false,
                  body: null,
                  title: null,
                  fireAtEpochMs: now.millisecondsSinceEpoch + 3723000,
                  countDownText: label,
                ),
                now: () => now,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('1:02:03'), findsOneWidget);
    expect(find.bySemanticsLabel('$label, 1:02:03 remaining'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
