import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkeycraft_client/notifications/browser_notification_backend.dart';
import 'package:monkeycraft_client/notifications/browser_notification_event.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

class ExactAlarmAccess {
  const ExactAlarmAccess({required this.supported, required this.granted});

  const ExactAlarmAccess.unsupported() : supported = false, granted = true;

  final bool supported;
  final bool granted;

  factory ExactAlarmAccess.fromMap(Map<dynamic, dynamic>? map) {
    return ExactAlarmAccess(
      supported: map?['supported'] == true,
      granted: map?['granted'] == true,
    );
  }
}

class BrowserAlertException implements Exception {
  const BrowserAlertException(this.code);

  final String code;
}

class TimedNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'monkeycraft/notifications',
  );

  final bool _isAndroid;

  TimedNotificationService({bool? isAndroid})
    : _isAndroid = isAndroid ?? platformCapabilities.isAndroid {
    if (platformCapabilities.isWeb) {
      _browserSoundRestore ??= _restoreBrowserSoundPreference();
    }
  }

  static const int timedId = 1;
  static const _browserSoundPreference = 'monkeycraft.browserReminderSound';
  static Future<void>? _browserSoundRestore;

  bool get supportsNotifications =>
      platformCapabilities.supportsNativeNotifications ||
      (platformCapabilities.isWeb && browserNotificationBackend.supported);

  Stream<BrowserNotificationEvent> get browserEvents =>
      browserNotificationBackend.events;
  String get browserPermission => browserNotificationBackend.permission;
  bool get browserSoundEnabled => browserNotificationBackend.soundEnabled;

  Future<bool> requestPermission() async {
    if (platformCapabilities.isWeb) {
      return browserNotificationBackend.supported;
    }
    if (!platformCapabilities.supportsNativeNotifications) {
      return false;
    }
    final result = await _channel.invokeMethod<bool>('requestPermission');
    return result ?? false;
  }

  Future<bool> requestBrowserPermission() async {
    if (!platformCapabilities.isWeb) return requestPermission();
    final results = await Future.wait([
      browserNotificationBackend.requestPermissionFromUserGesture(),
      browserNotificationBackend.setSoundEnabled(true),
    ]);
    await _saveBrowserSoundEnabled(browserNotificationBackend.soundEnabled);
    return results[0];
  }

  Future<void> setBrowserSoundEnabled(bool enabled) async {
    if (!platformCapabilities.isWeb) return;
    final applied = await browserNotificationBackend.setSoundEnabled(enabled);
    await _saveBrowserSoundEnabled(applied && enabled);
    if (enabled && !applied) {
      throw const BrowserAlertException('sound-unavailable');
    }
  }

  Future<bool> enableBrowserAlerts() async {
    if (!platformCapabilities.isWeb) return requestPermission();
    return browserNotificationBackend.enableFromUserGesture();
  }

  Future<void> scheduleTimed({
    required int fireAtEpochMs,
    required String title,
    required String body,
    required bool sound,
  }) async {
    if (platformCapabilities.isWeb) {
      await browserNotificationBackend.schedule(
        fireAtEpochMs: fireAtEpochMs,
        title: title,
        body: body,
        sound: sound,
      );
      return;
    }
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('scheduleTimed', {
      'id': timedId,
      'fireAtEpochMs': fireAtEpochMs,
      'title': title,
      'body': body,
      'sound': sound,
    });
  }

  Future<void> cancelTimed() async {
    if (platformCapabilities.isWeb) {
      await browserNotificationBackend.cancel();
      return;
    }
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('cancelTimed', {'id': timedId});
  }

  Future<void> showImmediate({
    required String title,
    required String body,
    required bool sound,
  }) async {
    if (platformCapabilities.isWeb) {
      await browserNotificationBackend.showImmediate(
        title: title,
        body: body,
        sound: sound,
      );
      return;
    }
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('showImmediate', {
      'title': title,
      'body': body,
      'sound': sound,
    });
  }

  Future<void> playNotificationSound() async {
    if (platformCapabilities.isWeb) {
      await browserNotificationBackend.playTestSound();
      return;
    }
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('playNotificationSound');
  }

  Future<void> playBrowserTestSound() async {
    if (!platformCapabilities.isWeb) return;
    if (!await browserNotificationBackend.playTestSound()) {
      throw const BrowserAlertException('sound-unavailable');
    }
  }

  Future<void> restoreBrowserSoundEnabled() async {
    if (!platformCapabilities.isWeb) return;
    await (_browserSoundRestore ??= _restoreBrowserSoundPreference());
  }

  static Future<void> _restoreBrowserSoundPreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      browserNotificationBackend.restoreSoundEnabled(
        preferences.getBool(_browserSoundPreference) == true,
      );
    } catch (_) {}
  }

  Future<void> _saveBrowserSoundEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_browserSoundPreference, enabled);
  }

  Future<ExactAlarmAccess> getExactAlarmAccess() async {
    if (!_isAndroid) return const ExactAlarmAccess.unsupported();
    final map = await _channel.invokeMapMethod<dynamic, dynamic>(
      'getExactAlarmAccess',
    );
    return ExactAlarmAccess.fromMap(map);
  }

  Future<bool> openExactAlarmSettings() async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('openExactAlarmSettings') ?? false;
  }

  Future<NotificationSettingsInfo> getSettings() async {
    if (!platformCapabilities.isIOS) return NotificationSettingsInfo.unknown;
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'getNotificationSettings',
    );
    return NotificationSettingsInfo.fromMap(map);
  }

  Future<void> openSettings() async {
    if (!platformCapabilities.isIOS) return;
    await _channel.invokeMethod<void>('openNotificationSettings');
  }
}
