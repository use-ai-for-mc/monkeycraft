import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const int wsOpcodeContinuation = 0x0;
const int wsOpcodeText = 0x1;
const int wsOpcodeBinary = 0x2;
const int wsOpcodeClose = 0x8;
const int wsOpcodePing = 0x9;
const int wsOpcodePong = 0xA;
const int wsCloseNormal = 1000;
const int wsMaxControlPayload = 125;

class WsFrame {
  WsFrame({
    required this.fin,
    required this.opcode,
    required this.payload,
    this.masked = false,
  });

  final bool fin;
  final int opcode;
  final Uint8List payload;
  final bool masked;
}

class WsProtocolException implements Exception {
  WsProtocolException(this.message);
  final String message;
  @override
  String toString() => 'WsProtocolException: $message';
}

Uint8List encodeWsFrame({
  required int opcode,
  required List<int> payload,
  bool fin = true,
  required Uint8List maskKey,
}) {
  final data = Uint8List.fromList(payload);
  if ((opcode == wsOpcodeClose ||
          opcode == wsOpcodePing ||
          opcode == wsOpcodePong) &&
      (!fin || data.length > wsMaxControlPayload)) {
    throw WsProtocolException('invalid control frame');
  }
  final n = data.length;
  var headerLen = 2 + 4;
  var lenByte = n;
  if (n > 0xffff) {
    headerLen += 8;
    lenByte = 127;
  } else if (n > 125) {
    headerLen += 2;
    lenByte = 126;
  }
  final out = Uint8List(headerLen + n);
  out[0] = (fin ? 0x80 : 0) | (opcode & 0x0f);
  out[1] = 0x80 | lenByte;
  var off = 2;
  if (lenByte == 126) {
    out[2] = (n >> 8) & 0xff;
    out[3] = n & 0xff;
    off = 4;
  } else if (lenByte == 127) {
    final view = ByteData.sublistView(out);
    view.setUint32(2, 0);
    view.setUint32(6, n);
    off = 10;
  }
  out.setRange(off, off + 4, maskKey);
  off += 4;
  for (var i = 0; i < n; i++) {
    out[off + i] = data[i] ^ maskKey[i & 3];
  }
  return out;
}

class WsFrameReader {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  void add(List<int> chunk) {
    _buf.add(chunk);
  }

  WsFrame? take() {
    final bytes = _buf.toBytes();
    if (bytes.length < 2) return null;
    final fin = (bytes[0] & 0x80) != 0;
    if ((bytes[0] & 0x70) != 0) {
      throw WsProtocolException('reserved bits');
    }
    final opcode = bytes[0] & 0x0f;
    final masked = (bytes[1] & 0x80) != 0;
    if (masked) {
      throw WsProtocolException('server frame was masked');
    }
    var n = bytes[1] & 0x7f;
    var off = 2;
    if (n == 126) {
      if (bytes.length < 4) return null;
      n = (bytes[2] << 8) | bytes[3];
      off = 4;
      if (n < 126) throw WsProtocolException('non-minimal length');
    } else if (n == 127) {
      if (bytes.length < 10) return null;
      final view = ByteData.sublistView(bytes, 2, 10);
      if (view.getUint32(0) != 0) {
        throw WsProtocolException('frame too large');
      }
      n = view.getUint32(4);
      if (n < 65536) throw WsProtocolException('non-minimal length');
      off = 10;
    }
    if (bytes.length < off + n) return null;
    final payload = Uint8List.fromList(bytes.sublist(off, off + n));
    final rest = bytes.sublist(off + n);
    _buf.clear();
    if (rest.isNotEmpty) _buf.add(rest);
    return WsFrame(fin: fin, opcode: opcode, payload: payload);
  }
}

class WsAssembler {
  int _fragOp = 0;
  final BytesBuilder _frag = BytesBuilder(copy: false);
  final int maxMessageBytes;

  WsAssembler({this.maxMessageBytes = 4 << 20});

  WsFrame? push(WsFrame frame) {
    if (frame.opcode == wsOpcodePing ||
        frame.opcode == wsOpcodePong ||
        frame.opcode == wsOpcodeClose) {
      return frame;
    }
    if (frame.opcode == wsOpcodeContinuation) {
      if (_fragOp == 0) throw WsProtocolException('unexpected continuation');
      _append(frame.payload);
      if (frame.fin) return _finish();
      return null;
    }
    if (frame.opcode != wsOpcodeText && frame.opcode != wsOpcodeBinary) {
      throw WsProtocolException('bad opcode');
    }
    if (_fragOp != 0) throw WsProtocolException('data during fragment');
    if (!frame.fin) {
      _fragOp = frame.opcode;
      _append(frame.payload);
      return null;
    }
    return frame;
  }

  void _append(Uint8List p) {
    if (_frag.length + p.length > maxMessageBytes) {
      throw WsProtocolException('message too big');
    }
    _frag.add(p);
  }

  WsFrame _finish() {
    final op = _fragOp;
    final payload = _frag.takeBytes();
    _fragOp = 0;
    return WsFrame(fin: true, opcode: op, payload: payload);
  }
}

Uint8List randomMaskKey([Random? random]) {
  final r = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(4, (_) => r.nextInt(256)));
}

String decodeTextPayload(Uint8List payload) {
  return utf8.decode(payload);
}
