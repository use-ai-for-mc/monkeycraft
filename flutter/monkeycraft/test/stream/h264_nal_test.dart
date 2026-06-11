import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/h264_nal.dart';

void main() {
  group('containsIdrNal', () {
    test('finds IDR behind a 4-byte start code', () {
      expect(containsIdrNal([0, 0, 0, 1, 0x65, 0xAA]), isTrue);
    });

    test('finds IDR behind a 3-byte start code', () {
      expect(containsIdrNal([0, 0, 1, 0x65, 0xAA]), isTrue);
    });

    test('finds IDR after a leading non-IDR NAL with 3-byte codes', () {
      // SPS (7), PPS (8), then IDR (5), all 3-byte start codes.
      expect(
        containsIdrNal([0, 0, 1, 0x67, 0x42, 0, 0, 1, 0x68, 0, 0, 1, 0x65]),
        isTrue,
      );
    });

    test('mixed start code lengths', () {
      expect(
        containsIdrNal([0, 0, 0, 1, 0x41, 0x9A, 0, 0, 1, 0x65, 0x88]),
        isTrue,
      );
    });

    test('no IDR in a P-frame access unit', () {
      expect(containsIdrNal([0, 0, 0, 1, 0x41, 0x9A, 0x00]), isFalse);
      expect(containsIdrNal([0, 0, 1, 0x41, 0x9A]), isFalse);
    });

    test('payload bytes that look like NAL type 5 are not misread', () {
      // 0x65 without a preceding start code must not count.
      expect(containsIdrNal([0x65, 0x65, 0x65]), isFalse);
      // Inside emulation-prevention-free payload after a non-IDR header.
      expect(containsIdrNal([0, 0, 1, 0x41, 0, 1, 0x65]), isFalse);
    });

    test('short and empty inputs', () {
      expect(containsIdrNal([]), isFalse);
      expect(containsIdrNal([0, 0, 1]), isFalse);
      expect(containsIdrNal([0, 0, 1, 0x65]), isTrue);
    });
  });
}
