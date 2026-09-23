import 'package:monkeycraft_client/notifications/notification_models.dart';

abstract class TimedNotificationScheduler {
  Future<bool> ensurePermission();
  Future<void> schedule(
    int fireAtEpochMs,
    String title,
    String body,
    bool sound,
  );
  Future<void> cancel();
}

class TimedNotificationCoordinator {
  final TimedNotificationScheduler scheduler;
  final int Function() _nowEpochMs;
  String? _scheduledSignature;
  int? _scheduledFireAtEpochMs;
  bool _cancelled = false;
  bool _closed = false;
  Future<void> _operations = Future<void>.value();

  TimedNotificationCoordinator({
    required this.scheduler,
    int Function()? nowEpochMs,
  }) : _nowEpochMs =
           nowEpochMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<void> handle(TimedNotification notification) {
    if (_closed) return Future<void>.value();
    final operation = _operations.then((_) => _handle(notification));
    _operations = operation.catchError((_) {});
    return operation;
  }

  Future<void> rescheduleIfFuture(TimedNotification notification) {
    if (_closed) return Future<void>.value();
    final operation = _operations.then((_) async {
      final fireAt = notification.fireAtEpochMs;
      if (fireAt == null || fireAt <= _nowEpochMs()) {
        return;
      }
      _scheduledSignature = null;
      await _handle(notification);
    });
    _operations = operation.catchError((_) {});
    return operation;
  }

  Future<void> _handle(TimedNotification notification) async {
    if (_closed) return;
    final fireAt = notification.fireAtEpochMs;
    if (fireAt == null) {
      if (!_cancelled) {
        await scheduler.cancel();
        _cancelled = true;
      }
      _scheduledSignature = null;
      _scheduledFireAtEpochMs = null;
      return;
    }

    final signature =
        '$fireAt\u0000${notification.title}\u0000${notification.body}\u0000${notification.sound}';
    if (fireAt <= _nowEpochMs()) {
      await _recordExpired(signature);
      return;
    }
    if (_scheduledSignature == signature) return;

    final ok = await scheduler.ensurePermission();
    if (!ok || _closed) return;
    if (fireAt <= _nowEpochMs()) {
      await _recordExpired(signature);
      return;
    }
    await scheduler.schedule(
      fireAt,
      notification.title ?? 'MonkeyCraft',
      notification.body ?? '',
      notification.sound,
    );
    _scheduledSignature = signature;
    _scheduledFireAtEpochMs = fireAt;
    _cancelled = false;
  }

  Future<void> _recordExpired(String signature) async {
    var cancelledScheduledNotification = false;
    final scheduledFireAt = _scheduledFireAtEpochMs;
    if (scheduledFireAt != null &&
        scheduledFireAt > _nowEpochMs() &&
        !_cancelled) {
      await scheduler.cancel();
      cancelledScheduledNotification = true;
    }
    _scheduledSignature = signature;
    _scheduledFireAtEpochMs = null;
    if (cancelledScheduledNotification) {
      _cancelled = true;
    }
  }

  Future<void> cancelAndClose() {
    _closed = true;
    final operation = _operations.then((_) => scheduler.cancel());
    _operations = operation.catchError((_) {});
    return operation;
  }
}
