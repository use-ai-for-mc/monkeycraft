import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';

import 'package:monkeycraft_client/notifications/browser_notification_event.dart';
import 'package:web/web.dart' as web;

@JS('globalThis.Notification')
external JSAny? get _notificationConstructor;

@JS('globalThis.navigator.serviceWorker')
external JSAny? get _serviceWorkerApi;

typedef BrowserNow = int Function();
typedef BrowserTimerFactory =
    Object Function(Duration delay, void Function() callback);
typedef BrowserTimerCancel = void Function(Object timer);

abstract class BrowserNotificationPlatform {
  bool get systemNotificationsSupported;
  String get permission;
  bool get pageHidden;
  bool get soundReady;

  Future<String> requestPermission();
  Future<bool> unlockSound();
  bool playTone();
  Future<bool> showSystemNotification({
    required String title,
    required String body,
    required bool silent,
    required String tag,
    required bool Function() isCurrent,
  });
  bool wasTimedNotificationFired(String key);
  void markTimedNotificationFired(String key);
}

class BrowserNotificationBackend {
  static const lateGrace = Duration(seconds: 15);
  static const _maxDelay = Duration(milliseconds: 2147483647);
  static const _nudgeDeduplicationWindow = Duration(seconds: 1);
  static const _maxRecentNudges = 32;

  BrowserNotificationBackend({
    BrowserNotificationPlatform? platform,
    BrowserNow? now,
    BrowserTimerFactory? createTimer,
    BrowserTimerCancel? cancelTimer,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _createTimer =
           createTimer ?? ((delay, callback) => Timer(delay, callback)),
       _cancelTimer = cancelTimer ?? ((timer) => (timer as Timer).cancel()) {
    _platform =
        platform ??
        WebBrowserNotificationPlatform(soundEnabled: () => _soundEnabled);
  }

  late final BrowserNotificationPlatform _platform;
  final BrowserNow _now;
  final BrowserTimerFactory _createTimer;
  final BrowserTimerCancel _cancelTimer;
  final StreamController<BrowserNotificationEvent> _events =
      StreamController<BrowserNotificationEvent>.broadcast();
  final LinkedHashMap<String, int> _recentNudges = LinkedHashMap();

  Object? _timer;
  int _generation = 0;
  int _soundGeneration = 0;
  int? _fireAtEpochMs;
  String? _title;
  String? _body;
  bool? _sound;
  String? _timedKey;
  bool _soundEnabled = false;
  bool _soundPreferenceTouched = false;

  bool get supported => true;
  bool get systemNotificationsSupported =>
      _platform.systemNotificationsSupported;
  String get permission =>
      systemNotificationsSupported ? _platform.permission : 'unavailable';
  bool get permissionGranted => permission == 'granted';
  bool get soundEnabled => _soundEnabled;
  Stream<BrowserNotificationEvent> get events => _events.stream;

  Future<bool> requestPermissionFromUserGesture() async {
    if (!systemNotificationsSupported) return false;
    try {
      return await _platform.requestPermission() == 'granted';
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockSoundFromUserGesture() async {
    final generation = ++_soundGeneration;
    final unlocked = await _unlockSound();
    if (generation != _soundGeneration) return _soundEnabled;
    _soundEnabled = unlocked;
    return unlocked;
  }

  Future<bool> setSoundEnabled(bool enabled) async {
    _soundPreferenceTouched = true;
    final generation = ++_soundGeneration;
    _soundEnabled = enabled;
    if (!enabled) return true;
    final unlocked = await _unlockSound();
    if (generation != _soundGeneration) return _soundEnabled;
    _soundEnabled = unlocked;
    return unlocked;
  }

  void restoreSoundEnabled(bool enabled) {
    if (_soundPreferenceTouched) return;
    _soundGeneration += 1;
    _soundEnabled = enabled;
  }

  Future<bool> _unlockSound() async {
    try {
      return await _platform.unlockSound().timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableFromUserGesture() async {
    final results = await Future.wait([
      setSoundEnabled(true),
      requestPermissionFromUserGesture(),
    ]);
    return results.any((value) => value);
  }

  Future<bool> playTestSound() async {
    if (!_soundEnabled) return false;
    if (!_platform.soundReady && !await unlockSoundFromUserGesture()) {
      return false;
    }
    return _soundEnabled && _platform.playTone();
  }

  Future<void> schedule({
    required int fireAtEpochMs,
    required String title,
    required String body,
    required bool sound,
  }) async {
    final key = _timedNotificationKey(fireAtEpochMs, title, body);
    if (_timedKey == key && _fireAtEpochMs != null) {
      _sound = sound;
      return;
    }
    final generation = ++_generation;
    _clearTimedState();
    if (_platform.wasTimedNotificationFired(key)) return;
    final lateBy = _now() - fireAtEpochMs;
    if (lateBy > lateGrace.inMilliseconds) {
      _platform.markTimedNotificationFired(key);
      return;
    }
    _fireAtEpochMs = fireAtEpochMs;
    _title = title;
    _body = body;
    _sound = sound;
    _timedKey = key;
    _arm(generation);
  }

  Future<void> cancel() async {
    _generation += 1;
    _clearTimedState();
  }

  Future<void> showImmediate({
    required String title,
    required String body,
    required bool sound,
  }) async {
    final now = _now();
    _recentNudges.removeWhere(
      (_, seenAt) => now - seenAt >= _nudgeDeduplicationWindow.inMilliseconds,
    );
    final key = '$title\u0000$body\u0000$sound';
    if (_recentNudges.containsKey(key)) return;
    _recentNudges[key] = now;
    while (_recentNudges.length > _maxRecentNudges) {
      _recentNudges.remove(_recentNudges.keys.first);
    }
    await _deliver(BrowserNotificationKind.immediate, title, body, sound);
  }

  void _clearTimedState() {
    final timer = _timer;
    if (timer != null) _cancelTimer(timer);
    _timer = null;
    _fireAtEpochMs = null;
    _title = null;
    _body = null;
    _sound = null;
    _timedKey = null;
  }

  void _arm(int generation) {
    if (generation != _generation) return;
    final fireAt = _fireAtEpochMs;
    if (fireAt == null) return;
    final remaining = fireAt - _now();
    if (remaining <= 0) {
      unawaited(_fire(generation));
      return;
    }
    final delay = Duration(
      milliseconds: remaining.clamp(1, _maxDelay.inMilliseconds),
    );
    _timer = _createTimer(delay, () => _arm(generation));
  }

  Future<void> _fire(int generation) async {
    if (generation != _generation) return;
    final fireAt = _fireAtEpochMs;
    final title = _title;
    final body = _body;
    final sound = _sound;
    final key = _timedKey;
    if (fireAt == null ||
        title == null ||
        body == null ||
        sound == null ||
        key == null) {
      return;
    }
    final lateBy = _now() - fireAt;
    if (lateBy < 0) {
      _arm(generation);
      return;
    }
    if (lateBy > lateGrace.inMilliseconds) {
      _platform.markTimedNotificationFired(key);
      if (generation == _generation) _clearTimedState();
      return;
    }
    _platform.markTimedNotificationFired(key);
    _clearTimedState();
    await _deliver(
      BrowserNotificationKind.timed,
      title,
      body,
      sound,
      generation: generation,
    );
  }

  Future<void> _deliver(
    BrowserNotificationKind kind,
    String title,
    String body,
    bool sound, {
    int? generation,
  }) async {
    final hidden = _platform.pageHidden;
    var systemNotification = false;
    if (hidden && permissionGranted) {
      systemNotification = await _platform.showSystemNotification(
        title: title,
        body: body,
        silent: !sound || !_soundEnabled,
        tag: kind == BrowserNotificationKind.timed
            ? 'monkeycraft-timed'
            : 'monkeycraft-immediate',
        isCurrent: () => generation == null || generation == _generation,
      );
    } else if (!hidden && sound && _soundEnabled && _platform.soundReady) {
      _platform.playTone();
    }
    if (generation != null && generation != _generation) return;
    _events.add(
      BrowserNotificationEvent(
        kind: kind,
        title: title,
        body: body,
        sound: sound && _soundEnabled,
        systemNotification: systemNotification,
      ),
    );
  }

  String _timedNotificationKey(int fireAtEpochMs, String title, String body) =>
      '$fireAtEpochMs\u0000$title\u0000$body';
}

class WebBrowserNotificationPlatform implements BrowserNotificationPlatform {
  static const _maxFired = 32;

  WebBrowserNotificationPlatform({
    bool Function()? soundEnabled,
    bool Function()? pageHidden,
    web.AudioContext Function()? createAudioContext,
  }) : _soundEnabled = soundEnabled ?? (() => true),
       _pageHidden = pageHidden ?? (() => web.document.hidden),
       _createAudioContext = createAudioContext ?? (() => web.AudioContext()) {
    _visibilityListener = ((web.Event _) {
      if (this.pageHidden) {
        _backgroundAudio();
      } else {
        _recoverAudio();
      }
    }).toJS;
    _pageHideListener = ((web.Event _) => _backgroundAudio()).toJS;
    _recoveryListener = ((web.Event _) => _recoverAudio()).toJS;
    _gestureListener = ((web.Event _) {
      if (!_disposed && !this.pageHidden && _soundEnabled() && !soundReady) {
        unawaited(unlockSound());
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
    web.window.addEventListener('pagehide', _pageHideListener);
    web.window.addEventListener('pageshow', _recoveryListener);
    web.window.addEventListener('focus', _recoveryListener);
    web.document.addEventListener('pointerup', _gestureListener, true.toJS);
    web.document.addEventListener('click', _gestureListener, true.toJS);
    web.document.addEventListener('keydown', _gestureListener, true.toJS);
  }

  final bool Function() _soundEnabled;
  final bool Function() _pageHidden;
  final web.AudioContext Function() _createAudioContext;
  late final JSFunction _visibilityListener;
  late final JSFunction _pageHideListener;
  late final JSFunction _recoveryListener;
  late final JSFunction _gestureListener;
  bool _disposed = false;
  bool _backgrounded = false;
  int _audioEpoch = 0;
  final List<Timer> _recoveryTimers = [];
  web.AudioContext? _audio;
  Future<web.ServiceWorkerRegistration?>? _registration;

  @override
  bool get systemNotificationsSupported => _notificationConstructor != null;

  @override
  String get permission => systemNotificationsSupported
      ? web.Notification.permission
      : 'unavailable';

  @override
  bool get pageHidden => _pageHidden();

  @override
  bool get soundReady =>
      !_disposed && !_backgrounded && !pageHidden && _audio?.state == 'running';

  @override
  Future<String> requestPermission() async {
    if (!systemNotificationsSupported) return 'unavailable';
    return (await web.Notification.requestPermission().toDart).toDart;
  }

  @override
  Future<bool> unlockSound() async {
    if (_disposed || _backgrounded || pageHidden) return false;
    final epoch = _audioEpoch;
    try {
      if (_audio?.state == 'closed') _audio = null;
      final audio = _audio ??= _createAudioContext();
      await audio.resume().toDart.timeout(const Duration(seconds: 3));
      return !_disposed &&
          !_backgrounded &&
          epoch == _audioEpoch &&
          !pageHidden &&
          _audio == audio &&
          audio.state == 'running';
    } catch (_) {
      return false;
    }
  }

  void _cancelRecovery() {
    _audioEpoch += 1;
    for (final timer in _recoveryTimers) {
      timer.cancel();
    }
    _recoveryTimers.clear();
  }

  void _backgroundAudio() {
    _backgrounded = true;
    _cancelRecovery();
  }

  void _recoverAudio() {
    if (_disposed || pageHidden) return;
    _backgrounded = false;
    _cancelRecovery();
    final audio = _audio;
    if (!_soundEnabled() || audio == null || audio.state == 'closed') return;
    final epoch = _audioEpoch;
    final startedAt = audio.currentTime;
    unawaited(unlockSound());
    _recoveryTimers.add(
      Timer(const Duration(milliseconds: 300), () {
        if (!_canRecover(audio, epoch)) return;
        if (audio.state == 'running' && audio.currentTime <= startedAt) {
          unawaited(_restartStalledAudio(audio, epoch));
        } else if (audio.state != 'running') {
          unawaited(unlockSound());
        }
      }),
    );
    _recoveryTimers.add(
      Timer(const Duration(seconds: 1), () {
        if (_canRecover(audio, epoch) && audio.state != 'running') {
          unawaited(unlockSound());
        }
      }),
    );
  }

  bool _canRecover(web.AudioContext audio, int epoch) =>
      !_disposed &&
      !_backgrounded &&
      !pageHidden &&
      _soundEnabled() &&
      epoch == _audioEpoch &&
      _audio == audio &&
      audio.state != 'closed';

  Future<void> _restartStalledAudio(web.AudioContext audio, int epoch) async {
    try {
      await audio.suspend().toDart.timeout(const Duration(seconds: 3));
      if (_canRecover(audio, epoch)) await unlockSound();
    } catch (_) {}
  }

  void _retireAudio() {
    final audio = _audio;
    _audio = null;
    if (audio == null || audio.state == 'closed') return;
    try {
      unawaited(audio.close().toDart.then<void>((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelRecovery();
    web.document.removeEventListener('visibilitychange', _visibilityListener);
    web.window.removeEventListener('pagehide', _pageHideListener);
    web.window.removeEventListener('pageshow', _recoveryListener);
    web.window.removeEventListener('focus', _recoveryListener);
    web.document.removeEventListener('pointerup', _gestureListener, true.toJS);
    web.document.removeEventListener('click', _gestureListener, true.toJS);
    web.document.removeEventListener('keydown', _gestureListener, true.toJS);
    _retireAudio();
  }

  @override
  bool playTone() {
    final audio = _audio;
    if (!soundReady || audio == null) {
      return false;
    }
    try {
      final oscillator = audio.createOscillator();
      final gain = audio.createGain();
      oscillator.frequency.value = 660;
      gain.gain.value = 0.08;
      oscillator.connect(gain);
      gain.connect(audio.destination);
      oscillator.start();
      oscillator.stop(audio.currentTime + 0.16);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> showSystemNotification({
    required String title,
    required String body,
    required bool silent,
    required String tag,
    required bool Function() isCurrent,
  }) async {
    if (permission != 'granted') return false;
    final registration = await _serviceWorkerRegistration();
    if (registration == null || !isCurrent()) return false;
    try {
      await registration
          .showNotification(
            title,
            web.NotificationOptions(body: body, tag: tag, silent: silent),
          )
          .toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<web.ServiceWorkerRegistration?> _serviceWorkerRegistration() {
    final existing = _registration;
    if (existing != null) return existing;
    final attempt = _registerServiceWorker();
    _registration = attempt;
    return attempt.then((registration) {
      if (registration == null) _registration = null;
      return registration;
    });
  }

  Future<web.ServiceWorkerRegistration?> _registerServiceWorker() async {
    if (_serviceWorkerApi == null || !web.window.isSecureContext) return null;
    try {
      final baseUri = Uri.parse(web.document.baseURI);
      final registration = await web.window.navigator.serviceWorker
          .register(baseUri.resolve('reminder-sw.js').toString().toJS)
          .toDart
          .timeout(const Duration(seconds: 3));
      return await _waitForActivation(registration);
    } catch (_) {
      return null;
    }
  }

  Future<web.ServiceWorkerRegistration?> _waitForActivation(
    web.ServiceWorkerRegistration registration,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (registration.active == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return registration.active == null ? null : registration;
  }

  @override
  bool wasTimedNotificationFired(String key) => _loadFired().contains(key);

  @override
  void markTimedNotificationFired(String key) {
    final fired = _loadFired();
    fired.remove(key);
    fired.add(key);
    while (fired.length > _maxFired) {
      fired.remove(fired.first);
    }
    try {
      web.window.sessionStorage.setItem(
        _firedStorageKey,
        jsonEncode(fired.toList()),
      );
    } catch (_) {}
  }

  LinkedHashSet<String> _loadFired() {
    try {
      final stored = web.window.sessionStorage.getItem(_firedStorageKey);
      if (stored == null || stored.isEmpty) return LinkedHashSet();
      final decoded = jsonDecode(stored);
      if (decoded is! List) return LinkedHashSet();
      return LinkedHashSet.of(decoded.whereType<String>());
    } catch (_) {
      return LinkedHashSet();
    }
  }

  String get _firedStorageKey =>
      'monkeycraft.reminder-fires:${Uri.parse(web.document.baseURI).path}';
}

final browserNotificationBackend = BrowserNotificationBackend();
