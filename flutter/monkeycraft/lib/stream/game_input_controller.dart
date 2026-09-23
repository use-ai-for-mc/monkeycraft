import 'package:flutter/services.dart';

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
  bool _qDown = false;
  bool _eDown = false;
  bool _fDown = false;
  bool _leftDown = false;
  bool _rightDown = false;
  bool _upDown = false;
  bool _downDown = false;

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

    _setKey(
      'W',
      pressed: _yAxis == -1,
      current: _wDown,
      assign: (v) => _wDown = v,
    );
    _setKey(
      'S',
      pressed: _yAxis == 1,
      current: _sDown,
      assign: (v) => _sDown = v,
    );
    _setKey(
      'A',
      pressed: _xAxis == -1,
      current: _aDown,
      assign: (v) => _aDown = v,
    );
    _setKey(
      'D',
      pressed: _xAxis == 1,
      current: _dDown,
      assign: (v) => _dDown = v,
    );
  }

  void setJumpPressed(bool pressed) {
    _setKey(
      'SPACE',
      pressed: pressed,
      current: _spaceDown,
      assign: (v) => _spaceDown = v,
    );
  }

  void setShiftPressed(bool pressed) {
    _setKey(
      'SHIFT',
      pressed: pressed,
      current: _shiftDown,
      assign: (v) => _shiftDown = v,
    );
  }

  bool handlePhysicalKey(String logicalKey, bool pressed) {
    switch (logicalKey) {
      case 'KeyW':
      case 'w':
      case 'W':
        _setKey(
          'W',
          pressed: pressed,
          current: _wDown,
          assign: (v) => _wDown = v,
        );
        return true;
      case 'KeyA':
      case 'a':
      case 'A':
        _setKey(
          'A',
          pressed: pressed,
          current: _aDown,
          assign: (v) => _aDown = v,
        );
        return true;
      case 'KeyS':
      case 's':
      case 'S':
        _setKey(
          'S',
          pressed: pressed,
          current: _sDown,
          assign: (v) => _sDown = v,
        );
        return true;
      case 'KeyD':
      case 'd':
      case 'D':
        _setKey(
          'D',
          pressed: pressed,
          current: _dDown,
          assign: (v) => _dDown = v,
        );
        return true;
      case 'Space':
      case ' ':
        setJumpPressed(pressed);
        return true;
      case 'ShiftLeft':
      case 'ShiftRight':
      case 'Shift':
        setShiftPressed(pressed);
        return true;
      case 'KeyQ':
      case 'q':
      case 'Q':
        _setKey(
          'Q',
          pressed: pressed,
          current: _qDown,
          assign: (v) => _qDown = v,
        );
        return true;
      case 'KeyE':
      case 'e':
      case 'E':
        _setKey(
          'E',
          pressed: pressed,
          current: _eDown,
          assign: (v) => _eDown = v,
        );
        return true;
      case 'KeyF':
      case 'f':
      case 'F':
        _setKey(
          'F',
          pressed: pressed,
          current: _fDown,
          assign: (v) => _fDown = v,
        );
        return true;
      case 'ArrowLeft':
      case 'Left':
        _setKey(
          'LEFT',
          pressed: pressed,
          current: _leftDown,
          assign: (v) => _leftDown = v,
        );
        return true;
      case 'ArrowRight':
      case 'Right':
        _setKey(
          'RIGHT',
          pressed: pressed,
          current: _rightDown,
          assign: (v) => _rightDown = v,
        );
        return true;
      case 'ArrowUp':
      case 'Up':
        _setKey(
          'UP',
          pressed: pressed,
          current: _upDown,
          assign: (v) => _upDown = v,
        );
        return true;
      case 'ArrowDown':
      case 'Down':
        _setKey(
          'DOWN',
          pressed: pressed,
          current: _downDown,
          assign: (v) => _downDown = v,
        );
        return true;
      default:
        return false;
    }
  }

  bool handleFlutterKey(
    PhysicalKeyboardKey physicalKey,
    LogicalKeyboardKey logicalKey,
    bool pressed,
  ) {
    final key = _mappedFlutterKey(physicalKey, logicalKey);
    return key != null && _setMappedKey(key, pressed);
  }

  void releaseAll() {
    _setKey('W', pressed: false, current: _wDown, assign: (v) => _wDown = v);
    _setKey('A', pressed: false, current: _aDown, assign: (v) => _aDown = v);
    _setKey('S', pressed: false, current: _sDown, assign: (v) => _sDown = v);
    _setKey('D', pressed: false, current: _dDown, assign: (v) => _dDown = v);
    _setKey(
      'SPACE',
      pressed: false,
      current: _spaceDown,
      assign: (v) => _spaceDown = v,
    );
    _setKey(
      'SHIFT',
      pressed: false,
      current: _shiftDown,
      assign: (v) => _shiftDown = v,
    );
    _setKey('Q', pressed: false, current: _qDown, assign: (v) => _qDown = v);
    _setKey('E', pressed: false, current: _eDown, assign: (v) => _eDown = v);
    _setKey('F', pressed: false, current: _fDown, assign: (v) => _fDown = v);
    _setKey(
      'LEFT',
      pressed: false,
      current: _leftDown,
      assign: (v) => _leftDown = v,
    );
    _setKey(
      'RIGHT',
      pressed: false,
      current: _rightDown,
      assign: (v) => _rightDown = v,
    );
    _setKey('UP', pressed: false, current: _upDown, assign: (v) => _upDown = v);
    _setKey(
      'DOWN',
      pressed: false,
      current: _downDown,
      assign: (v) => _downDown = v,
    );
    _xAxis = 0;
    _yAxis = 0;
  }

  String? _mappedFlutterKey(
    PhysicalKeyboardKey physicalKey,
    LogicalKeyboardKey logicalKey,
  ) {
    if (physicalKey == PhysicalKeyboardKey.keyW ||
        logicalKey == LogicalKeyboardKey.keyW) {
      return 'W';
    }
    if (physicalKey == PhysicalKeyboardKey.keyA ||
        logicalKey == LogicalKeyboardKey.keyA) {
      return 'A';
    }
    if (physicalKey == PhysicalKeyboardKey.keyS ||
        logicalKey == LogicalKeyboardKey.keyS) {
      return 'S';
    }
    if (physicalKey == PhysicalKeyboardKey.keyD ||
        logicalKey == LogicalKeyboardKey.keyD) {
      return 'D';
    }
    if (physicalKey == PhysicalKeyboardKey.keyQ ||
        logicalKey == LogicalKeyboardKey.keyQ) {
      return 'Q';
    }
    if (physicalKey == PhysicalKeyboardKey.keyE ||
        logicalKey == LogicalKeyboardKey.keyE) {
      return 'E';
    }
    if (physicalKey == PhysicalKeyboardKey.keyF ||
        logicalKey == LogicalKeyboardKey.keyF) {
      return 'F';
    }
    if (physicalKey == PhysicalKeyboardKey.space ||
        logicalKey == LogicalKeyboardKey.space) {
      return 'SPACE';
    }
    if (physicalKey == PhysicalKeyboardKey.shiftLeft ||
        physicalKey == PhysicalKeyboardKey.shiftRight ||
        logicalKey == LogicalKeyboardKey.shiftLeft ||
        logicalKey == LogicalKeyboardKey.shiftRight) {
      return 'SHIFT';
    }
    if (physicalKey == PhysicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowLeft) {
      return 'LEFT';
    }
    if (physicalKey == PhysicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowRight) {
      return 'RIGHT';
    }
    if (physicalKey == PhysicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowUp) {
      return 'UP';
    }
    if (physicalKey == PhysicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.arrowDown) {
      return 'DOWN';
    }
    return null;
  }

  bool _setMappedKey(String key, bool pressed) {
    switch (key) {
      case 'W':
        _setKey(
          'W',
          pressed: pressed,
          current: _wDown,
          assign: (v) => _wDown = v,
        );
        return true;
      case 'A':
        _setKey(
          'A',
          pressed: pressed,
          current: _aDown,
          assign: (v) => _aDown = v,
        );
        return true;
      case 'S':
        _setKey(
          'S',
          pressed: pressed,
          current: _sDown,
          assign: (v) => _sDown = v,
        );
        return true;
      case 'D':
        _setKey(
          'D',
          pressed: pressed,
          current: _dDown,
          assign: (v) => _dDown = v,
        );
        return true;
      case 'SPACE':
        setJumpPressed(pressed);
        return true;
      case 'SHIFT':
        setShiftPressed(pressed);
        return true;
      case 'Q':
        _setKey(
          'Q',
          pressed: pressed,
          current: _qDown,
          assign: (v) => _qDown = v,
        );
        return true;
      case 'E':
        _setKey(
          'E',
          pressed: pressed,
          current: _eDown,
          assign: (v) => _eDown = v,
        );
        return true;
      case 'F':
        _setKey(
          'F',
          pressed: pressed,
          current: _fDown,
          assign: (v) => _fDown = v,
        );
        return true;
      case 'LEFT':
        _setKey(
          'LEFT',
          pressed: pressed,
          current: _leftDown,
          assign: (v) => _leftDown = v,
        );
        return true;
      case 'RIGHT':
        _setKey(
          'RIGHT',
          pressed: pressed,
          current: _rightDown,
          assign: (v) => _rightDown = v,
        );
        return true;
      case 'UP':
        _setKey(
          'UP',
          pressed: pressed,
          current: _upDown,
          assign: (v) => _upDown = v,
        );
        return true;
      case 'DOWN':
        _setKey(
          'DOWN',
          pressed: pressed,
          current: _downDown,
          assign: (v) => _downDown = v,
        );
        return true;
      default:
        return false;
    }
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
