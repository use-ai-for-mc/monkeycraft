import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:live_activities/live_activities.dart';

abstract class LiveActivityBackend {
  Future<bool> initialize(String appGroupId);
  Future<void> clear();
  Future<void> createOrUpdate(String id, Map<String, dynamic> payload);
  Future<void> update(String id, Map<String, dynamic> payload);
  Future<void> end(String id);
}

class _IosLiveActivityBackend implements LiveActivityBackend {
  _IosLiveActivityBackend(this._activities);

  final LiveActivities _activities;

  @override
  Future<bool> initialize(String appGroupId) async {
    if (!await _activities.areActivitiesEnabled()) return false;
    await _activities.init(appGroupId: appGroupId);
    return true;
  }

  @override
  Future<void> clear() => _activities.endAllActivities();

  @override
  Future<void> createOrUpdate(String id, Map<String, dynamic> payload) {
    return _activities.createOrUpdateActivity(
      id,
      payload,
      removeWhenAppIsKilled: true,
    );
  }

  @override
  Future<void> update(String id, Map<String, dynamic> payload) {
    return _activities.updateActivity(id, payload);
  }

  @override
  Future<void> end(String id) => _activities.endActivity(id);
}

class _AndroidLiveActivityBackend implements LiveActivityBackend {
  _AndroidLiveActivityBackend(this._channel);

  final MethodChannel _channel;

  @override
  Future<bool> initialize(String appGroupId) async => true;

  @override
  Future<void> clear() => _channel.invokeMethod('cancelCountdown');

  @override
  Future<void> createOrUpdate(String id, Map<String, dynamic> payload) {
    return _channel.invokeMethod('startCountdown', payload);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> payload) {
    return _channel.invokeMethod('updateCountdown', payload);
  }

  @override
  Future<void> end(String id) => _channel.invokeMethod('cancelCountdown');
}

class _UnavailableLiveActivityBackend implements LiveActivityBackend {
  @override
  Future<bool> initialize(String appGroupId) async => false;

  @override
  Future<void> clear() async {}

  @override
  Future<void> createOrUpdate(String id, Map<String, dynamic> payload) async {}

  @override
  Future<void> update(String id, Map<String, dynamic> payload) async {}

  @override
  Future<void> end(String id) async {}
}

class LiveActivityService {
  static const String _appGroupId = 'group.com.chenweikeng.monkeycraft';
  static const String _timedCountdownActivityId = 'timed_countdown';
  static const MethodChannel _androidChannel = MethodChannel(
    'monkeycraft/notifications',
  );

  LiveActivityService({LiveActivityBackend? backend, DateTime Function()? now})
    : _backend = backend ?? _defaultBackend(),
      _now = now ?? DateTime.now;

  final LiveActivityBackend _backend;
  final DateTime Function() _now;
  bool _initialized = false;
  String? _currentSignature;
  Future<void> _operations = Future<void>.value();
  Future<void>? _initializing;

  static LiveActivityBackend _defaultBackend() {
    if (Platform.isIOS) return _IosLiveActivityBackend(LiveActivities());
    if (Platform.isAndroid) return _AndroidLiveActivityBackend(_androidChannel);
    return _UnavailableLiveActivityBackend();
  }

  Future<void> init() {
    if (_initialized) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    final initializing = _enqueue(() async {
      try {
        if (!await _backend.initialize(_appGroupId)) return;
        await _backend.clear();
        _initialized = true;
      } catch (error) {
        debugPrint('Live activity initialization failed: $error');
      }
    });
    _initializing = initializing;
    initializing.whenComplete(() {
      if (identical(_initializing, initializing)) _initializing = null;
    });
    return initializing;
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

  String _signature(Map<String, dynamic> payload) {
    return '${payload['fireAtEpochMs']}\u0000${payload['title']}\u0000${payload['body']}\u0000${payload['countDownText']}';
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((_) {});
    return next;
  }

  Future<void> startCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) {
    final payload = _payload(fireAtEpochMs, title, body, countDownText);
    return _enqueue(() async {
      if (!_initialized) return;
      if (fireAtEpochMs <= _now().millisecondsSinceEpoch) {
        await _cancelNow();
        return;
      }
      final signature = _signature(payload);
      if (_currentSignature == signature) return;
      try {
        await _backend.createOrUpdate(_timedCountdownActivityId, payload);
        _currentSignature = signature;
      } catch (error) {
        debugPrint('Countdown create/update failed: $error');
      }
    });
  }

  Future<void> updateCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) {
    final payload = _payload(fireAtEpochMs, title, body, countDownText);
    return _enqueue(() async {
      if (!_initialized) return;
      if (fireAtEpochMs <= _now().millisecondsSinceEpoch) {
        await _cancelNow();
        return;
      }
      final signature = _signature(payload);
      if (_currentSignature == signature) return;
      try {
        await _backend.update(_timedCountdownActivityId, payload);
        _currentSignature = signature;
      } catch (error) {
        debugPrint('Countdown update failed: $error');
      }
    });
  }

  Future<void> _cancelNow() async {
    _currentSignature = null;
    try {
      await _backend.end(_timedCountdownActivityId);
    } catch (error) {
      debugPrint('Countdown cancel failed: $error');
    }
  }

  Future<void> cancel() {
    return _enqueue(() async {
      if (!_initialized) return;
      await _cancelNow();
    });
  }

  Future<void> dispose() => cancel();
}
