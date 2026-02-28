import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/look_delta_coalescer.dart';
import 'package:monkeycraft_client/stream/widgets/look_pad.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('isPointExcluded returns true for included rects', () {
    final excluded = [const Rect.fromLTWH(10, 10, 20, 20)];
    expect(isPointExcluded(const Offset(15, 15), excluded), isTrue);
    expect(isPointExcluded(const Offset(5, 5), excluded), isFalse);
  });

  testWidgets('LookDeltaCoalescer coalesces and flushes on interval', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    final flushed = <String>[];
    final coalescer = LookDeltaCoalescer(
      onFlush: (yaw, pitch) => flushed.add('$yaw,$pitch'),
      interval: const Duration(milliseconds: 16),
    );

    coalescer.start();
    coalescer.add(yaw: 1, pitch: 2);
    await tester.pump(const Duration(milliseconds: 15));
    expect(flushed, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(flushed, ['1.0,2.0']);

    coalescer.add(yaw: 0.5, pitch: -0.5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(flushed, ['1.0,2.0', '0.5,-0.5']);

    coalescer.stop();
  });

  testWidgets(
    'LookPad converts drag to yaw/pitch deltas and ignores excluded',
    (tester) async {
      final deltas = <String>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              children: [
                LookPad(
                  excludedRegions: const [Rect.fromLTWH(0, 0, 120, 120)],
                  sensitivityX: 0.1,
                  sensitivityY: 0.2,
                  onDelta: (yaw, pitch) => deltas.add(
                    '${yaw.toStringAsFixed(2)},${pitch.toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final excludedStart =
          tester.getTopLeft(find.byType(LookPad)) + const Offset(60, 60);
      final gesture1 = await tester.startGesture(excludedStart);
      await gesture1.moveBy(const Offset(20, 20));
      await gesture1.up();
      await tester.pump();
      expect(deltas, isEmpty);

      final start =
          tester.getTopLeft(find.byType(LookPad)) + const Offset(200, 200);
      final gesture2 = await tester.startGesture(start);
      await gesture2.moveBy(const Offset(10, 20));
      await gesture2.up();
      await tester.pump();

      expect(deltas, ['1.00,-4.00']);
    },
  );
}
