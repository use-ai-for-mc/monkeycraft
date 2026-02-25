import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
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
  final Duration longPressDelay;
  final double moveThreshold;

  const LookPad({
    super.key,
    required this.excludedRegions,
    required this.onDelta,
    this.sensitivityX = 0.12,
    this.sensitivityY = 0.12,
    this.invertY = false,
    this.onTap,
    this.onLongPress,
    this.longPressDelay = const Duration(milliseconds: 200),
    this.moveThreshold = 800,
  });

  @override
  State<LookPad> createState() => _LookPadState();
}

class _LookPadState extends State<LookPad> {
  int? _dragPointerId;
  Offset? _last;
  LookDeltaCoalescer? _coalescer;

  Offset? _tapDownPos;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _tapCancelled = false;

  void _startCoalescer() {
    _coalescer ??= LookDeltaCoalescer(onFlush: widget.onDelta);
    _coalescer!.start();
  }

  void _stopCoalescer() {
    _coalescer?.stop();
  }

  void _cancelTap() {
    _longPressTimer?.cancel();
    _tapDownPos = null;
    _tapCancelled = true;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _stopCoalescer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        if (isPointExcluded(details.localPosition, widget.excludedRegions)) {
          return;
        }
        _tapDownPos = details.localPosition;
        _tapCancelled = false;
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(widget.longPressDelay, () {
          if (!_tapCancelled && _tapDownPos != null) {
            _longPressTriggered = true;
            HapticFeedback.heavyImpact();
            widget.onLongPress?.call(_tapDownPos!);
          }
        });
      },
      onTapUp: (details) {
        if (_tapCancelled || _longPressTriggered) {
          _cancelTap();
          return;
        }
        HapticFeedback.lightImpact();
        widget.onTap?.call(details.localPosition);
        _cancelTap();
      },
      onTapCancel: () {
        _cancelTap();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (_dragPointerId != null) return;
          if (isPointExcluded(event.localPosition, widget.excludedRegions)) {
            return;
          }
          _dragPointerId = event.pointer;
          _last = event.localPosition;
          _startCoalescer();
        },
        onPointerMove: (event) {
          if (_dragPointerId != event.pointer) return;
          final last = _last;
          if (last == null) return;
          final current = event.localPosition;
          final dx = current.dx - last.dx;
          final dy = current.dy - last.dy;
          _last = current;

          final yaw = dx * widget.sensitivityX;
          final pitchRaw = dy * widget.sensitivityY;
          final pitch = widget.invertY ? pitchRaw : -pitchRaw;
          _coalescer?.add(yaw: yaw, pitch: pitch);

          if (_tapDownPos != null && !_longPressTriggered) {
            final moveSq =
                (current.dx - _tapDownPos!.dx) *
                    (current.dx - _tapDownPos!.dx) +
                (current.dy - _tapDownPos!.dy) * (current.dy - _tapDownPos!.dy);
            if (moveSq > widget.moveThreshold) {
              _cancelTap();
            }
          }
        },
        onPointerUp: (event) {
          if (_dragPointerId != event.pointer) return;
          _dragPointerId = null;
          _last = null;
          _coalescer?.flush();
          _stopCoalescer();
        },
        onPointerCancel: (event) {
          if (_dragPointerId != event.pointer) return;
          _dragPointerId = null;
          _last = null;
          _coalescer?.flush();
          _stopCoalescer();
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
