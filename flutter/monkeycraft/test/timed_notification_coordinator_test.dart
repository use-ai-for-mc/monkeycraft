import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/notifications/timed_notification_coordinator.dart';

const _futureEpochMs = 4102444800000;

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
  Future<void> schedule(
    int fireAtEpochMs,
    String title,
    String body,
    bool sound,
  ) async {
    scheduleCalls += 1;
    lastFireAt = fireAtEpochMs;
    lastTitle = title;
    lastBody = body;
    lastSound = sound;
  }
}

class _GatedPermissionScheduler extends _FakeScheduler {
  final permissionStarted = Completer<void>();
  final releasePermission = Completer<bool>();

  @override
  Future<bool> ensurePermission() {
    permissionStarted.complete();
    return releasePermission.future;
  }
}

class _GatedScheduler extends _FakeScheduler {
  final scheduleStarted = Completer<void>();
  final releaseSchedule = Completer<void>();
  final operations = <String>[];

  @override
  Future<void> cancel() async {
    operations.add('cancel');
    await super.cancel();
  }

  @override
  Future<void> schedule(
    int fireAtEpochMs,
    String title,
    String body,
    bool sound,
  ) async {
    operations.add('schedule:$sound');
    scheduleStarted.complete();
    await releaseSchedule.future;
    await super.schedule(fireAtEpochMs, title, body, sound);
  }
}

void main() {
  test(
    'closing a browser session cancels and rejects pending permission work',
    () async {
      final scheduler = _GatedPermissionScheduler();
      final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
      const notification = TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 'Future reminder',
        body: '',
        sound: true,
      );
      final pending = coordinator.handle(notification);
      await scheduler.permissionStarted.future;
      final closed = coordinator.cancelAndClose();
      scheduler.releasePermission.complete(true);
      await pending;
      await closed;
      await coordinator.handle(notification);
      expect(scheduler.scheduleCalls, 0);
      expect(scheduler.cancelCalls, 1);
    },
  );

  test('TIMED with null fireAt cancels', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: null,
        title: null,
        body: null,
        sound: true,
      ),
    );
    expect(scheduler.cancelCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('TIMED schedules when permission granted', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 't',
        body: 'b',
        sound: false,
      ),
    );
    expect(scheduler.cancelCalls, 0);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.lastFireAt, _futureEpochMs);
    expect(scheduler.lastTitle, 't');
    expect(scheduler.lastBody, 'b');
    expect(scheduler.lastSound, false);
  });

  test('TIMED does nothing when permission denied', () async {
    final scheduler = _FakeScheduler()..permission = false;
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 't',
        body: 'b',
        sound: true,
      ),
    );
    expect(scheduler.cancelCalls, 0);
    expect(scheduler.scheduleCalls, 0);
  });

  test('repeated TIMED state is scheduled only once', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    const notification = TimedNotification(
      fireAtEpochMs: _futureEpochMs,
      title: 't',
      body: 'b',
      sound: true,
    );

    await coordinator.handle(notification);
    await coordinator.handle(notification);

    expect(scheduler.scheduleCalls, 1);
  });

  test('exact alarm grant reschedules only a future reminder', () async {
    const now = 2000;
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(
      scheduler: scheduler,
      nowEpochMs: () => now,
    );
    const future = TimedNotification(
      fireAtEpochMs: 3000,
      title: 't',
      body: 'b',
      sound: true,
    );

    await coordinator.handle(future);
    await coordinator.rescheduleIfFuture(future);
    await coordinator.rescheduleIfFuture(
      const TimedNotification(
        fireAtEpochMs: 1000,
        title: 'old',
        body: 'old',
        sound: true,
      ),
    );

    expect(scheduler.scheduleCalls, 2);
  });

  test('changed TIMED state replaces the scheduled notification', () async {
    final scheduler = _FakeScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);

    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 't',
        body: 'old',
        sound: true,
      ),
    );
    await coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: _futureEpochMs + 1000,
        title: 't',
        body: 'new',
        sound: false,
      ),
    );

    expect(scheduler.scheduleCalls, 2);
    expect(scheduler.lastFireAt, _futureEpochMs + 1000);
    expect(scheduler.lastBody, 'new');
    expect(scheduler.lastSound, isFalse);
  });

  test(
    'cancel clears the duplicate key so a later timer can be scheduled',
    () async {
      final scheduler = _FakeScheduler();
      final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
      const notification = TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 't',
        body: 'b',
        sound: true,
      );

      await coordinator.handle(notification);
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: null,
          title: null,
          body: null,
          sound: true,
        ),
      );
      await coordinator.handle(notification);

      expect(scheduler.cancelCalls, 1);
      expect(scheduler.scheduleCalls, 2);
    },
  );

  test('queues a disconnect cancellation behind an in-flight update', () async {
    final scheduler = _GatedScheduler();
    final coordinator = TimedNotificationCoordinator(scheduler: scheduler);
    final updating = coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: _futureEpochMs,
        title: 't',
        body: 'b',
        sound: false,
      ),
    );
    await scheduler.scheduleStarted.future;
    final cancelling = coordinator.handle(
      const TimedNotification(
        fireAtEpochMs: null,
        title: null,
        body: null,
        sound: true,
      ),
    );

    expect(scheduler.operations, ['schedule:false']);
    scheduler.releaseSchedule.complete();
    await Future.wait([updating, cancelling]);

    expect(scheduler.operations, ['schedule:false', 'cancel']);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.cancelCalls, 1);
  });

  test(
    'a fresh coordinator ignores an expired timer without clearing its alert',
    () async {
      var now = 2000;
      final scheduler = _FakeScheduler();
      final coordinator = TimedNotificationCoordinator(
        scheduler: scheduler,
        nowEpochMs: () => now,
      );
      const expired = TimedNotification(
        fireAtEpochMs: 1000,
        title: 't',
        body: 'b',
        sound: true,
      );

      await coordinator.handle(expired);
      await coordinator.handle(expired);
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 1500,
          title: 'changed',
          body: 'changed',
          sound: false,
        ),
      );

      expect(scheduler.scheduleCalls, 0);
      expect(scheduler.cancelCalls, 0);

      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: null,
          title: null,
          body: null,
          sound: true,
        ),
      );

      expect(scheduler.scheduleCalls, 0);
      expect(scheduler.cancelCalls, 1);
    },
  );

  test(
    'different expired state does not cancel a timer that already reached its deadline',
    () async {
      var now = 1000;
      final scheduler = _FakeScheduler();
      final coordinator = TimedNotificationCoordinator(
        scheduler: scheduler,
        nowEpochMs: () => now,
      );

      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 2000,
          title: 'a',
          body: 'a',
          sound: true,
        ),
      );
      now = 2500;
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 1500,
          title: 'b',
          body: 'b',
          sound: false,
        ),
      );

      expect(scheduler.scheduleCalls, 1);
      expect(scheduler.cancelCalls, 0);

      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: null,
          title: null,
          body: null,
          sound: true,
        ),
      );

      expect(scheduler.cancelCalls, 1);
    },
  );

  test(
    'does not schedule when the deadline passes while asking permission',
    () async {
      var now = 1000;
      final scheduler = _GatedPermissionScheduler();
      final coordinator = TimedNotificationCoordinator(
        scheduler: scheduler,
        nowEpochMs: () => now,
      );
      final handling = coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 2000,
          title: 't',
          body: 'b',
          sound: true,
        ),
      );
      await scheduler.permissionStarted.future;

      now = 2000;
      scheduler.releasePermission.complete(true);
      await handling;

      expect(scheduler.scheduleCalls, 0);
      expect(scheduler.cancelCalls, 0);
    },
  );

  test(
    'an expired update replaces a future timer without breaking cancellation',
    () async {
      var now = 1000;
      final scheduler = _FakeScheduler();
      final coordinator = TimedNotificationCoordinator(
        scheduler: scheduler,
        nowEpochMs: () => now,
      );

      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 3000,
          title: 'a',
          body: 'a',
          sound: true,
        ),
      );
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 500,
          title: 'b',
          body: 'b',
          sound: false,
        ),
      );
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: 4000,
          title: 'c',
          body: 'c',
          sound: true,
        ),
      );
      await coordinator.handle(
        const TimedNotification(
          fireAtEpochMs: null,
          title: null,
          body: null,
          sound: true,
        ),
      );

      expect(scheduler.scheduleCalls, 2);
      expect(scheduler.cancelCalls, 2);
      expect(scheduler.lastFireAt, 4000);
    },
  );
}
