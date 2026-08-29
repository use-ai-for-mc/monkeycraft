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
      expect(containsIdrNal([0x65, 0x65, 0x65]), isFalse);
      expect(containsIdrNal([0, 0, 1, 0x41, 0, 1, 0x65]), isFalse);
    });

    test('short and empty inputs', () {
      expect(containsIdrNal([]), isFalse);
      expect(containsIdrNal([0, 0, 1]), isFalse);
      expect(containsIdrNal([0, 0, 1, 0x65]), isTrue);
    });
  });

  group('SPS codec string', () {
    test('reads Baseline Level 4.0 from a JCodec-style IDR AU', () {
      final au = [
        0, 0, 0, 1, 0x67, 0x42, 0x00, 0x28, 0xAB,
        0, 0, 0, 1, 0x68, 0xCE,
        0, 0, 0, 1, 0x65, 0x88,
      ];
      expect(containsSpsNal(au), isTrue);
      expect(containsPpsNal(au), isTrue);
      expect(containsIdrNal(au), isTrue);
      expect(parseSpsCodec(au)?.codecString, 'avc1.420028');
    });

    test('returns null when there is no SPS', () {
      expect(parseSpsCodec([0, 0, 0, 1, 0x41, 0x9A]), isNull);
    });
  });
}
