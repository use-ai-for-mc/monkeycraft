@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/platform/browser_input_web.dart';
import 'package:web/web.dart' as web;

void main() {
  test('Promise rejection clears a pending pointer-lock request', () async {
    var locked = false;
    var requests = 0;
    var exits = 0;
    final rejection = Completer<void>();
    final controller = BrowserPointerLockController.forTesting(
      isTargetLocked: () => locked,
      requestPointerLock: () {
        requests += 1;
        return rejection.future.toJS;
      },
      exitPointerLock: () => exits += 1,
    );

    controller.request();
    controller.request();
    expect(requests, 1);
    rejection.completeError(StateError('denied'));
    await Future<void>.delayed(Duration.zero);
    controller.request();

    expect(requests, 2);
    expect(exits, 0);
    controller.dispose();
  });

  test('a successful request accepts its later DOM lock event', () async {
    var locked = false;
    var exits = 0;
    final controller = BrowserPointerLockController.forTesting(
      isTargetLocked: () => locked,
      requestPointerLock: () => Future<void>.value().toJS,
      exitPointerLock: () {
        exits += 1;
        locked = false;
      },
    );

    controller.request();
    await Future<void>.delayed(Duration.zero);
    locked = true;
    web.document.dispatchEvent(web.Event('pointerlockchange'));

    expect(controller.isLocked, isTrue);
    expect(exits, 0);
    controller.dispose();
  });

  test('void request that locks after dispose is immediately released', () {
    var locked = false;
    var exits = 0;
    final controller = BrowserPointerLockController.forTesting(
      isTargetLocked: () => locked,
      requestPointerLock: () => null,
      exitPointerLock: () {
        exits += 1;
        locked = false;
      },
    );

    controller.request();
    controller.dispose();
    locked = true;
    web.document.dispatchEvent(web.Event('pointerlockchange'));

    expect(exits, 1);
    expect(controller.isLocked, isFalse);
  });

  test('release invalidates a void request before a late lock event', () {
    var locked = false;
    var exits = 0;
    final controller = BrowserPointerLockController.forTesting(
      isTargetLocked: () => locked,
      requestPointerLock: () => null,
      exitPointerLock: () {
        exits += 1;
        locked = false;
      },
    );

    controller.request();
    controller.release();
    locked = true;
    web.document.dispatchEvent(web.Event('pointerlockchange'));

    expect(exits, 1);
    controller.dispose();
  });

  test(
    'locked document mouse movement is forwarded once and stops on disable',
    () {
      var locked = true;
      final deltas = <(double, double)>[];
      final controller = BrowserPointerLockController.forTesting(
        isTargetLocked: () => locked,
        requestPointerLock: () => null,
        exitPointerLock: () => locked = false,
      );
      controller.setMoveHandler((dx, dy) => deltas.add((dx, dy)));
      controller.request();
      web.document.dispatchEvent(web.Event('pointerlockchange'));
      web.document.dispatchEvent(
        web.MouseEvent(
          'mousemove',
          web.MouseEventInit(movementX: 9, movementY: -4),
        ),
      );
      controller.setEnabled(false);
      web.document.dispatchEvent(
        web.MouseEvent(
          'mousemove',
          web.MouseEventInit(movementX: 3, movementY: 2),
        ),
      );

      expect(deltas, [(9.0, -4.0)]);
      controller.dispose();
    },
  );
}
