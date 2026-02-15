import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/services/stream_resolution.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('computeTargetResolution clamps and makes even', () {
    final r = computeTargetResolution(
      logicalSize: const Size(10000, 10000),
      devicePixelRatio: 3,
      scale: 1,
      maxDim: 1920,
    );
    expect(r.width, 1920);
    expect(r.height, 1920);
    expect(r.width.isEven, isTrue);
    expect(r.height.isEven, isTrue);
  });

  test('computeTargetResolution respects scale', () {
    final r1 = computeTargetResolution(
      logicalSize: const Size(200, 100),
      devicePixelRatio: 2,
      scale: 1,
      maxDim: 1920,
    );
    final r2 = computeTargetResolution(
      logicalSize: const Size(200, 100),
      devicePixelRatio: 2,
      scale: 0.5,
      maxDim: 1920,
    );
    expect(r2.width, r1.width ~/ 2);
    expect(r2.height, r1.height ~/ 2);
  });

  test('computeTargetResolution subtracts safe-area padding', () {
    final r = computeTargetResolution(
      logicalSize: const Size(200, 100),
      padding: const EdgeInsets.only(top: 10),
      devicePixelRatio: 2,
      scale: 1,
      maxDim: 1920,
    );
    expect(r.width, 400);
    expect(r.height, 180);
  });
}
