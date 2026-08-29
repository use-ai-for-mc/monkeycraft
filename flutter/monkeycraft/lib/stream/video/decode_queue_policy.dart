enum DecodeAction { decode, drop, waitForKey, resetAndWaitForKey }

class DecodeQueuePolicy {
  static const int maxQueueSize = 3;
  static const int dropLimitBeforeReset = 12;

  final int maxQueue;
  final int dropLimit;

  const DecodeQueuePolicy({
    this.maxQueue = maxQueueSize,
    this.dropLimit = dropLimitBeforeReset,
  });

  DecodeAction decide({
    required bool isKey,
    required bool waitingForKey,
    required int queueSize,
    required int consecutiveDrops,
  }) {
    if (waitingForKey && !isKey) {
      return DecodeAction.waitForKey;
    }
    if (queueSize >= maxQueue) {
      if (isKey) {
        return DecodeAction.resetAndWaitForKey;
      }
      if (consecutiveDrops + 1 >= dropLimit) {
        return DecodeAction.resetAndWaitForKey;
      }
      return DecodeAction.drop;
    }
    return DecodeAction.decode;
  }
}
