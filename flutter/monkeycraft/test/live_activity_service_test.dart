import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/live_activity_service_io.dart';

class _FakeBackend implements LiveActivityBackend {
  final calls = <String>[];
  final payloads = <Map<String, dynamic>>[];
  Completer<void>? createGate;
  Completer<void>? createStarted;
  bool active = false;
  bool failNextCreate = false;

  @override
  Future<void> clear() async {
    calls.add('clear');
    active = false;
  }

  @override
  Future<void> createOrUpdate(String id, Map<String, dynamic> payload) async {
    calls.add('create');
    payloads.add(Map.of(payload));
    createStarted?.complete();
    await createGate?.future;
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('create failed');
    }
    active = true;
  }

  @override
  Future<void> end(String id) async {
    calls.add('end');
    active = false;
  }

  @override
  Future<bool> initialize(String appGroupId) async {
    calls.add('initialize');
    return true;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> payload) async {
    calls.add('update');
    payloads.add(Map.of(payload));
  }
}

LiveActivityService _service(_FakeBackend backend) {
  return LiveActivityService(
    backend: backend,
    now: () => DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  test('queues a countdown received during initialization', () async {
    final backend = _FakeBackend();
    final service = _service(backend);

    final initializing = service.init();
    final starting = service.startCountdown(fireAtEpochMs: 2000, title: 'A');
    await Future.wait([initializing, starting]);

    expect(backend.calls, ['initialize', 'clear', 'create']);
  });

  test('updates same deadline when countdown content changes', () async {
    final backend = _FakeBackend();
    final service = _service(backend);
    await service.init();

    await service.startCountdown(fireAtEpochMs: 2000, title: 'A', body: 'one');
    await service.startCountdown(fireAtEpochMs: 2000, title: 'B', body: 'two');
    await service.startCountdown(fireAtEpochMs: 2000, title: 'B', body: 'two');

    expect(backend.calls, ['initialize', 'clear', 'create', 'create']);
    expect(backend.payloads.last['title'], 'B');
  });

  test(
    'serializes create before cancel so an activity cannot revive',
    () async {
      final backend = _FakeBackend()
        ..createGate = Completer<void>()
        ..createStarted = Completer<void>();
      final service = _service(backend);
      await service.init();

      final creating = service.startCountdown(fireAtEpochMs: 2000, title: 'A');
      final cancelling = service.cancel();
      await backend.createStarted!.future;
      expect(backend.calls, ['initialize', 'clear', 'create']);

      backend.createGate!.complete();
      await Future.wait([creating, cancelling]);

      expect(backend.calls, ['initialize', 'clear', 'create', 'end']);
      expect(backend.active, isFalse);
    },
  );

  test('retries a failed create with the same countdown payload', () async {
    final backend = _FakeBackend()..failNextCreate = true;
    final service = _service(backend);
    await service.init();

    await service.startCountdown(fireAtEpochMs: 2000, title: 'A');
    await service.startCountdown(fireAtEpochMs: 2000, title: 'A');

    expect(backend.calls, ['initialize', 'clear', 'create', 'create']);
    expect(backend.active, isTrue);
  });

  test(
    'does not clear an active countdown on repeated initialization',
    () async {
      final backend = _FakeBackend();
      final service = _service(backend);
      await service.init();
      await service.startCountdown(fireAtEpochMs: 2000, title: 'A');
      await service.init();

      expect(backend.calls, ['initialize', 'clear', 'create']);
      expect(backend.active, isTrue);
    },
  );
}
