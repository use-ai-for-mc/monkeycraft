import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/stream/look_delta_coalescer.dart';
import 'package:monkeycraft_client/stream/pointer_kind.dart';

typedef LookDeltaSender = void Function(double yawDelta, double pitchDelta);
typedef GameClickSender = void Function(int button);
typedef PointerKindSender = void Function(PointerDeviceKind kind, bool down);

class LookPad extends StatefulWidget {
  final List<Rect> excludedRegions;
  final double sensitivityX;
  final double sensitivityY;
  final bool invertY;
  final LookDeltaSender onDelta;
  final GameClickSender? onClick;
  final PointerKindSender? onPointerKind;
  final Duration longPressDelay;
  final double moveThreshold;

  const LookPad({
    super.key,
    required this.excludedRegions,
    required this.onDelta,
    this.sensitivityX = 0.12,
    this.sensitivityY = 0.12,
    this.invertY = false,
    this.onClick,
    this.onPointerKind,
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

  Offset? _downPos;
  int _downButton = 0;
  bool _mouseLike = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _clickCancelled = false;
  bool _lookStarted = false;

  void _startCoalescer() {
    _coalescer ??= LookDeltaCoalescer(onFlush: widget.onDelta);
    _coalescer!.start();
  }

  void _stopCoalescer() {
    _coalescer?.stop();
  }

  void _cancelClick() {
    _longPressTimer?.cancel();
    _clickCancelled = true;
  }

  void _resetPointer() {
    _longPressTimer?.cancel();
    _dragPointerId = null;
    _last = null;
    _downPos = null;
    _longPressTriggered = false;
    _clickCancelled = false;
    _lookStarted = false;
    _coalescer?.flush();
    _stopCoalescer();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _stopCoalescer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Camera look pad',
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (_dragPointerId != null) return;
          if (isPointExcluded(event.localPosition, widget.excludedRegions)) {
            return;
          }
          _dragPointerId = event.pointer;
          _last = event.localPosition;
          _downPos = event.localPosition;
          _mouseLike = isMouseLike(event.kind);
          _downButton = mouseButtonIndex(event.buttons) ?? 0;
          _longPressTriggered = false;
          _clickCancelled = false;
          _lookStarted = false;
          _startCoalescer();
          widget.onPointerKind?.call(event.kind, true);
          _longPressTimer?.cancel();
          if (!_mouseLike) {
            _longPressTimer = Timer(widget.longPressDelay, () {
              if (!_clickCancelled && _downPos != null) {
                _longPressTriggered = true;
                HapticFeedback.heavyImpact();
                widget.onClick?.call(1);
              }
            });
          }
        },
        onPointerMove: (event) {
          if (_dragPointerId != event.pointer) return;
          final last = _last;
          final down = _downPos;
          if (last == null || down == null) return;
          final current = event.localPosition;
          final dx = current.dx - last.dx;
          final dy = current.dy - last.dy;
          _last = current;

          final moveSq =
              (current.dx - down.dx) * (current.dx - down.dx) +
              (current.dy - down.dy) * (current.dy - down.dy);
          final dragged = moveSq > widget.moveThreshold;

          if (dragged && !_clickCancelled) {
            _cancelClick();
          }

          final shouldLook = _mouseLike ? dragged || _lookStarted : true;
          if (shouldLook) {
            _lookStarted = true;
            final yaw = dx * widget.sensitivityX;
            final pitchRaw = dy * widget.sensitivityY;
            final pitch = widget.invertY ? pitchRaw : -pitchRaw;
            _coalescer?.add(yaw: yaw, pitch: pitch);
          }
        },
        onPointerUp: (event) {
          if (_dragPointerId != event.pointer) return;
          final sendClick =
              !_clickCancelled && !_longPressTriggered && _downPos != null;
          final button = _downButton;
          final kind = event.kind;
          _resetPointer();
          widget.onPointerKind?.call(kind, false);
          if (sendClick) {
            if (!_mouseLike) {
              HapticFeedback.lightImpact();
            }
            widget.onClick?.call(_mouseLike ? button : 0);
          }
        },
        onPointerCancel: (event) {
          if (_dragPointerId != event.pointer) return;
          final kind = event.kind;
          _resetPointer();
          widget.onPointerKind?.call(kind, false);
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
