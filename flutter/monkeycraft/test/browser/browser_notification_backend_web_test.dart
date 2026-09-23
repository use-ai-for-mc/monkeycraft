@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/browser_notification_backend_web.dart';
import 'package:monkeycraft_client/notifications/browser_notification_event.dart';

void main() {
  late _FakePlatform platform;
  late _FakeClock clock;
  late _FakeTimers timers;
  late BrowserNotificationBackend backend;

  setUp(() {
    platform = _FakePlatform();
    clock = _FakeClock(100000);
    timers = _FakeTimers();
    backend = BrowserNotificationBackend(
      platform: platform,
      now: clock.call,
      createTimer: timers.create,
      cancelTimer: timers.cancel,
    );
  });

  test(
    'unsupported and denied system notifications still emit page banners',
    () async {
      platform.systemSupported = false;
      final unsupported = expectLater(
        backend.events,
        emits(
          predicate<BrowserNotificationEvent>(
            (event) => event.title == 'unsupported',
          ),
        ),
      );
      await backend.showImmediate(
        title: 'unsupported',
        body: 'body',
        sound: true,
      );
      await unsupported;
      expect(platform.systemCalls, isEmpty);
      expect(platform.toneCount, 0);

      platform.systemSupported = true;
      platform.permissionValue = 'denied';
      platform.hidden = true;
      final denied = expectLater(
        backend.events,
        emits(
          predicate<BrowserNotificationEvent>(
            (event) => event.title == 'denied',
          ),
        ),
      );
      await backend.showImmediate(title: 'denied', body: 'body', sound: true);
      await denied;
      expect(platform.systemCalls, isEmpty);
    },
  );

  test(
    'foreground sound follows preference and never waits for a later resume',
    () async {
      platform.soundIsReady = true;
      await backend.showImmediate(title: 'off', body: '', sound: true);
      expect(platform.toneCount, 0);

      backend.restoreSoundEnabled(true);
      platform.soundIsReady = false;
      final event = backend.events.first;
      await backend.showImmediate(title: 'locked', body: '', sound: true);
      expect((await event).sound, isTrue);
      expect(platform.unlockCalls, 0);
      expect(platform.toneCount, 0);

      platform.soundIsReady = true;
      await backend.showImmediate(title: 'on', body: '', sound: true);
      expect(platform.toneCount, 1);
      await backend.showImmediate(
        title: 'server silent',
        body: '',
        sound: false,
      );
      expect(platform.toneCount, 1);
    },
  );

  test(
    'background uses service worker silent semantics without page audio',
    () async {
      platform.hidden = true;
      platform.permissionValue = 'granted';
      platform.soundIsReady = true;
      backend.restoreSoundEnabled(true);

      final audibleEvent = backend.events.first;
      await backend.showImmediate(title: 'audible', body: 'body', sound: true);
      expect((await audibleEvent).systemNotification, isTrue);
      expect(platform.systemCalls.single.silent, isFalse);
      expect(platform.toneCount, 0);

      platform.systemResult = false;
      final fallbackEvent = backend.events.first;
      await backend.showImmediate(title: 'failed', body: 'body', sound: true);
      expect((await fallbackEvent).systemNotification, isFalse);
      expect(platform.toneCount, 0);

      await backend.showImmediate(title: 'silent', body: 'body', sound: false);
      expect(platform.systemCalls.last.silent, isTrue);
    },
  );

  test('timer fires once and an identical replay is deduplicated', () async {
    final events = <BrowserNotificationEvent>[];
    backend.events.listen(events.add);
    await backend.schedule(
      fireAtEpochMs: 101000,
      title: 'timer',
      body: 'body',
      sound: false,
    );
    expect(timers.active.single.delay, const Duration(seconds: 1));
    clock.now = 101000;
    timers.active.single.fire();
    await _flush();
    expect(events.map((event) => event.title), ['timer']);

    await backend.schedule(
      fireAtEpochMs: 101000,
      title: 'timer',
      body: 'body',
      sound: false,
    );
    expect(timers.active, isEmpty);
    expect(events, hasLength(1));
  });

  test('replacement and cancellation invalidate old timer callbacks', () async {
    final events = <BrowserNotificationEvent>[];
    backend.events.listen(events.add);
    await backend.schedule(
      fireAtEpochMs: 101000,
      title: 'old',
      body: '',
      sound: false,
    );
    final old = timers.all.single;
    await backend.schedule(
      fireAtEpochMs: 102000,
      title: 'new',
      body: '',
      sound: false,
    );
    expect(old.cancelled, isTrue);
    clock.now = 101000;
    old.forceFire();
    await _flush();
    expect(events, isEmpty);

    final replacement = timers.active.single;
    await backend.cancel();
    expect(replacement.cancelled, isTrue);
    clock.now = 102000;
    replacement.forceFire();
    await _flush();
    expect(events, isEmpty);
  });

  test(
    'late grace delivers a resumed timer but discards an expired timer',
    () async {
      final events = <BrowserNotificationEvent>[];
      backend.events.listen(events.add);
      await backend.schedule(
        fireAtEpochMs: 101000,
        title: 'within grace',
        body: '',
        sound: false,
      );
      clock.now = 116000;
      timers.active.single.fire();
      await _flush();
      expect(events.map((event) => event.title), ['within grace']);

      await backend.schedule(
        fireAtEpochMs: 117000,
        title: 'expired',
        body: '',
        sound: false,
      );
      clock.now = 132001;
      timers.active.single.fire();
      await _flush();
      expect(events, hasLength(1));

      await backend.schedule(
        fireAtEpochMs: 100000,
        title: 'already stale',
        body: '',
        sound: false,
      );
      expect(timers.active, isEmpty);
      expect(events, hasLength(1));
    },
  );

  test(
    'cancel suppresses a timed event crossing async system delivery',
    () async {
      platform.hidden = true;
      platform.permissionValue = 'granted';
      final pendingWorker = Completer<void>();
      platform.beforeSystemShow = pendingWorker;
      final events = <BrowserNotificationEvent>[];
      backend.events.listen(events.add);

      await backend.schedule(
        fireAtEpochMs: clock.now,
        title: 'racing',
        body: '',
        sound: false,
      );
      await _flush();
      expect(platform.systemCalls, isEmpty);
      await backend.cancel();
      pendingWorker.complete();
      await _flush();
      expect(platform.systemCalls, isEmpty);
      expect(events, isEmpty);
    },
  );

  test(
    'replacement suppresses the old notification waiting for a worker',
    () async {
      platform.hidden = true;
      platform.permissionValue = 'granted';
      final pendingWorker = Completer<void>();
      platform.beforeSystemShow = pendingWorker;

      await backend.schedule(
        fireAtEpochMs: clock.now,
        title: 'old',
        body: '',
        sound: false,
      );
      await _flush();
      await backend.schedule(
        fireAtEpochMs: clock.now + 1000,
        title: 'new',
        body: '',
        sound: false,
      );
      pendingWorker.complete();
      await _flush();
      expect(platform.systemCalls, isEmpty);
    },
  );

  test('turning sound off wins an in-flight audio unlock', () async {
    final unlock = Completer<bool>();
    platform.unlockCompleter = unlock;
    final enabling = backend.setSoundEnabled(true);
    expect(backend.soundEnabled, isTrue);
    await backend.setSoundEnabled(false);
    unlock.complete(true);
    expect(await enabling, isFalse);
    expect(backend.soundEnabled, isFalse);
    platform.soundIsReady = true;
    await backend.showImmediate(title: 'still off', body: '', sound: true);
    expect(platform.toneCount, 0);
  });

  test(
    'late preference restoration cannot override an explicit choice',
    () async {
      await backend.setSoundEnabled(false);
      backend.restoreSoundEnabled(true);
      expect(backend.soundEnabled, isFalse);
    },
  );

  test(
    'permission errors degrade safely and nudge deduplication expires',
    () async {
      platform.permissionError = true;
      expect(await backend.requestPermissionFromUserGesture(), isFalse);

      final events = <BrowserNotificationEvent>[];
      backend.events.listen(events.add);
      await backend.showImmediate(title: 'same', body: '', sound: false);
      await backend.showImmediate(title: 'same', body: '', sound: false);
      expect(events, hasLength(1));
      clock.now += 1000;
      await backend.showImmediate(title: 'same', body: '', sound: false);
      expect(events, hasLength(2));
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _FakeClock {
  _FakeClock(this.now);
  int now;
  int call() => now;
}

class _FakeTimers {
  final List<_FakeTimer> all = [];
  Iterable<_FakeTimer> get active =>
      all.where((timer) => !timer.cancelled && !timer.fired);

  Object create(Duration delay, void Function() callback) {
    final timer = _FakeTimer(delay, callback);
    all.add(timer);
    return timer;
  }

  void cancel(Object timer) => (timer as _FakeTimer).cancelled = true;
}

class _FakeTimer {
  _FakeTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    forceFire();
  }

  void forceFire() {
    fired = true;
    callback();
  }
}

class _SystemCall {
  _SystemCall(this.title, this.silent, this.tag);
  final String title;
  final bool silent;
  final String tag;
}

class _FakePlatform implements BrowserNotificationPlatform {
  bool systemSupported = true;
  String permissionValue = 'default';
  bool hidden = false;
  bool soundIsReady = false;
  bool systemResult = true;
  bool permissionError = false;
  int toneCount = 0;
  int unlockCalls = 0;
  Completer<bool>? unlockCompleter;
  Completer<void>? beforeSystemShow;
  final List<_SystemCall> systemCalls = [];
  final Set<String> fired = {};

  @override
  bool get systemNotificationsSupported => systemSupported;
  @override
  String get permission => permissionValue;
  @override
  bool get pageHidden => hidden;
  @override
  bool get soundReady => soundIsReady;

  @override
  Future<String> requestPermission() async {
    if (permissionError) throw StateError('permission');
    return permissionValue;
  }

  @override
  Future<bool> unlockSound() async {
    unlockCalls += 1;
    final result = unlockCompleter == null
        ? true
        : await unlockCompleter!.future;
    soundIsReady = result;
    return result;
  }

  @override
  bool playTone() {
    toneCount += 1;
    return true;
  }

  @override
  Future<bool> showSystemNotification({
    required String title,
    required String body,
    required bool silent,
    required String tag,
    required bool Function() isCurrent,
  }) async {
    if (beforeSystemShow != null) await beforeSystemShow!.future;
    if (!isCurrent()) return false;
    systemCalls.add(_SystemCall(title, silent, tag));
    return systemResult;
  }

  @override
  bool wasTimedNotificationFired(String key) => fired.contains(key);
  @override
  void markTimedNotificationFired(String key) => fired.add(key);
}
