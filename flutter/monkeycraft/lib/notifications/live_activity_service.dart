import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:live_activities/live_activities.dart';

/// The ride countdown. On iOS this is an ActivityKit Live Activity; on Android
/// it is an ongoing chronometer notification posted through the shared
/// `monkeycraft/notifications` channel. Same public API on both platforms.
class LiveActivityService {
  static const String _appGroupId = 'group.com.chenweikeng.monkeycraft';
  static const String _timedCountdownActivityId = 'timed_countdown';
  static const MethodChannel _androidChannel =
      MethodChannel('monkeycraft/notifications');

  final LiveActivities _liveActivities = LiveActivities();
  bool _initialized = false;
  int? _currentFireAtEpochMs;

  Future<void> init() async {
    if (Platform.isIOS) {
      final enabled = await _liveActivities.areActivitiesEnabled();
      if (!enabled) return;
      await _liveActivities.init(appGroupId: _appGroupId);
      // Clear a countdown orphaned by a previous instance (duplicate-countdown fix).
      try {
        await _liveActivities.endAllActivities();
      } catch (e) {
        debugPrint('Live activity cleanup on init failed: $e');
      }
      _initialized = true;
    } else if (Platform.isAndroid) {
      // Same anti-duplicate cleanup: drop any stale countdown notification.
      try {
        await _androidChannel.invokeMethod('cancelCountdown');
      } catch (e) {
        debugPrint('Countdown cleanup on init failed: $e');
      }
      _initialized = true;
    }
  }

  Map<String, dynamic> _payload(
    int fireAtEpochMs,
    String title,
    String body,
    String countDownText,
  ) {
    return {
      'fireAtEpochMs': fireAtEpochMs,
      'title': title,
      'body': body.isNotEmpty ? body : 'TBA',
      'countDownText': countDownText.isNotEmpty ? countDownText : 'TBA',
    };
  }

  Future<void> startCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {
    if (!_initialized) return;
    if (fireAtEpochMs <= DateTime.now().millisecondsSinceEpoch) {
      // The target time has already passed — never post (or re-post) a
      // chronometer that would tick into negative values. The server can
      // keep sending TIMED_STATUS updates with the same past fireAt; just
      // ensure any stale countdown is cleared.
      await cancel();
      return;
    }
    if (_currentFireAtEpochMs == fireAtEpochMs) return;
    _currentFireAtEpochMs = fireAtEpochMs;

    final payload = _payload(fireAtEpochMs, title, body, countDownText);
    try {
      if (Platform.isIOS) {
        await _liveActivities.createOrUpdateActivity(
          _timedCountdownActivityId,
          payload,
          removeWhenAppIsKilled: true,
        );
      } else if (Platform.isAndroid) {
        await _androidChannel.invokeMethod('startCountdown', payload);
      }
    } catch (e) {
      debugPrint('Countdown create/update failed: $e');
    }
  }

  Future<void> updateCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {
    if (!_initialized) return;
    if (fireAtEpochMs <= DateTime.now().millisecondsSinceEpoch) {
      await cancel();
      return;
    }

    final payload = _payload(fireAtEpochMs, title, body, countDownText);
    try {
      if (Platform.isIOS) {
        await _liveActivities.updateActivity(_timedCountdownActivityId, payload);
      } else if (Platform.isAndroid) {
        await _androidChannel.invokeMethod('updateCountdown', payload);
      }
    } catch (e) {
      debugPrint('Countdown update failed: $e');
    }
  }

  Future<void> cancel() async {
    if (!_initialized) return;
    _currentFireAtEpochMs = null;
    try {
      if (Platform.isIOS) {
        await _liveActivities.endActivity(_timedCountdownActivityId);
      } else if (Platform.isAndroid) {
        await _androidChannel.invokeMethod('cancelCountdown');
      }
    } catch (e) {
      debugPrint('Countdown cancel failed: $e');
    }
  }

  Future<void> dispose() async {
    await cancel();
  }
}
