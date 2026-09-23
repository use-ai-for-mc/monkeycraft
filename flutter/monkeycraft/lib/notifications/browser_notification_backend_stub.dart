import 'dart:async';

import 'package:monkeycraft_client/notifications/browser_notification_event.dart';

class BrowserNotificationBackend {
  bool get supported => false;
  bool get systemNotificationsSupported => false;
  String get permission => 'unavailable';
  bool get permissionGranted => false;
  bool get soundEnabled => false;
  Stream<BrowserNotificationEvent> get events => const Stream.empty();

  Future<bool> requestPermissionFromUserGesture() async => false;
  Future<bool> unlockSoundFromUserGesture() async => false;
  Future<bool> setSoundEnabled(bool enabled) async => !enabled;
  void restoreSoundEnabled(bool enabled) {}
  Future<bool> enableFromUserGesture() async => false;
  Future<bool> playTestSound() async => false;

  Future<void> schedule({
    required int fireAtEpochMs,
    required String title,
    required String body,
    required bool sound,
  }) async {}

  Future<void> cancel() async {}

  Future<void> showImmediate({
    required String title,
    required String body,
    required bool sound,
  }) async {}
}

final browserNotificationBackend = BrowserNotificationBackend();
