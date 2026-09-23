import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/stream/game_input_controller.dart';

void main() {
  test('presses and releases W with hysteresis', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    controller.updateMoveVector(const Offset(0, -0.5));
    controller.updateMoveVector(const Offset(0, -0.3));
    controller.updateMoveVector(const Offset(0, -0.2));

    expect(events, ['W:true', 'W:false']);
  });

  test('supports diagonal movement', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    controller.updateMoveVector(const Offset(0.7, -0.7));

    expect(events, ['W:true', 'D:true']);
  });

  test('switches cleanly from W to S', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    controller.updateMoveVector(const Offset(0, -0.7));
    controller.updateMoveVector(const Offset(0, 0.7));

    expect(events, ['W:true', 'W:false', 'S:true']);
  });

  test('jump button toggles SPACE', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    controller.setJumpPressed(true);
    controller.setJumpPressed(false);

    expect(events, ['SPACE:true', 'SPACE:false']);
  });

  test('releaseAll releases any pressed keys', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    controller.updateMoveVector(const Offset(-0.7, -0.7));
    controller.setJumpPressed(true);
    controller.releaseAll();

    expect(events, [
      'W:true',
      'A:true',
      'SPACE:true',
      'W:false',
      'A:false',
      'SPACE:false',
    ]);
  });

  test('physical WASD, space and shift map to existing keys', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    expect(controller.handlePhysicalKey('w', true), isTrue);
    expect(controller.handlePhysicalKey('D', true), isTrue);
    expect(controller.handlePhysicalKey(' ', true), isTrue);
    expect(controller.handlePhysicalKey('ShiftLeft', true), isTrue);
    expect(controller.handlePhysicalKey('q', true), isTrue);
    controller.releaseAll();

    expect(events, [
      'W:true',
      'D:true',
      'SPACE:true',
      'SHIFT:true',
      'Q:true',
      'W:false',
      'D:false',
      'SPACE:false',
      'SHIFT:false',
      'Q:false',
    ]);
  });

  test('Flutter physical and logical keys preserve release mappings', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    expect(
      controller.handleFlutterKey(
        PhysicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftLeft,
        true,
      ),
      isTrue,
    );
    expect(
      controller.handleFlutterKey(
        PhysicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyQ,
        true,
      ),
      isTrue,
    );
    expect(
      controller.handleFlutterKey(
        PhysicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        true,
      ),
      isTrue,
    );
    controller.handleFlutterKey(
      PhysicalKeyboardKey.keyQ,
      LogicalKeyboardKey.keyQ,
      false,
    );
    controller.releaseAll();

    expect(events, [
      'SHIFT:true',
      'Q:true',
      'RIGHT:true',
      'Q:false',
      'SHIFT:false',
      'RIGHT:false',
    ]);
  });

  test('Q E F and arrows are mapped by legacy physical labels', () {
    final events = <String>[];
    final controller = GameInputController((key, pressed) {
      events.add('$key:$pressed');
    });

    for (final key in ['KeyQ', 'KeyE', 'KeyF', 'ArrowLeft', 'ArrowUp']) {
      expect(controller.handlePhysicalKey(key, true), isTrue);
      expect(controller.handlePhysicalKey(key, false), isTrue);
    }

    expect(events, [
      'Q:true',
      'Q:false',
      'E:true',
      'E:false',
      'F:true',
      'F:false',
      'LEFT:true',
      'LEFT:false',
      'UP:true',
      'UP:false',
    ]);
  });
}
