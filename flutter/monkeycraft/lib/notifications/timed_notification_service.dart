import 'package:flutter/services.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

class TimedNotificationService {
  static const MethodChannel _channel = MethodChannel('monkeycraft/notifications');

  static const int timedId = 1;

  Future<bool> requestPermission() async {
    if (!platformCapabilities.supportsNativeNotifications) return false;
    final result = await _channel.invokeMethod<bool>('requestPermission');
    return result ?? false;
  }

  Future<void> scheduleTimed({
    required int fireAtEpochMs,
    required String title,
    required String body,
    required bool sound,
  }) async {
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
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('cancelTimed', {'id': timedId});
  }

  Future<void> showImmediate({
    required String title,
    required String body,
    required bool sound,
  }) async {
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('showImmediate', {
      'title': title,
      'body': body,
      'sound': sound,
    });
  }

  Future<void> playNotificationSound() async {
    if (!platformCapabilities.supportsNativeNotifications) return;
    await _channel.invokeMethod<void>('playNotificationSound');
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
