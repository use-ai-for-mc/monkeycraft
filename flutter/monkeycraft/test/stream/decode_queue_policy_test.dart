import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/video/decode_queue_policy.dart';

void main() {
  const policy = DecodeQueuePolicy(maxQueue: 3, dropLimit: 4);

  test('decodes when the queue is small', () {
    expect(
      policy.decide(
        isKey: false,
        waitingForKey: false,
        queueSize: 1,
        consecutiveDrops: 0,
      ),
      DecodeAction.decode,
    );
  });

  test('ignores deltas until a key arrives', () {
    expect(
      policy.decide(
        isKey: false,
        waitingForKey: true,
        queueSize: 0,
        consecutiveDrops: 0,
      ),
      DecodeAction.waitForKey,
    );
    expect(
      policy.decide(
        isKey: true,
        waitingForKey: true,
        queueSize: 0,
        consecutiveDrops: 0,
      ),
      DecodeAction.decode,
    );
  });

  test('drops deltas when the queue is full', () {
    expect(
      policy.decide(
        isKey: false,
        waitingForKey: false,
        queueSize: 3,
        consecutiveDrops: 0,
      ),
      DecodeAction.drop,
    );
  });

  test('resets after too many consecutive drops', () {
    expect(
      policy.decide(
        isKey: false,
        waitingForKey: false,
        queueSize: 3,
        consecutiveDrops: 3,
      ),
      DecodeAction.resetAndWaitForKey,
    );
  });

  test('resets instead of queuing a key behind a full queue', () {
    expect(
      policy.decide(
        isKey: true,
        waitingForKey: false,
        queueSize: 3,
        consecutiveDrops: 0,
      ),
      DecodeAction.resetAndWaitForKey,
    );
  });
}
