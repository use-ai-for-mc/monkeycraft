import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:monkeycraft_client/stream/transport/ws_frame.dart';

typedef TcpWrite = Future<void> Function(Uint8List bytes);
typedef TcpRead = Future<Uint8List?> Function();
typedef TcpClose = Future<void> Function();

class TailscaleWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  TailscaleWebSocketChannel._({
    required StreamController<dynamic> incoming,
    required _TailscaleWebSocketSink sink,
    required Completer<void> ready,
  }) : _incoming = incoming,
       _sink = sink,
       _ready = ready;

  final StreamController<dynamic> _incoming;
  final _TailscaleWebSocketSink _sink;
  final Completer<void> _ready;

  static Future<TailscaleWebSocketChannel> connect({
    required Uri url,
    required TcpWrite write,
    required TcpRead read,
    required TcpClose close,
    Duration timeout = const Duration(seconds: 5),
    Random? random,
  }) async {
    final incoming = StreamController<dynamic>();
    final ready = Completer<void>();
    final sink = _TailscaleWebSocketSink(write: write, closeTcp: close);
    final channel = TailscaleWebSocketChannel._(
      incoming: incoming,
      sink: sink,
      ready: ready,
    );
    sink._channel = channel;
    incoming.onCancel = () => sink.close();

    Uint8List leftover = Uint8List(0);
    try {
      leftover = await _handshake(
        url,
        write,
        read,
        random ?? Random.secure(),
      ).timeout(timeout);
      if (!ready.isCompleted) ready.complete();
    } catch (_) {
      await close();
      rethrow;
    }

    unawaited(channel._readLoop(read, close, leftover));
    return channel;
  }

  Future<void> _readLoop(
    TcpRead read,
    TcpClose closeTcp,
    Uint8List leftover,
  ) async {
    final reader = WsFrameReader();
    if (leftover.isNotEmpty) reader.add(leftover);
    final assembler = WsAssembler();
    try {
      while (!_incoming.isClosed) {
        while (true) {
          final frame = reader.take();
          if (frame == null) break;
          final msg = assembler.push(frame);
          if (msg == null) continue;
          if (msg.opcode == wsOpcodePing) {
            await _sink._writeFrame(wsOpcodePong, msg.payload);
            continue;
          }
          if (msg.opcode == wsOpcodePong) continue;
          if (msg.opcode == wsOpcodeClose) {
            _closeCode = msg.payload.length >= 2
                ? (msg.payload[0] << 8) | msg.payload[1]
                : wsCloseNormal;
            await _sink.close(_closeCode);
            return;
          }
          if (msg.opcode == wsOpcodeText) {
            _incoming.add(decodeTextPayload(msg.payload));
          } else if (msg.opcode == wsOpcodeBinary) {
            _incoming.add(msg.payload);
          }
        }
        final chunk = await read();
        if (chunk == null) break;
        if (chunk.isNotEmpty) reader.add(chunk);
      }
    } catch (e, st) {
      if (!_incoming.isClosed) _incoming.addError(e, st);
    } finally {
      _sink._closed = true;
      if (!_sink._done.isCompleted) _sink._done.complete();
      await closeTcp();
      if (!_incoming.isClosed) unawaited(_incoming.close());
    }
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => _ready.future;

  @override
  String? get protocol => null;

  int? _closeCode;
  String? _closeReason;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;
}

class _TailscaleWebSocketSink implements WebSocketSink {
  _TailscaleWebSocketSink({required this.write, required this.closeTcp});

  final TcpWrite write;
  final TcpClose closeTcp;
  TailscaleWebSocketChannel? _channel;
  final Completer<void> _done = Completer<void>();
  bool _closed = false;
  Future<void> _writes = Future.value();

  Future<void> _writeFrame(int opcode, List<int> payload) {
    final frame = encodeWsFrame(
      opcode: opcode,
      payload: payload,
      maskKey: randomMaskKey(),
    );
    final operation = _writes.then((_) => write(frame));
    _writes = operation.catchError((Object error, StackTrace stack) {
      final channel = _channel;
      if (channel != null && !channel._incoming.isClosed) {
        channel._incoming.addError(error, stack);
      }
      unawaited(closeTcp());
    });
    return operation;
  }

  @override
  void add(dynamic data) {
    if (_closed) return;
    if (data is String) {
      unawaited(
        _writeFrame(wsOpcodeText, utf8.encode(data)).catchError((_) {}),
      );
      return;
    }
    if (data is List<int>) {
      unawaited(_writeFrame(wsOpcodeBinary, data).catchError((_) {}));
      return;
    }
    throw ArgumentError('unsupported websocket payload ${data.runtimeType}');
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {
    if (_closed) return _done.future;
    _closed = true;
    _channel?._closeCode = closeCode ?? wsCloseNormal;
    _channel?._closeReason = closeReason;
    final reason = utf8.encode(closeReason ?? '');
    final payload = Uint8List(2 + reason.length);
    final code = closeCode ?? wsCloseNormal;
    payload[0] = (code >> 8) & 0xff;
    payload[1] = code & 0xff;
    payload.setRange(2, payload.length, reason);
    try {
      await _writeFrame(wsOpcodeClose, payload);
    } catch (_) {}
    await closeTcp();
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future get done => _done.future;
}

Future<Uint8List> _handshake(
  Uri url,
  TcpWrite write,
  TcpRead read,
  Random random,
) async {
  final keyBytes = List<int>.generate(16, (_) => random.nextInt(256));
  final key = base64Encode(keyBytes);
  final path =
      '${url.path.isEmpty ? '/' : url.path}${url.hasQuery ? '?${url.query}' : ''}';
  final hostname = url.host.contains(':') ? '[${url.host}]' : url.host;
  final host = url.hasPort ? '$hostname:${url.port}' : hostname;
  final req =
      'GET ${path.isEmpty ? '/' : path} HTTP/1.1\r\n'
      'Host: $host\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Key: $key\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      '\r\n';
  await write(Uint8List.fromList(utf8.encode(req)));

  const marker = [13, 10, 13, 10];
  final buf = BytesBuilder(copy: false);
  var headerEnd = -1;
  while (headerEnd < 0) {
    final chunk = await read();
    if (chunk == null || chunk.isEmpty) {
      throw StateError('websocket handshake closed');
    }
    buf.add(chunk);
    final all = buf.toBytes();
    for (var i = 0; i <= all.length - 4; i++) {
      if (all[i] == marker[0] &&
          all[i + 1] == marker[1] &&
          all[i + 2] == marker[2] &&
          all[i + 3] == marker[3]) {
        headerEnd = i;
        break;
      }
    }
    if (headerEnd > 16 * 1024 || (headerEnd < 0 && buf.length > 16 * 1024)) {
      throw StateError('websocket handshake too large');
    }
  }
  final all = buf.takeBytes();
  final headers = utf8.decode(all.sublist(0, headerEnd));
  if (!RegExp(r'^HTTP/1\.[01] 101(?: |\r\n)').hasMatch(headers) ||
      !RegExp(
        r'^Upgrade:\s*websocket\s*$',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(headers) ||
      !RegExp(
        r'^Connection:[^\r\n]*\bUpgrade\b',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(headers)) {
    throw StateError('websocket handshake rejected');
  }
  final accept = RegExp(
    r'Sec-WebSocket-Accept:\s*(\S+)',
    caseSensitive: false,
  ).firstMatch(headers);
  final expected = base64Encode(
    sha1
        .convert(utf8.encode('$key${'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'}'))
        .bytes,
  );
  if (accept == null || accept.group(1) != expected) {
    throw StateError('websocket accept mismatch');
  }
  final bodyStart = headerEnd + 4;
  if (bodyStart < all.length) {
    return Uint8List.fromList(all.sublist(bodyStart));
  }
  return Uint8List(0);
}
