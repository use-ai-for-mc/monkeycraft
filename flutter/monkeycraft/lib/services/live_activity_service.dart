import 'dart:io';
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
    if (!enabled) {
      print('LiveActivityService: Live Activities not enabled');
      return;
    }

    await _liveActivities.init(appGroupId: _appGroupId);
    _initialized = true;
    print('LiveActivityService: Initialized successfully');
  }

  Future<void> startCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {
    if (!_initialized) {
      print('LiveActivityService: Not initialized, skipping startCountdown');
      return;
    }

    if (_currentFireAtEpochMs == fireAtEpochMs) {
      return;
    }
    _currentFireAtEpochMs = fireAtEpochMs;

    print(
      'LiveActivityService: Creating/updating activity with id=$_timedCountdownActivityId',
    );
    try {
      await _liveActivities.createOrUpdateActivity(_timedCountdownActivityId, {
        'fireAtEpochMs': fireAtEpochMs,
        'body': body.isNotEmpty ? body : 'TBA',
        'countDownText': countDownText.isNotEmpty ? countDownText : 'TBA',
      }, removeWhenAppIsKilled: true);
      print('LiveActivityService: Activity created/updated successfully');
    } catch (e) {
      print('LiveActivityService: Failed to create/update activity: $e');
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
