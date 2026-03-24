import 'package:flutter/material.dart';

class HotbarToggleButton extends StatefulWidget {
  final double size;
  final bool expanded;
  final VoidCallback onPressed;

  const HotbarToggleButton({
    super.key,
    required this.size,
    required this.expanded,
    required this.onPressed,
  });

  @override
  State<HotbarToggleButton> createState() => _HotbarToggleButtonState();
}

class _HotbarToggleButtonState extends State<HotbarToggleButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.expanded || _pressed;
    return Semantics(
      label: 'Hotbar selector',
      button: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: TextButton(
            onPressed: widget.onPressed,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(
                alpha: active ? 0.35 : 0.22,
              ),
            ),
            child: const Text(
              '1–9',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class HotbarGrid extends StatelessWidget {
  final double buttonSize;
  final double gap;
  final int selectedSlot;
  final ValueChanged<int> onSelect;
  final bool singleRow;
  final void Function(String key)? onKey;

  const HotbarGrid({
    super.key,
    required this.buttonSize,
    required this.gap,
    required this.selectedSlot,
    required this.onSelect,
    this.singleRow = false,
    this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: singleRow ? _singleRow() : _grid(),
      ),
    );
  }

  Widget _singleRow() {
    final hotbar = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell(0),
        SizedBox(width: gap),
        _cell(1),
        SizedBox(width: gap),
        _cell(2),
        SizedBox(width: gap),
        _cell(3),
        SizedBox(width: gap),
        _cell(4),
        SizedBox(width: gap),
        _cell(5),
        SizedBox(width: gap),
        _cell(6),
        SizedBox(width: gap),
        _cell(7),
        SizedBox(width: gap),
        _cell(8),
      ],
    );

    if (onKey == null) return hotbar;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hotbar,
        SizedBox(width: gap),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _keyCell('Q'),
            SizedBox(height: gap),
            _keyCell('E'),
            SizedBox(height: gap),
            _keyCell('F'),
          ],
        ),
      ],
    );
  }

  Widget _grid() {
    final hotbar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(0, 1, 2),
        SizedBox(height: gap),
        _row(3, 4, 5),
        SizedBox(height: gap),
        _row(6, 7, 8),
      ],
    );

    if (onKey == null) return hotbar;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hotbar,
        SizedBox(width: gap),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _keyCell('Q'),
            SizedBox(height: gap),
            _keyCell('E'),
            SizedBox(height: gap),
            _keyCell('F'),
          ],
        ),
      ],
    );
  }

  Widget _row(int a, int b, int c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell(a),
        SizedBox(width: gap),
        _cell(b),
        SizedBox(width: gap),
        _cell(c),
      ],
    );
  }

  Widget _cell(int slot) {
    final selected = slot == selectedSlot;
    return Semantics(
      label: 'Hotbar slot ${slot + 1}',
      button: true,
      selected: selected,
      child: SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: TextButton(
          onPressed: () => onSelect(slot),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(
              alpha: selected ? 0.38 : 0.18,
            ),
          ),
          child: Text(
            '${slot + 1}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _keyCell(String key) {
    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: TextButton(
        onPressed: onKey != null ? () => onKey!(key) : null,
        onLongPress: onKey != null ? () => onKey!(key) : null,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.18),
        ),
        child: Text(key, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
