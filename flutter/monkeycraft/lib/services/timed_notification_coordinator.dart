import 'package:monkeycraft_client/services/notification_models.dart';

abstract class TimedNotificationScheduler {
  Future<bool> ensurePermission();
  Future<void> schedule(int fireAtEpochMs, String title, String body, bool sound);
  Future<void> cancel();
}

class TimedNotificationCoordinator {
  final TimedNotificationScheduler scheduler;

  TimedNotificationCoordinator({required this.scheduler});

  Future<void> handle(TimedNotification notification) async {
    final fireAt = notification.fireAtEpochMs;
    if (fireAt == null) {
      await scheduler.cancel();
      return;
    }
    final ok = await scheduler.ensurePermission();
    if (!ok) return;
    await scheduler.schedule(
      fireAt,
      notification.title ?? 'MonkeyCraft',
      notification.body ?? '',
      notification.sound,
    );
  }
}
