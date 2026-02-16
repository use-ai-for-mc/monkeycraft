import 'dart:io';

import 'package:flutter/services.dart';

class TimedNotificationService {
  static const MethodChannel _channel = MethodChannel('monkeycraft/notifications');

  static const int timedId = 1;

  Future<bool> requestPermission() async {
    if (!Platform.isIOS) return false;
    final result = await _channel.invokeMethod<bool>('requestPermission');
    return result ?? false;
  }

  Future<void> scheduleTimed({
    required int fireAtEpochMs,
    required String title,
    required String body,
    required bool sound,
  }) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('scheduleTimed', {
      'id': timedId,
      'fireAtEpochMs': fireAtEpochMs,
      'title': title,
      'body': body,
      'sound': sound,
    });
  }

  Future<void> cancelTimed() async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('cancelTimed', {'id': timedId});
  }
}
