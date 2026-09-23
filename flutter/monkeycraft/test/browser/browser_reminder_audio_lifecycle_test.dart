@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/browser_notification_backend_web.dart';
import 'package:web/web.dart' as web;

void main() {
  late bool hidden;
  late bool enabled;
  late bool gesture;
  late List<_FakeAudio> contexts;
  late WebBrowserNotificationPlatform platform;

  setUp(() {
    hidden = false;
    enabled = true;
    gesture = false;
    contexts = [];
    platform = WebBrowserNotificationPlatform(
      soundEnabled: () => enabled,
      pageHidden: () => hidden,
      createAudioContext: () {
        final audio = _FakeAudio(() => gesture);
        contexts.add(audio);
        return audio.context;
      },
    );
  });

  tearDown(() => platform.dispose());

  Future<void> unlock() async {
    gesture = true;
    expect(await platform.unlockSound(), isTrue);
    gesture = false;
  }

  void background() {
    hidden = true;
    web.document.dispatchEvent(web.Event('visibilitychange'));
  }

  void foreground() {
    hidden = false;
    web.document.dispatchEvent(web.Event('visibilitychange'));
  }

  test('retains gesture authorization across a lock interruption', () async {
    await unlock();
    final audio = contexts.single;
    background();
    audio.state = 'interrupted';
    expect(audio.closeCalls, 0);
    expect(platform.soundReady, isFalse);
    expect(platform.playTone(), isFalse);
    foreground();
    await Future<void>.delayed(Duration.zero);
    expect(contexts, hasLength(1));
    expect(platform.soundReady, isTrue);
    expect(audio.resumeCalls, 2);
    expect(audio.toneCalls, 0);
    expect(platform.playTone(), isTrue);
    expect(audio.toneCalls, 1);
  });

  test('automatic foreground recovery cannot create a new context', () async {
    web.window.dispatchEvent(web.Event('pageshow'));
    web.window.dispatchEvent(web.Event('focus'));
    expect(contexts, isEmpty);
    gesture = true;
    web.document.dispatchEvent(web.Event('pointerup'));
    await Future<void>.delayed(Duration.zero);
    gesture = false;
    expect(platform.soundReady, isTrue);
  });

  test('disabled sound prevents lifecycle and gesture recovery', () async {
    enabled = false;
    gesture = true;
    web.document.dispatchEvent(web.Event('pointerup'));
    expect(contexts, isEmpty);
    enabled = true;
    await unlock();
    final audio = contexts.single;
    background();
    audio.state = 'interrupted';
    enabled = false;
    foreground();
    web.document.dispatchEvent(web.Event('click'));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(audio.resumeCalls, 1);
    expect(platform.soundReady, isFalse);
    expect(audio.toneCalls, 0);
  });

  test('completion from before backgrounding cannot report success', () async {
    await unlock();
    final audio = contexts.single;
    audio.pendingResume = Completer<JSAny?>();
    final pending = platform.unlockSound();
    background();
    foreground();
    audio.pendingResume!.complete(null);
    expect(await pending, isFalse);
    expect(contexts, hasLength(1));
    expect(audio.closeCalls, 0);
  });

  test('page cache retains audio and disposal removes recovery work', () async {
    await unlock();
    web.window.dispatchEvent(web.Event('pagehide'));
    expect(platform.soundReady, isFalse);
    web.window.dispatchEvent(web.Event('pageshow'));
    await Future<void>.delayed(Duration.zero);
    expect(contexts, hasLength(1));
    expect(platform.soundReady, isTrue);
    final calls = contexts.single.resumeCalls;
    platform.dispose();
    web.window.dispatchEvent(web.Event('focus'));
    web.window.dispatchEvent(web.Event('pageshow'));
    web.document.dispatchEvent(web.Event('pointerup'));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(contexts, hasLength(1));
    expect(contexts.single.closeCalls, 1);
    expect(contexts.single.resumeCalls, calls);
    expect(platform.soundReady, isFalse);
    expect(await platform.unlockSound(), isFalse);
  });

  test(
    'repairs a running context with a frozen clock without replacing it',
    () async {
      await unlock();
      final audio = contexts.single;
      background();
      foreground();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(audio.suspendCalls, 1);
      expect(audio.resumeCalls, 3);
      expect(audio.closeCalls, 0);
      expect(contexts, hasLength(1));
      expect(audio.toneCalls, 0);
      expect(platform.soundReady, isTrue);
    },
  );

  test('does not reset an advancing audio clock', () async {
    await unlock();
    final audio = contexts.single;
    background();
    foreground();
    audio.time = 0.2;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(audio.suspendCalls, 0);
    expect(audio.resumeCalls, 2);
    expect(audio.toneCalls, 0);
  });

  test(
    'retries a late interruption without replaying an old reminder',
    () async {
      await unlock();
      final audio = contexts.single;
      background();
      foreground();
      audio.time = 0.2;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      audio.state = 'interrupted';
      expect(platform.playTone(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 750));
      expect(platform.soundReady, isTrue);
      expect(audio.toneCalls, 0);
      expect(audio.resumeCalls, 3);
    },
  );

  test('returning to background cancels recovery probes', () async {
    await unlock();
    final audio = contexts.single;
    background();
    foreground();
    background();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(audio.suspendCalls, 0);
    expect(audio.resumeCalls, 2);
    expect(audio.toneCalls, 0);
    expect(platform.soundReady, isFalse);
  });
}

class _FakeAudio {
  _FakeAudio(bool Function() gesture) {
    state = 'suspended';
    time = 0;
    object.setProperty('destination'.toJS, JSObject());
    object.setProperty(
      'resume'.toJS,
      (() {
        resumeCalls += 1;
        if (!authorized && !gesture()) {
          return Future<JSAny?>.error(StateError('User gesture required')).toJS;
        }
        authorized = true;
        state = 'running';
        return (pendingResume?.future ?? Future<JSAny?>.value(null)).toJS;
      }).toJS,
    );
    object.setProperty(
      'suspend'.toJS,
      (() {
        suspendCalls += 1;
        state = 'suspended';
        return Future<JSAny?>.value(null).toJS;
      }).toJS,
    );
    object.setProperty(
      'close'.toJS,
      (() {
        closeCalls += 1;
        state = 'closed';
        return Future<JSAny?>.value(null).toJS;
      }).toJS,
    );
    object.setProperty(
      'createOscillator'.toJS,
      (() {
        toneCalls += 1;
        final node = _node('frequency');
        node.setProperty('start'.toJS, (() {}).toJS);
        node.setProperty('stop'.toJS, ((JSNumber _) {}).toJS);
        return node;
      }).toJS,
    );
    object.setProperty('createGain'.toJS, (() => _node('gain')).toJS);
  }

  JSObject _node(String parameter) {
    final node = JSObject();
    node.setProperty(parameter.toJS, JSObject());
    node.setProperty('connect'.toJS, ((JSObject _) {}).toJS);
    return node;
  }

  final object = JSObject();
  bool authorized = false;
  int resumeCalls = 0;
  int suspendCalls = 0;
  int closeCalls = 0;
  int toneCalls = 0;
  Completer<JSAny?>? pendingResume;

  set state(String value) => object.setProperty('state'.toJS, value.toJS);
  set time(double value) => object.setProperty('currentTime'.toJS, value.toJS);
  web.AudioContext get context => object as web.AudioContext;
}
