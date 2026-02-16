import 'dart:ui';

typedef InputSender = void Function(String key, bool pressed);

class GameInputController {
  final InputSender _send;
  final double pressThreshold;
  final double releaseThreshold;

  int _xAxis = 0;
  int _yAxis = 0;

  bool _wDown = false;
  bool _aDown = false;
  bool _sDown = false;
  bool _dDown = false;
  bool _spaceDown = false;
  bool _shiftDown = false;

  GameInputController(
    this._send, {
    this.pressThreshold = 0.35,
    this.releaseThreshold = 0.25,
  });

  void updateMoveVector(Offset normalized) {
    final x = normalized.dx.clamp(-1.0, 1.0);
    final y = normalized.dy.clamp(-1.0, 1.0);

    _xAxis = _updateAxis(_xAxis, x);
    _yAxis = _updateAxis(_yAxis, y);

    _setKey('W', pressed: _yAxis == -1, current: _wDown, assign: (v) => _wDown = v);
    _setKey('S', pressed: _yAxis == 1, current: _sDown, assign: (v) => _sDown = v);
    _setKey('A', pressed: _xAxis == -1, current: _aDown, assign: (v) => _aDown = v);
    _setKey('D', pressed: _xAxis == 1, current: _dDown, assign: (v) => _dDown = v);
  }

  void setJumpPressed(bool pressed) {
    _setKey('SPACE', pressed: pressed, current: _spaceDown, assign: (v) => _spaceDown = v);
  }

  void setShiftPressed(bool pressed) {
    _setKey('SHIFT', pressed: pressed, current: _shiftDown, assign: (v) => _shiftDown = v);
  }

  void releaseAll() {
    _setKey('W', pressed: false, current: _wDown, assign: (v) => _wDown = v);
    _setKey('A', pressed: false, current: _aDown, assign: (v) => _aDown = v);
    _setKey('S', pressed: false, current: _sDown, assign: (v) => _sDown = v);
    _setKey('D', pressed: false, current: _dDown, assign: (v) => _dDown = v);
    _setKey('SPACE', pressed: false, current: _spaceDown, assign: (v) => _spaceDown = v);
    _setKey('SHIFT', pressed: false, current: _shiftDown, assign: (v) => _shiftDown = v);
    _xAxis = 0;
    _yAxis = 0;
  }

  int _updateAxis(int current, double value) {
    if (current == 0) {
      if (value <= -pressThreshold) return -1;
      if (value >= pressThreshold) return 1;
      return 0;
    }

    if (current == -1) {
      if (value <= -releaseThreshold) return -1;
      if (value >= pressThreshold) return 1;
      return 0;
    }

    if (current == 1) {
      if (value >= releaseThreshold) return 1;
      if (value <= -pressThreshold) return -1;
      return 0;
    }

    return 0;
  }

  void _setKey(
    String key, {
    required bool pressed,
    required bool current,
    required void Function(bool) assign,
  }) {
    if (pressed == current) return;
    assign(pressed);
    _send(key, pressed);
  }
}
