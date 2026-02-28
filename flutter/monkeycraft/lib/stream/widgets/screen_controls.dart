import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';

enum ClickMode { left, right, hover }

class ScreenTouchHandler extends StatelessWidget {
  final StreamProxy proxy;
  final ClickMode clickMode;
  final bool shiftActive;
  final Rect videoDisplayRect;

  const ScreenTouchHandler({
    super.key,
    required this.proxy,
    required this.clickMode,
    required this.shiftActive,
    required this.videoDisplayRect,
  });

  void _handlePosition(Offset globalPos) {
    if (videoDisplayRect == Rect.zero) return;

    final localX = globalPos.dx - videoDisplayRect.left;
    final localY = globalPos.dy - videoDisplayRect.top;

    if (localX < 0 ||
        localX > videoDisplayRect.width ||
        localY < 0 ||
        localY > videoDisplayRect.height) {
      return;
    }

    final normX = (localX / videoDisplayRect.width).clamp(0.0, 1.0);
    final normY = (localY / videoDisplayRect.height).clamp(0.0, 1.0);

    if (clickMode == ClickMode.hover) {
      proxy.sendScreenHover(normX, normY);
    } else {
      proxy.sendScreenClick(clickMode == ClickMode.left ? 0 : 1, normX, normY);
    }
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => _handlePosition(details.globalPosition),
      onPanUpdate: (details) {
        if (clickMode == ClickMode.hover) {
          _handlePosition(details.globalPosition);
        }
      },
      child: const SizedBox.expand(),
    );
  }
}

const _kPaletteBackground = Color(0xB3000000);
const _kButtonActive = Color(0xFF2196F3);
const _kButtonInactive = Color(0xFF757575);
const _kEscButtonColor = Color(0xFFE53935);
const kToggleSize = 48.0;
const kButtonHeight = 44.0;
const kPalettePadding = 8.0;
const kPaletteBorderRadius = 12.0;
const kPaletteWidth = 108.0;
const kPaletteGap = 8.0;

class SmartPalettePosition extends StatelessWidget {
  final Offset togglePosition;
  final double toggleSize;
  final Size screenSize;
  final EdgeInsets safePadding;
  final Widget child;

  const SmartPalettePosition({
    super.key,
    required this.togglePosition,
    required this.toggleSize,
    required this.screenSize,
    required this.safePadding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final paletteHeight = kButtonHeight * 3 + kPalettePadding * 2 + 8;
    final preferredLeft =
        togglePosition.dx + toggleSize / 2 - kPaletteWidth / 2;
    final preferredTop = togglePosition.dy + toggleSize + kPaletteGap;

    final minLeft = safePadding.left;
    final maxLeft = screenSize.width - kPaletteWidth - safePadding.right;
    final minTop = safePadding.top;
    final maxTop = screenSize.height - paletteHeight - safePadding.bottom;

    final actualLeft = preferredLeft.clamp(minLeft, maxLeft);
    var actualTop = preferredTop;

    if (actualTop > maxTop) {
      actualTop = togglePosition.dy - paletteHeight - kPaletteGap;
      actualTop = actualTop.clamp(minTop, maxTop);
    }

    return Positioned(left: actualLeft, top: actualTop, child: child);
  }
}

class ScreenControlToggle extends StatefulWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final Offset position;
  final ValueChanged<Offset> onPositionChanged;
  final Size screenSize;
  final EdgeInsets safePadding;

  const ScreenControlToggle({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.position,
    required this.onPositionChanged,
    required this.screenSize,
    required this.safePadding,
  });

  @override
  State<ScreenControlToggle> createState() => _ScreenControlToggleState();
}

class _ScreenControlToggleState extends State<ScreenControlToggle> {
  late Offset _position;

  Offset get _defaultPosition => Offset(
    widget.screenSize.width - kToggleSize - widget.safePadding.right - 20,
    widget.safePadding.top + 80,
  );

  @override
  void initState() {
    super.initState();
    _position =
        widget.position == const Offset(double.infinity, double.infinity)
        ? _defaultPosition
        : widget.position;
    if (widget.position == const Offset(double.infinity, double.infinity)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onPositionChanged(_position);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ScreenControlToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position &&
        widget.position != const Offset(double.infinity, double.infinity)) {
      _position = widget.position;
    }
  }

  void _updatePosition(Offset newPos) {
    final constrainedX = newPos.dx.clamp(
      widget.safePadding.left,
      widget.screenSize.width - kToggleSize - widget.safePadding.right,
    );
    final constrainedY = newPos.dy.clamp(
      widget.safePadding.top,
      widget.screenSize.height - kToggleSize - widget.safePadding.bottom,
    );
    final constrained = Offset(constrainedX, constrainedY);
    if (constrained != _position) {
      setState(() => _position = constrained);
      widget.onPositionChanged(constrained);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) {},
        onPanUpdate: (details) => _updatePosition(_position + details.delta),
        onPanEnd: (_) {},
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: kToggleSize,
          height: kToggleSize,
          decoration: BoxDecoration(
            color: _kPaletteBackground,
            borderRadius: BorderRadius.circular(kToggleSize / 2),
            border: Border.all(
              color: widget.expanded ? _kButtonActive : Colors.white24,
              width: widget.expanded ? 2 : 1,
            ),
          ),
          child: Icon(
            widget.expanded ? Icons.close : Icons.control_camera,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class ScreenControlPalette extends StatelessWidget {
  final VoidCallback onEsc;
  final bool shiftActive;
  final VoidCallback onShiftToggle;
  final ClickMode clickMode;
  final ValueChanged<ClickMode> onClickModeChange;

  const ScreenControlPalette({
    super.key,
    required this.onEsc,
    required this.shiftActive,
    required this.onShiftToggle,
    required this.clickMode,
    required this.onClickModeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPaletteWidth,
      decoration: BoxDecoration(
        color: _kPaletteBackground,
        borderRadius: BorderRadius.circular(kPaletteBorderRadius),
      ),
      padding: const EdgeInsets.all(kPalettePadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(label: 'ESC', color: _kEscButtonColor, onPressed: onEsc),
          const SizedBox(height: 4),
          _buildButton(
            label: '⇧',
            color: shiftActive ? _kButtonActive : null,
            onPressed: onShiftToggle,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildModeButton('L', ClickMode.left),
              _buildModeButton('R', ClickMode.right),
              _buildModeButton('H', ClickMode.hover),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    Color? color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: kButtonHeight,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: color ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: color ?? Colors.white24),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(String label, ClickMode mode) {
    final isActive = clickMode == mode;
    return GestureDetector(
      onTap: () => onClickModeChange(mode),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isActive ? _kButtonActive : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? _kButtonActive : _kButtonInactive,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
