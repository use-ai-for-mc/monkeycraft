import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/transport/ws_frame.dart';

void main() {
  test('client frames are masked on the wire', () {
    final key = Uint8List.fromList([1, 2, 3, 4]);
    final encoded = encodeWsFrame(
      opcode: wsOpcodeText,
      payload: 'ab'.codeUnits,
      maskKey: key,
    );
    expect(encoded[1] & 0x80, 0x80);
    expect(encoded[6] == 'a'.codeUnitAt(0), isFalse);
  });

  test('reader rejects masked server frames', () {
    final reader = WsFrameReader();
    reader.add(encodeWsFrame(
      opcode: wsOpcodeText,
      payload: 'x'.codeUnits,
      maskKey: Uint8List.fromList([1, 2, 3, 4]),
    ));
    expect(reader.take, throwsA(isA<WsProtocolException>()));
  });

  test('assembler joins continuation frames', () {
    final asm = WsAssembler();
    expect(
      asm.push(
        WsFrame(
          fin: false,
          opcode: wsOpcodeBinary,
          payload: Uint8List.fromList([1, 2]),
        ),
      ),
      isNull,
    );
    final msg = asm.push(
      WsFrame(
        fin: true,
        opcode: wsOpcodeContinuation,
        payload: Uint8List.fromList([3, 4]),
      ),
    );
    expect(msg!.opcode, wsOpcodeBinary);
    expect(msg.payload, [1, 2, 3, 4]);
  });

  test('rfc6455 hello unmasked', () {
    final reader = WsFrameReader();
    reader.add([0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]);
    final f = reader.take();
    expect(f!.opcode, wsOpcodeText);
    expect(decodeTextPayload(f.payload), 'Hello');
  });
}
