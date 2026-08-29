import 'package:monkeycraft_client/notifications/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

class IosTimedNotificationScheduler implements TimedNotificationScheduler {
  final TimedNotificationService _service;
  bool? _granted;

  IosTimedNotificationScheduler(this._service);

  @override
  Future<bool> ensurePermission() async {
    // Despite the class name, this also drives Android notifications via the
    // same `monkeycraft/notifications` channel.
    if (!platformCapabilities.supportsNativeNotifications) return false;
    final granted = _granted;
    if (granted != null) return granted;
    final next = await _service.requestPermission();
    _granted = next;
    return next;
  }

  @override
  Future<void> schedule(
    int fireAtEpochMs,
    String title,
    String body,
    bool sound,
  ) {
    return _service.scheduleTimed(
      fireAtEpochMs: fireAtEpochMs,
      title: title,
      body: body,
      sound: sound,
    );
  }

  @override
  Future<void> cancel() {
    return _service.cancelTimed();
  }

  Future<void> showImmediate(String title, String body, bool sound) {
    return _service.showImmediate(title: title, body: body, sound: sound);
  }

  Future<void> playNotificationSound() {
    return _service.playNotificationSound();
  }
}
