import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/audio_background_session.dart';

void main() {
  tearDown(AudioBackgroundSession.resetForTest);

  test('two owners share one native start and last release stops it', () async {
    final backend = FakeAudioBackend();
    AudioBackgroundSession.configureForTest(backend);
    final first = Object();
    final second = Object();

    expect(await AudioBackgroundSession.acquire(first), isTrue);
    expect(await AudioBackgroundSession.acquire(second), isTrue);
    expect(backend.starts, 1);
    await AudioBackgroundSession.release(first);
    expect(backend.stops, 0);
    await AudioBackgroundSession.release(second);
    expect(backend.stops, 1);
  });

  test('release queued during delayed start stops after successful start', () async {
    final backend = FakeAudioBackend(delayedStart: true);
    AudioBackgroundSession.configureForTest(backend);
    final owner = Object();

    final acquire = AudioBackgroundSession.acquire(owner);
    await backend.startCalled.future;
    final release = AudioBackgroundSession.release(owner);
    backend.completeStart();
    expect(await acquire, isTrue);
    await release;
    expect(backend.starts, 1);
    expect(backend.stops, 1);
  });

  test('failed start does not own the lease and can retry', () async {
    final backend = FakeAudioBackend(failFirstStart: true);
    AudioBackgroundSession.configureForTest(backend);
    final owner = Object();

    expect(await AudioBackgroundSession.acquire(owner), isFalse);
    expect(AudioBackgroundSession.activeLeases, 0);
    expect(await AudioBackgroundSession.acquire(owner), isTrue);
    await AudioBackgroundSession.release(owner);
    expect(backend.starts, 2);
    expect(backend.stops, 1);
  });

  test('failed final stop keeps ownership for a later retry', () async {
    final backend = FakeAudioBackend(failFirstStop: true);
    AudioBackgroundSession.configureForTest(backend);
    final owner = Object();

    expect(await AudioBackgroundSession.acquire(owner), isTrue);
    expect(await AudioBackgroundSession.release(owner), isFalse);
    expect(AudioBackgroundSession.activeLeases, 1);
    expect(await AudioBackgroundSession.release(owner), isTrue);
    expect(AudioBackgroundSession.activeLeases, 0);
    expect(backend.stops, 2);
  });
}

class FakeAudioBackend implements AudioBackgroundBackend {
  FakeAudioBackend({
    this.delayedStart = false,
    this.failFirstStart = false,
    this.failFirstStop = false,
  });

  final bool delayedStart;
  final bool failFirstStart;
  final bool failFirstStop;
  int starts = 0;
  int stops = 0;
  Completer<void>? _startCompleter;
  final startCalled = Completer<void>();

  @override
  Future<void> start() {
    starts += 1;
    if (failFirstStart && starts == 1) return Future<void>.error(StateError('start failed'));
    if (!delayedStart) return Future<void>.value();
    _startCompleter = Completer<void>();
    startCalled.complete();
    return _startCompleter!.future;
  }

  void completeStart() => _startCompleter!.complete();

  @override
  Future<void> stop() async {
    stops += 1;
    if (failFirstStop && stops == 1) throw StateError('stop failed');
  }
}
