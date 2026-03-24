import 'package:flutter/material.dart';

class ShiftButton extends StatefulWidget {
  final double size;
  final ValueChanged<bool> onChanged;

  const ShiftButton({
    super.key,
    required this.size,
    required this.onChanged,
  });

  @override
  State<ShiftButton> createState() => _ShiftButtonState();
}

class _ShiftButtonState extends State<ShiftButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sneak',
      button: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: _pressed ? 0.35 : 0.22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: const Center(
              child: Icon(Icons.arrow_downward, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

