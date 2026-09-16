import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/pointer_kind.dart';

void main() {
  test('mouseButtonIndex maps primary and secondary', () {
    expect(mouseButtonIndex(kPrimaryButton), 0);
    expect(mouseButtonIndex(kSecondaryButton), 1);
    expect(mouseButtonIndex(0), isNull);
  });

  test('touch vs mouse kinds', () {
    expect(isMouseLike(PointerDeviceKind.mouse), isTrue);
    expect(isMouseLike(PointerDeviceKind.trackpad), isTrue);
    expect(isMouseLike(PointerDeviceKind.touch), isFalse);
    expect(isTouchLike(PointerDeviceKind.touch), isTrue);
    expect(isTouchLike(PointerDeviceKind.stylus), isTrue);
    expect(isTouchLike(PointerDeviceKind.mouse), isFalse);
  });
}
