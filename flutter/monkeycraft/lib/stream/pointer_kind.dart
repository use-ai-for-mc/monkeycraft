import 'package:flutter/gestures.dart';

bool isMouseLike(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

bool isTouchLike(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;

int? mouseButtonIndex(int buttons) {
  if ((buttons & kSecondaryButton) != 0) return 1;
  if ((buttons & kPrimaryButton) != 0) return 0;
  return null;
}
