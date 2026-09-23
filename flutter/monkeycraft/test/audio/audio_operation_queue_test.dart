import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/audio_operation_queue.dart';

void main() {
  test(
    'runs overlapping operations one at a time in submission order',
    () async {
      final queue = AudioOperationQueue();
      final gate = Completer<void>();
      final started = <String>[];
      var running = 0;
      var maxRunning = 0;

      final first = queue.enqueue(() async {
        started.add('first');
        running++;
        maxRunning = maxRunning < running ? running : maxRunning;
        await gate.future;
        running--;
      });
      final second = queue.enqueue(() async {
        started.add('second');
        running++;
        maxRunning = maxRunning < running ? running : maxRunning;
        running--;
      });

      await Future<void>.delayed(Duration.zero);
      expect(started, ['first']);
      gate.complete();
      await Future.wait([first, second]);

      expect(started, ['first', 'second']);
      expect(maxRunning, 1);
    },
  );

  test('continues after a failed operation', () async {
    final queue = AudioOperationQueue();
    final failed = queue.enqueue<void>(() async {
      throw StateError('expected');
    });
    var ranAfterFailure = false;
    final next = queue.enqueue(() async {
      ranAfterFailure = true;
    });

    await expectLater(failed, throwsStateError);
    await next;

    expect(ranAfterFailure, isTrue);
  });
}
