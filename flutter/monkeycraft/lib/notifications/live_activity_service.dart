import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

class LiveActivityService {
  static const String _appGroupId = 'group.com.chenweikeng.monkeycraft';
  static const String _timedCountdownActivityId = 'timed_countdown';
  final LiveActivities _liveActivities = LiveActivities();
  bool _initialized = false;
  int? _currentFireAtEpochMs;

  Future<void> init() async {
    if (!Platform.isIOS) return;

    final enabled = await _liveActivities.areActivitiesEnabled();
    if (!enabled) return;

    await _liveActivities.init(appGroupId: _appGroupId);

    // A countdown from a previous app/screen instance can survive (Live
    // Activities outlive a backgrounded app), and after re-init the plugin no
    // longer tracks it by id — so createOrUpdateActivity would spawn a *second*
    // countdown for the same ride. Clear any leftovers before we start fresh;
    // the next TIMED/TIMED_STATUS update recreates a single countdown.
    try {
      await _liveActivities.endAllActivities();
    } catch (e) {
      debugPrint('Live activity cleanup on init failed: $e');
    }

    _initialized = true;
  }

  Future<void> startCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {
    if (!_initialized) return;

    if (_currentFireAtEpochMs == fireAtEpochMs) {
      return;
    }
    _currentFireAtEpochMs = fireAtEpochMs;

    try {
      await _liveActivities.createOrUpdateActivity(_timedCountdownActivityId, {
        'fireAtEpochMs': fireAtEpochMs,
        'body': body.isNotEmpty ? body : 'TBA',
        'countDownText': countDownText.isNotEmpty ? countDownText : 'TBA',
      }, removeWhenAppIsKilled: true);
    } catch (e) {
      debugPrint('Live activity create/update failed: $e');
    }
  }

  Future<void> updateCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {
    if (!_initialized) return;

    await _liveActivities.updateActivity(_timedCountdownActivityId, {
      'fireAtEpochMs': fireAtEpochMs,
      'body': body.isNotEmpty ? body : 'TBA',
      'countDownText': countDownText.isNotEmpty ? countDownText : 'TBA',
    });
  }

  Future<void> cancel() async {
    if (!_initialized) return;

    _currentFireAtEpochMs = null;
    await _liveActivities.endActivity(_timedCountdownActivityId);
  }

  Future<void> dispose() async {
    await cancel();
  }
}
