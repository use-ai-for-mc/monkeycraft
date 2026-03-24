import 'dart:math' as math;

import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final double size;
  final ValueChanged<Offset> onChanged;

  const VirtualJoystick({
    super.key,
    required this.size,
    required this.onChanged,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knob = Offset.zero;

  double get _radius => widget.size / 2;
  double get _knobRadius => widget.size * 0.18;

  void _update(Offset localPosition) {
    final center = Offset(_radius, _radius);
    final delta = localPosition - center;
    final maxDistance = _radius - _knobRadius - 4;

    final distance = delta.distance;
    final clamped = distance <= maxDistance || distance == 0
        ? delta
        : delta * (maxDistance / distance);

    final normalized = Offset(
      (clamped.dx / maxDistance).clamp(-1.0, 1.0),
      (clamped.dy / maxDistance).clamp(-1.0, 1.0),
    );

    setState(() => _knob = clamped);
    widget.onChanged(normalized);
  }

  void _reset() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Movement joystick',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _update(d.localPosition),
          onPanUpdate: (d) => _update(d.localPosition),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: CustomPaint(
            painter: _JoystickPainter(
              knobOffset: _knob,
              knobRadius: _knobRadius,
            ),
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset knobOffset;
  final double knobRadius;

  _JoystickPainter({
    required this.knobOffset,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final knobPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, basePaint);
    canvas.drawCircle(center, radius - 1.5, ringPaint);

    final knobCenter = center + knobOffset;
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.knobOffset != knobOffset || oldDelegate.knobRadius != knobRadius;
  }
}

