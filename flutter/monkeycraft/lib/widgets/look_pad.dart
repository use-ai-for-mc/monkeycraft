import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:monkeycraft_client/services/look_delta_coalescer.dart';

typedef LookDeltaSender = void Function(double yawDelta, double pitchDelta);
typedef TapSender = void Function(Offset localPosition);
typedef LongPressSender = void Function(Offset localPosition);

class LookPad extends StatefulWidget {
  final List<Rect> excludedRegions;
  final double sensitivityX;
  final double sensitivityY;
  final bool invertY;
  final LookDeltaSender onDelta;
  final TapSender? onTap;
  final LongPressSender? onLongPress;

  const LookPad({
    super.key,
    required this.excludedRegions,
    required this.onDelta,
    this.sensitivityX = 0.12,
    this.sensitivityY = 0.12,
    this.invertY = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<LookPad> createState() => _LookPadState();
}

class _LookPadState extends State<LookPad> {
  int? _pointerId;
  Offset? _last;
  Offset? _downAt;
  DateTime? _downTime;
  double _maxMoveSq = 0;
  LookDeltaCoalescer? _coalescer;

  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  void _startCoalescer() {
    _coalescer ??= LookDeltaCoalescer(onFlush: widget.onDelta);
    _coalescer!.start();
  }

  void _stopCoalescer() {
    _coalescer?.stop();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _stopCoalescer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointerId != null) return;
        if (isPointExcluded(event.localPosition, widget.excludedRegions)) return;
        _pointerId = event.pointer;
        _last = event.localPosition;
        _downAt = event.localPosition;
        _downTime = DateTime.now();
        _maxMoveSq = 0;
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 500), () {
          _longPressTriggered = true;
          widget.onLongPress?.call(event.localPosition);
        });
        _startCoalescer();
      },
      onPointerMove: (event) {
        if (_pointerId != event.pointer) return;
        final last = _last;
        if (last == null) return;
        final current = event.localPosition;
        final dx = current.dx - last.dx;
        final dy = current.dy - last.dy;
        _last = current;
        final downAt = _downAt;
        if (downAt != null) {
          final mx = current.dx - downAt.dx;
          final my = current.dy - downAt.dy;
          final d2 = (mx * mx) + (my * my);
          if (d2 > _maxMoveSq) _maxMoveSq = d2;
          if (_maxMoveSq > 100) {
            _longPressTimer?.cancel();
          }
        }

        final yaw = dx * widget.sensitivityX;
        final pitchRaw = dy * widget.sensitivityY;
        final pitch = widget.invertY ? pitchRaw : -pitchRaw;
        _coalescer?.add(yaw: yaw, pitch: pitch);
      },
      onPointerUp: (event) {
        _longPressTimer?.cancel();
        if (_pointerId != event.pointer) return;
        final downTime = _downTime;
        final downAt = _downAt;
        if (downTime != null && downAt != null && widget.onTap != null && !_longPressTriggered) {
          final elapsed = DateTime.now().difference(downTime);
          const maxMove = 10.0;
          final maxMoveSq = maxMove * maxMove;
          if (elapsed <= const Duration(milliseconds: 250) && _maxMoveSq <= maxMoveSq) {
            widget.onTap?.call(event.localPosition);
          }
        }
        _pointerId = null;
        _last = null;
        _downAt = null;
        _downTime = null;
        _maxMoveSq = 0;
        _coalescer?.flush();
        _stopCoalescer();
      },
      onPointerCancel: (event) {
        _longPressTimer?.cancel();
        if (_pointerId != event.pointer) return;
        _pointerId = null;
        _last = null;
        _downAt = null;
        _downTime = null;
        _maxMoveSq = 0;
        _coalescer?.flush();
        _stopCoalescer();
      },
      child: const SizedBox.expand(),
    );
  }
}
