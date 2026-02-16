import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/timed_notification_coordinator.dart';

class _FakeScheduler implements TimedNotificationScheduler {
  bool permission = true;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  int? lastFireAt;
  String? lastTitle;
  String? lastBody;
  bool? lastSound;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<bool> ensurePermission() async {
    return permission;
  }

  @override
  Future<void> schedule(int fireAtEpochMs, String title, String body, bool sound) async {
    scheduleCalls += 1;
    lastFireAt = fireAtEpochMs;
    lastTitle = title;
    lastBody = body;
    lastSound = sound;
  }
}

void main() {
  test('TIMED with null fireAt cancels', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(fireAtEpochMs: null, title: null, body: null, sound: true),
    );
    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('TIMED schedules when permission granted', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: 1730000000000,
        title: 't',
        body: 'b',
        sound: false,
      ),
    );
    expect(scheduler.cancelCalls, 0);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.lastFireAt, 1730000000000);
    expect(scheduler.lastTitle, 't');
    expect(scheduler.lastBody, 'b');
    expect(scheduler.lastSound, false);
  });

  test('TIMED does nothing when permission denied', () async {
    final scheduler = _FakeScheduler()..permission = false;
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: 1730000000000,
        title: 't',
        body: 'b',
        sound: true,
      ),
    );
    expect(scheduler.cancelCalls, 0);
    expect(scheduler.scheduleCalls, 0);
  });
}
