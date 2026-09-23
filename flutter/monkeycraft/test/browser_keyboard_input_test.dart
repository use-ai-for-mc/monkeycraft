import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/browser_keyboard_input.dart';
import 'package:monkeycraft_client/stream/game_input_controller.dart';

void main() {
  KeyEvent down(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) {
    return KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );
  }

  KeyEvent up(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) {
    return KeyUpEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );
  }

  test('routes escape to an open screen and keeps its matching keyup', () {
    final events = <String>[];
    var screenOpen = true;
    final input = BrowserKeyboardInput(
      input: GameInputController((key, pressed) => events.add('$key:$pressed')),
      isScreenOpen: () => screenOpen,
      sendScreenEscape: (pressed) => events.add('ESCAPE:$pressed'),
    );

    expect(
      input.handle(down(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape)),
      isTrue,
    );
    screenOpen = false;
    expect(
      input.handle(up(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape)),
      isTrue,
    );

    expect(events, ['ESCAPE:true', 'ESCAPE:false']);
  });

  test(
    'ignores escape outside a screen and releases pressed movement on blur',
    () {
      final events = <String>[];
      final input = BrowserKeyboardInput(
        input: GameInputController(
          (key, pressed) => events.add('$key:$pressed'),
        ),
        isScreenOpen: () => false,
        sendScreenEscape: (pressed) => events.add('ESCAPE:$pressed'),
      );

      expect(
        input.handle(
          down(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape),
        ),
        isFalse,
      );
      expect(
        input.handle(down(PhysicalKeyboardKey.keyF, LogicalKeyboardKey.keyF)),
        isTrue,
      );
      input.releaseAll();

      expect(events, ['F:true', 'F:false']);
    },
  );
}
