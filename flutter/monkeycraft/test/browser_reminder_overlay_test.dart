import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/browser_notification_event.dart';
import 'package:monkeycraft_client/shared/browser_reminder_overlay.dart';

void main() {
  testWidgets('keeps a timed reminder visible when an immediate arrives', (
    tester,
  ) async {
    final events = StreamController<BrowserNotificationEvent>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(_view(events.stream));

    events
      ..add(_timed('Timed'))
      ..add(_immediate('Immediate'));
    await tester.pump();

    expect(find.text('Timed'), findsOneWidget);
    expect(find.text('Immediate'), findsNothing);

    await tester.pump(const Duration(seconds: 12));
    expect(find.text('Immediate'), findsOneWidget);
  });

  testWidgets('keeps only the latest pending immediate reminder', (
    tester,
  ) async {
    final events = StreamController<BrowserNotificationEvent>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(_view(events.stream));

    events.add(_timed('Timed'));
    await tester.pump();
    events
      ..add(_immediate('Old'))
      ..add(_immediate('Latest'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));

    expect(find.text('Old'), findsNothing);
    expect(find.text('Latest'), findsOneWidget);
  });

  testWidgets('drops an expired pending immediate reminder', (tester) async {
    final events = StreamController<BrowserNotificationEvent>.broadcast();
    addTearDown(events.close);
    var now = DateTime(2026, 9, 19);
    await tester.pumpWidget(_view(events.stream, now: () => now));

    events.add(_timed('Timed'));
    await tester.pump();
    events.add(_immediate('Expired'));
    await tester.pump();
    now = now.add(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 12));

    expect(find.text('Expired'), findsNothing);
    expect(find.byTooltip('Dismiss reminder'), findsNothing);
  });

  testWidgets('dismisses a timed reminder into its fresh pending immediate', (
    tester,
  ) async {
    final events = StreamController<BrowserNotificationEvent>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(_view(events.stream));

    events
      ..add(_timed('Timed'))
      ..add(_immediate('Pending'));
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss reminder'));
    await tester.pump();

    expect(find.text('Timed'), findsNothing);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('cancels its subscription and timer on dispose', (tester) async {
    final events = StreamController<BrowserNotificationEvent>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(_view(events.stream));
    events.add(_timed('Timed'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    events.add(_immediate('After dispose'));
    await tester.pump(const Duration(seconds: 12));

    expect(find.text('After dispose'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _view(
  Stream<BrowserNotificationEvent> events, {
  DateTime Function()? now,
}) => MaterialApp(
  home: BrowserReminderOverlay(
    eventStream: events,
    now: now,
    child: const Scaffold(body: SizedBox.expand()),
  ),
);

BrowserNotificationEvent _timed(String title) => BrowserNotificationEvent(
  kind: BrowserNotificationKind.timed,
  title: title,
  body: '',
  sound: false,
  systemNotification: false,
);

BrowserNotificationEvent _immediate(String title) => BrowserNotificationEvent(
  kind: BrowserNotificationKind.immediate,
  title: title,
  body: '',
  sound: false,
  systemNotification: false,
);
