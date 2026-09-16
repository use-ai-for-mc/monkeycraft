import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/transport/tailscale_web_channel.dart';
import 'package:monkeycraft_client/stream/transport/ws_frame.dart';

class _Pipe {
  final _fromClient = StreamController<Uint8List>();
  final _toClient = <Uint8List>[];
  Completer<void>? _wait;

  Future<void> writeFromClient(Uint8List bytes) async {
    _fromClient.add(bytes);
  }

  void writeToClient(Uint8List bytes) {
    _toClient.add(bytes);
    _wait?.complete();
    _wait = null;
  }

  Future<Uint8List?> readToClient() async {
    if (_toClient.isNotEmpty) return _toClient.removeAt(0);
    _wait = Completer<void>();
    await _wait!.future;
    if (_toClient.isEmpty) return null;
    return _toClient.removeAt(0);
  }
}

Uint8List unmasked(int opcode, List<int> payload, {bool fin = true}) {
  final n = payload.length;
  final out = Uint8List(2 + n);
  out[0] = (fin ? 0x80 : 0) | opcode;
  out[1] = n;
  out.setRange(2, 2 + n, payload);
  return out;
}

void main() {
  test('client handshake then binary roundtrip', () async {
    final pipe = _Pipe();
    final rng = Random(1);

    unawaited(() async {
      final pending = BytesBuilder(copy: false);
      await for (final chunk in pipe._fromClient.stream) {
        pending.add(chunk);
        final bytes = pending.toBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        if (!text.contains('\r\n\r\n')) continue;
        final key = RegExp(
          r'Sec-WebSocket-Key:\s*(\S+)',
          caseSensitive: false,
        ).firstMatch(text)!.group(1)!;
        final accept = base64Encode(
          sha1
              .convert(
                utf8.encode('$key${'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'}'),
              )
              .bytes,
        );
        pipe.writeToClient(
          Uint8List.fromList(
            utf8.encode(
              'HTTP/1.1 101 Switching Protocols\r\n'
              'Upgrade: websocket\r\n'
              'Connection: Upgrade\r\n'
              'Sec-WebSocket-Accept: $accept\r\n\r\n',
            ),
          ),
        );
        break;
      }
    }());

    final channel = await TailscaleWebSocketChannel.connect(
      url: Uri.parse('ws://100.64.0.1:9600/'),
      write: pipe.writeFromClient,
      read: pipe.readToClient,
      close: () async {},
      random: rng,
    );
    await channel.ready;

    final got = Completer<Object?>();
    channel.stream.listen(got.complete);
    pipe.writeToClient(unmasked(wsOpcodeBinary, [9, 8, 7]));
    final msg = await got.future.timeout(const Duration(seconds: 2));
    expect(msg, [9, 8, 7]);
  });
}
