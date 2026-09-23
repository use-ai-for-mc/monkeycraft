import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/widgets/screen_controls.dart';

void main() {
  test('normalizes only points inside the contained video rect', () {
    const rect = Rect.fromLTWH(100, 50, 400, 200);

    expect(normalizeScreenPoint(const Offset(100, 50), rect), (x: 0.0, y: 0.0));
    expect(normalizeScreenPoint(const Offset(500, 250), rect), (
      x: 1.0,
      y: 1.0,
    ));
    expect(normalizeScreenPoint(const Offset(99, 50), rect), isNull);
    expect(normalizeScreenPoint(const Offset(501, 250), rect), isNull);
  });

  test('limits hover dispatch to at most 30Hz', () {
    final throttle = ScreenHoverThrottle();
    final start = DateTime(2026, 9, 19);

    expect(throttle.shouldSend(start), isTrue);
    expect(
      throttle.shouldSend(start.add(const Duration(milliseconds: 33))),
      isFalse,
    );
    expect(
      throttle.shouldSend(start.add(const Duration(milliseconds: 34))),
      isTrue,
    );
  });
}
