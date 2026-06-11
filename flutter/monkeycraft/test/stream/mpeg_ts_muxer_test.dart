import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/mpeg_ts_muxer.dart';

int _readPcrBase(Uint8List packet) {
  return (packet[6] << 25) |
      (packet[7] << 17) |
      (packet[8] << 9) |
      (packet[9] << 1) |
      ((packet[10] >> 7) & 0x01);
}

void main() {
  group('MpegTsMuxer', () {
    test('first packet of an access unit carries the PCR', () {
      final muxer = MpegTsMuxer();
      final au = Uint8List.fromList(List.generate(1000, (i) => i & 0xFF));
      const pts = 123456789;

      final packets = muxer.muxH264AccessUnit(au, pts);

      final first = packets.first;
      expect(first[0], 0x47);
      expect((first[1] >> 6) & 0x01, 1, reason: 'payload_unit_start');
      final adaptationControl = (first[3] >> 4) & 0x03;
      expect(adaptationControl, 3, reason: 'adaptation field + payload');
      expect(first[5] & 0x10, 0x10, reason: 'PCR flag');
      expect(_readPcrBase(first), pts);

      for (final packet in packets.skip(1)) {
        expect((packet[1] >> 6) & 0x01, 0);
      }
    });

    test('payload bytes reassemble the full PES with the PTS intact', () {
      final muxer = MpegTsMuxer();
      final au = Uint8List.fromList(List.generate(700, (i) => (i * 7) & 0xFF));
      const pts = 0x0007654321;

      final packets = muxer.muxH264AccessUnit(au, pts);

      final pes = BytesBuilder();
      for (final packet in packets) {
        final adaptationControl = (packet[3] >> 4) & 0x03;
        var index = 4;
        if (adaptationControl == 3) {
          index = 5 + packet[4];
        }
        pes.add(packet.sublist(index));
      }
      final bytes = pes.toBytes();

      expect(bytes.sublist(0, 4), [0x00, 0x00, 0x01, 0xE0]);
      // PTS from the PES header (5-byte 33-bit encoding at offset 9).
      final decodedPts = (((bytes[9] >> 1) & 0x07) << 30) |
          (bytes[10] << 22) |
          (((bytes[11] >> 1) & 0x7F) << 15) |
          (bytes[12] << 7) |
          ((bytes[13] >> 1) & 0x7F);
      expect(decodedPts, pts);
      // The access unit follows the 14-byte PES header.
      expect(bytes.length, 14 + au.length);
      expect(bytes.sublist(14), au);
    });

    test('continuity counters increment across video packets', () {
      final muxer = MpegTsMuxer();
      final au = Uint8List.fromList(List.filled(600, 0xAB));

      final packets = muxer.muxH264AccessUnit(au, 0);

      final counters = packets.map((p) => p[3] & 0x0F).toList();
      for (var i = 1; i < counters.length; i++) {
        expect(counters[i], (counters[i - 1] + 1) & 0x0F);
      }
    });
  });
}
