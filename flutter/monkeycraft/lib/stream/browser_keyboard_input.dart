import 'package:flutter/services.dart';
import 'package:monkeycraft_client/stream/game_input_controller.dart';

class BrowserKeyboardInput {
  BrowserKeyboardInput({
    required this.input,
    required this.isScreenOpen,
    required this.sendScreenEscape,
  });

  final GameInputController input;
  final bool Function() isScreenOpen;
  final void Function(bool pressed) sendScreenEscape;
  bool _escapeDown = false;

  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyUpEvent) return false;
    final pressed = event is KeyDownEvent;
    if (_isEscape(event)) {
      if (pressed && !isScreenOpen()) return false;
      if (pressed == _escapeDown) return true;
      _escapeDown = pressed;
      sendScreenEscape(pressed);
      return true;
    }
    return input.handleFlutterKey(event.physicalKey, event.logicalKey, pressed);
  }

  void releaseAll() {
    input.releaseAll();
    if (_escapeDown) {
      _escapeDown = false;
      sendScreenEscape(false);
    }
  }

  bool _isEscape(KeyEvent event) {
    return event.physicalKey == PhysicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.escape;
  }
}
