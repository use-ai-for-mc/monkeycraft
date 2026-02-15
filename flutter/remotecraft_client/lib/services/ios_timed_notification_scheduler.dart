import 'dart:io';

import 'package:monkeycraft_client/services/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/services/timed_notification_service.dart';

class IosTimedNotificationScheduler implements TimedNotificationScheduler {
  final TimedNotificationService _service;
  bool? _granted;

  IosTimedNotificationScheduler(this._service);

  @override
  Future<bool> ensurePermission() async {
    if (!Platform.isIOS) return false;
    final granted = _granted;
    if (granted != null) return granted;
    final next = await _service.requestPermission();
    _granted = next;
    return next;
  }

  @override
  Future<void> schedule(int fireAtEpochMs, String title, String body, bool sound) {
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
}
