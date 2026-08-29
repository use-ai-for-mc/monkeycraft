import 'package:flutter_test/flutter_test.dart';
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
    expect(controller.handlePhysicalKey('q', true), isFalse);
    controller.releaseAll();

    expect(events, [
      'W:true',
      'D:true',
      'SPACE:true',
      'SHIFT:true',
      'W:false',
      'D:false',
      'SPACE:false',
      'SHIFT:false',
    ]);
  });
}
