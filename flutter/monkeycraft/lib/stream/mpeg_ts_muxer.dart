import 'dart:io';
import 'dart:typed_data';

class MpegTsMuxer {
  static const int _patPid = 0x0000;
  static const int _pmtPid = 0x1000;
  static const int _videoPid = 0x0100;
  static const int _programNumber = 1;
  static const int _pcrPid = _videoPid;

  int _patCc = 0;
  int _pmtCc = 0;
  int _videoCc = 0;

  void reset() {
    _patCc = 0;
    _pmtCc = 0;
    _videoCc = 0;
  }

  void writeTables(Socket client) {
    client.add(_buildPatPacket());
    client.add(_buildPmtPacket());
  }

  List<Uint8List> muxH264AccessUnit(Uint8List accessUnit, int pts90k) {
    final pes = _buildPes(accessUnit, pts90k);
    return _packetizePes(_videoPid, pes);
  }

  Uint8List _buildPatPacket() {
    final section = BytesBuilder(copy: false);
    section.addByte(0x00);
    section.addByte(0xB0);
    section.addByte(0x0D);
    section.addByte(0x00);
    section.addByte(0x01);
    section.addByte(0xC1);
    section.addByte(0x00);
    section.addByte(0x00);
    section.addByte((_programNumber >> 8) & 0xFF);
    section.addByte(_programNumber & 0xFF);
    section.addByte(0xE0 | ((_pmtPid >> 8) & 0x1F));
    section.addByte(_pmtPid & 0xFF);

    final crc = _crc32(section.toBytes());
    section.add(_u32be(crc));

    final payload = BytesBuilder(copy: false);
    payload.addByte(0x00);
    payload.add(section.toBytes());

    final packet = _tsPacket(
      pid: _patPid,
      payloadUnitStart: true,
      continuityCounter: _patCc,
      payload: payload.toBytes(),
    );
    _patCc = (_patCc + 1) & 0x0F;
    return packet;
  }

  Uint8List _buildPmtPacket() {
    final section = BytesBuilder(copy: false);
    section.addByte(0x02);
    section.addByte(0xB0);
    section.addByte(0x12);
    section.addByte((_programNumber >> 8) & 0xFF);
    section.addByte(_programNumber & 0xFF);
    section.addByte(0xC1);
    section.addByte(0x00);
    section.addByte(0x00);
    section.addByte(0xE0 | ((_pcrPid >> 8) & 0x1F));
    section.addByte(_pcrPid & 0xFF);
    section.addByte(0xF0);
    section.addByte(0x00);
    section.addByte(0x1B);
    section.addByte(0xE0 | ((_videoPid >> 8) & 0x1F));
    section.addByte(_videoPid & 0xFF);
    section.addByte(0xF0);
    section.addByte(0x00);

    final crc = _crc32(section.toBytes());
    section.add(_u32be(crc));

    final payload = BytesBuilder(copy: false);
    payload.addByte(0x00);
    payload.add(section.toBytes());

    final packet = _tsPacket(
      pid: _pmtPid,
      payloadUnitStart: true,
      continuityCounter: _pmtCc,
      payload: payload.toBytes(),
    );
    _pmtCc = (_pmtCc + 1) & 0x0F;
    return packet;
  }

  Uint8List _buildPes(Uint8List payload, int pts90k) {
    final b = BytesBuilder(copy: false);
    b.add(const [0x00, 0x00, 0x01]);
    b.addByte(0xE0);
    b.add(const [0x00, 0x00]);
    b.add(const [0x80, 0x80, 0x05]);
    b.add(_encodePts(pts90k));
    b.add(payload);
    return b.toBytes();
  }

  List<Uint8List> _packetizePes(int pid, Uint8List pes) {
    final packets = <Uint8List>[];
    int offset = 0;
    bool first = true;
    while (offset < pes.length) {
      final remaining = pes.length - offset;
      final payloadLen = remaining >= 184 ? 184 : remaining;
      final payload = pes.sublist(offset, offset + payloadLen);
      final packet = _tsPacket(
        pid: pid,
        payloadUnitStart: first,
        continuityCounter: _videoCc,
        payload: payload,
      );
      packets.add(packet);
      _videoCc = (_videoCc + 1) & 0x0F;
      offset += payloadLen;
      first = false;
    }
    return packets;
  }

  Uint8List _tsPacket({
    required int pid,
    required bool payloadUnitStart,
    required int continuityCounter,
    required List<int> payload,
  }) {
    final packet = Uint8List(188);
    packet[0] = 0x47;
    packet[1] = ((payloadUnitStart ? 0x40 : 0x00) | ((pid >> 8) & 0x1F));
    packet[2] = pid & 0xFF;

    int adaptationControl = 1;
    int headerIndex = 4;

    final payloadCapacity = 184;
    final remaining = payloadCapacity - payload.length;
    if (remaining > 0) {
      adaptationControl = 3;
      final adaptationLen = remaining - 1;
      packet[3] =
          ((adaptationControl & 0x03) << 4) | (continuityCounter & 0x0F);
      packet[4] = adaptationLen & 0xFF;
      headerIndex = 5;
      if (adaptationLen > 0) {
        packet[5] = 0x00;
        for (int i = 6; i < 5 + adaptationLen; i++) {
          packet[i] = 0xFF;
        }
        headerIndex = 5 + adaptationLen;
      }
    } else {
      packet[3] =
          ((adaptationControl & 0x03) << 4) | (continuityCounter & 0x0F);
    }

    packet.setRange(headerIndex, headerIndex + payload.length, payload);
    if (headerIndex + payload.length < 188) {
      packet.fillRange(headerIndex + payload.length, 188, 0xFF);
    }
    return packet;
  }

  static Uint8List _encodePts(int pts90k) {
    final pts = pts90k & 0x1FFFFFFFF;
    return Uint8List.fromList([
      0x21 | (((pts >> 30) & 0x07) << 1),
      (pts >> 22) & 0xFF,
      0x01 | (((pts >> 15) & 0x7F) << 1),
      (pts >> 7) & 0xFF,
      0x01 | (((pts) & 0x7F) << 1),
    ]);
  }

  static Uint8List _u32be(int v) {
    return Uint8List.fromList([
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= (byte & 0xFF) << 24;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x80000000) != 0) {
          crc = (crc << 1) ^ 0x04C11DB7;
        } else {
          crc <<= 1;
        }
        crc &= 0xFFFFFFFF;
      }
    }
    return crc & 0xFFFFFFFF;
  }
}
