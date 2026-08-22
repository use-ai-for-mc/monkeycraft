import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeChannel implements WebSocketChannel {
  final _controller = StreamController<dynamic>();
  late final _FakeSink _sink = _FakeSink(_controller);
  final Future<void> _ready;

  _FakeChannel({Future<void>? ready}) : _ready = ready ?? Future.value();

  @override
  Future<void> get ready => _ready;

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  void addFromServer(Object message) => _controller.add(message);

  void addErrorFromServer(Object error) => _controller.addError(error);

  Future<void> closeFromServer() => _controller.close();

  List<Object> get sent => _sink.sent;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  final StreamController<dynamic> controller;
  final List<Object> sent = [];

  _FakeSink(this.controller);

  @override
  void add(Object? data) => sent.add(data!);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!controller.isClosed) await controller.close();
  }

  @override
  Future<void> get done => controller.done;
}

void main() {
  const password = 'test-password';
  const serverSalt = 'server-salt';

  String signature(String data) {
    return base64Encode(
      Hmac(sha256, utf8.encode(password)).convert(utf8.encode(data)).bytes,
    );
  }

  Future<Map<String, dynamic>> sendHello(_FakeChannel channel) async {
    channel.addFromServer(jsonEncode({'type': 'HELLO', 'salt': serverSalt}));
    await pumpEventQueue();
    return jsonDecode(channel.sent.single as String) as Map<String, dynamic>;
  }

  test('accepts a valid reciprocal server signature', () async {
    final channel = _FakeChannel();
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) =>
              channel,
    );
    final starting = proxy.start('wss://example.com', password);
    await pumpEventQueue();

    final auth = await sendHello(channel);
    expect(auth['type'], 'AUTH');
    expect(auth['protocolVersion'], 3);
    final clientSalt = auth['salt'] as String;
    channel.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': signature('$clientSalt$serverSalt'),
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );

    await starting;
    expect(proxy.isConnected, isTrue);
    await proxy.stop();
  });

  test('rejects an invalid reciprocal server signature', () async {
    final channel = _FakeChannel();
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) =>
              channel,
    );
    final starting = proxy.start('wss://example.com', password);
    await pumpEventQueue();

    await sendHello(channel);
    channel.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': 'invalid',
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );

    await expectLater(starting, throwsA(isA<AuthFailureException>()));
    expect(proxy.isConnected, isFalse);
  });

  test('rejects explicit plaintext WebSocket URLs', () async {
    final proxy = StreamProxy();

    await expectLater(
      proxy.start('ws://example.com:9600', password),
      throwsFormatException,
    );
    await expectLater(
      proxy.start('HTTP://example.com:9600', password),
      throwsFormatException,
    );
  });

  test('accepts mixed-case secure URL schemes', () async {
    final channel = _FakeChannel();
    late Uri connectedUrl;
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) {
            connectedUrl = url;
            return channel;
          },
    );
    final starting = proxy.start('WSS://Example.com:9600/path', password);
    await pumpEventQueue();

    final auth = await sendHello(channel);
    final clientSalt = auth['salt'] as String;
    channel.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': signature('$clientSalt$serverSalt'),
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );

    await starting;
    expect(connectedUrl.scheme, 'wss');
    expect(connectedUrl.host, 'example.com');
    expect(connectedUrl.port, 9600);
    expect(connectedUrl.path, '/path');
    await proxy.stop();
  });

  test('ignores late completion from a replaced channel', () async {
    final first = _FakeChannel();
    final second = _FakeChannel();
    var connectionCount = 0;
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) {
            return connectionCount++ == 0 ? first : second;
          },
    );

    final firstStart = proxy.start('wss://example.com', password);
    await pumpEventQueue();
    final firstAuth = await sendHello(first);
    final firstClientSalt = firstAuth['salt'] as String;
    first.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': signature('$firstClientSalt$serverSalt'),
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );
    await firstStart;

    first.addErrorFromServer(StateError('old connection failed'));
    await pumpEventQueue();
    expect(proxy.isConnected, isFalse);

    final secondStart = proxy.start('wss://example.com', password);
    await pumpEventQueue();
    final secondAuth = await sendHello(second);
    final secondClientSalt = secondAuth['salt'] as String;
    second.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': signature('$secondClientSalt$serverSalt'),
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );
    await secondStart;
    expect(proxy.isConnected, isTrue);

    await first.closeFromServer();
    await pumpEventQueue();
    expect(proxy.isConnected, isTrue);
    await proxy.stop();
  });

  test('stop cancels a connection attempt waiting for readiness', () async {
    final ready = Completer<void>();
    final first = _FakeChannel(ready: ready.future);
    final second = _FakeChannel();
    var connectionCount = 0;
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) {
            return connectionCount++ == 0 ? first : second;
          },
    );
    final starting = expectLater(
      proxy.start('wss://example.com', password),
      throwsA(isA<StateError>()),
    );
    await pumpEventQueue();

    await proxy.stop();
    await starting;

    final restarted = proxy.start('wss://example.com', password);
    await pumpEventQueue();
    final auth = await sendHello(second);
    final clientSalt = auth['salt'] as String;
    second.addFromServer(
      jsonEncode({
        'type': 'AUTH_OK',
        'signature': signature('$clientSalt$serverSalt'),
        'protocolVersion': 3,
        'capabilities': ['TLS'],
      }),
    );
    await restarted;
    expect(proxy.isConnected, isTrue);
    await proxy.stop();
  });

  test('rejects different credentials during an active start', () async {
    final ready = Completer<void>();
    final channel = _FakeChannel(ready: ready.future);
    final proxy = StreamProxy(
      connectWebSocket:
          (Uri url, {HttpClient? customClient, Duration? connectTimeout}) =>
              channel,
    );
    final firstStart = expectLater(
      proxy.start('wss://example.com', password),
      throwsA(isA<StateError>()),
    );
    await pumpEventQueue();

    await expectLater(
      proxy.start('wss://other.example.com', password),
      throwsA(isA<StateError>()),
    );
    await proxy.stop();
    await firstStart;
  });
}
