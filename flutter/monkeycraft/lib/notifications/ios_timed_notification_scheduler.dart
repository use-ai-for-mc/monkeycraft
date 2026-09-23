import 'package:monkeycraft_client/notifications/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';

typedef NotificationPermissionRequest = Future<bool> Function();
typedef ImmediateNotificationShow =
    Future<void> Function({
      required String title,
      required String body,
      required bool sound,
    });

class IosTimedNotificationScheduler implements TimedNotificationScheduler {
  final TimedNotificationService _service;
  final NotificationPermissionRequest _requestPermission;
  final bool _supportsNativeNotifications;
  final ImmediateNotificationShow _showImmediate;
  Future<bool>? _permissionRequest;
  final int Function() _nowMilliseconds;
  final _recentImmediate = <(String, String, bool), int>{};

  IosTimedNotificationScheduler(
    this._service, {
    NotificationPermissionRequest? requestPermission,
    ImmediateNotificationShow? showImmediate,
    bool? supportsNativeNotifications,
    int Function()? nowMilliseconds,
  }) : _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch),
       _requestPermission = requestPermission ?? _service.requestPermission,
       _showImmediate = showImmediate ?? _service.showImmediate,
       _supportsNativeNotifications =
           supportsNativeNotifications ?? _service.supportsNotifications;

  @override
  Future<bool> ensurePermission() {
    if (!_supportsNativeNotifications) return Future.value(false);
    final pending = _permissionRequest;
    if (pending != null) return pending;
    final request = _requestPermission();
    _permissionRequest = request;
    return request.whenComplete(() {
      _permissionRequest = null;
    });
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

  Future<bool> showImmediate(String title, String body, bool sound) async {
    if (!await ensurePermission()) return false;
    final now = _nowMilliseconds();
    _recentImmediate.removeWhere((_, seen) => now - seen >= 1000 || now < seen);
    final key = (title, body, sound);
    if (_recentImmediate.containsKey(key)) return false;
    _recentImmediate[key] = now;
    while (_recentImmediate.length > 32) {
      _recentImmediate.remove(_recentImmediate.keys.first);
    }
    try {
      await _showImmediate(title: title, body: body, sound: sound);
      return true;
    } catch (_) {
      if (_recentImmediate[key] == now) _recentImmediate.remove(key);
      rethrow;
    }
  }

  Future<void> playNotificationSound() {
    return _service.playNotificationSound();
  }
}
