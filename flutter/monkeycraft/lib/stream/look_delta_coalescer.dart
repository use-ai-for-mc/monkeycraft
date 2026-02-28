import 'dart:async';
import 'dart:ui';

typedef LookDeltaSink = void Function(double yawDelta, double pitchDelta);

class LookDeltaCoalescer {
  final LookDeltaSink onFlush;
  final Duration interval;

  Timer? _timer;
  double _yaw = 0;
  double _pitch = 0;

  LookDeltaCoalescer({
    required this.onFlush,
    this.interval = const Duration(milliseconds: 16),
  });

  void start() {
    _timer ??= Timer.periodic(interval, (_) => flush());
  }

  void stop({bool flushPending = false}) {
    if (flushPending) flush();
    _timer?.cancel();
    _timer = null;
    _yaw = 0;
    _pitch = 0;
  }

  void add({required double yaw, required double pitch}) {
    _yaw += yaw;
    _pitch += pitch;
  }

  void flush() {
    if (_yaw == 0 && _pitch == 0) return;
    final yaw = _yaw;
    final pitch = _pitch;
    _yaw = 0;
    _pitch = 0;
    onFlush(yaw, pitch);
  }
}

bool isPointExcluded(Offset position, List<Rect> excludedRegions) {
  for (final rect in excludedRegions) {
    if (rect.contains(position)) return true;
  }
  return false;
}
