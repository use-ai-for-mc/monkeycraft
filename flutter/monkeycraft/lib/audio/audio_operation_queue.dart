import 'dart:async';

class AudioOperationQueue {
  Future<void> _tail = Future.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (error, stackTrace) {});
    return result;
  }
}
