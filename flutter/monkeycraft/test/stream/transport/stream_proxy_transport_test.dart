import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';

import 'fake_transport.dart';

String _hmac(String key, String data) {
  final digest = Hmac(sha256, utf8.encode(key)).convert(utf8.encode(data));
  return base64Encode(digest.bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ready and AUTH_OK complete start', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('127.0.0.1:9600', 'secret');
    await Future<void>.delayed(Duration.zero);

    final transport = factory.lastTransport!;
    transport.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 'server-salt'}),
    );
    await Future<void>.delayed(Duration.zero);
    transport.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));

    await started;
    expect(proxy.isConnected, isTrue);
    expect(factory.connectedUrls.single, Uri.parse('ws://127.0.0.1:9600'));
    final auth = jsonDecode(transport.channel.sent.single as String);
    expect(auth['type'], 'AUTH');
    expect(auth['signature'], _hmac('secret', 'server-salt${auth['salt']}'));
    await proxy.stop();
  });

  test('AUTH_RESPONSE failure throws AuthFailureException', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('127.0.0.1:9600', 'secret');
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 's'}),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({
        'type': 'AUTH_RESPONSE',
        'success': false,
        'message': 'bad password',
      }),
    );

    await expectLater(
      started,
      throwsA(
        isA<AuthFailureException>().having(
          (e) => e.message,
          'message',
          'bad password',
        ),
      ),
    );
  });

  test('invalid signature is flagged on AuthFailureException', () {
    expect(AuthFailureException('Invalid signature').isInvalidSignature, isTrue);
    expect(AuthFailureException('bad password').isInvalidSignature, isFalse);
  });

  test('binary frames after auth reach accessUnits', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('127.0.0.1:9600', 'pw');
    await Future<void>.delayed(Duration.zero);
    final incoming = factory.lastTransport!.channel.incoming;
    incoming.add(jsonEncode({'type': 'HELLO', 'salt': 's'}));
    await Future<void>.delayed(Duration.zero);
    incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;

    final frames = <Uint8List>[];
    final sub = proxy.accessUnits.listen(frames.add);
    incoming.add(Uint8List.fromList([0, 1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(frames, isNotEmpty);
    await sub.cancel();
    await proxy.stop();
  });

  test('text CHAT_MESSAGE after auth is forwarded', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('host:1', 'pw');
    await Future<void>.delayed(Duration.zero);
    final incoming = factory.lastTransport!.channel.incoming;
    incoming.add(jsonEncode({'type': 'HELLO', 'salt': 's'}));
    await Future<void>.delayed(Duration.zero);
    incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;

    final chats = <String>[];
    final sub = proxy.chatMessages.listen((m) => chats.add(m.message));
    incoming.add(
      jsonEncode({
        'type': 'CHAT_MESSAGE',
        'sender': 'steve',
        'message': 'hi',
        'timestamp': 1,
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(chats, ['hi']);
    await sub.cancel();
    await proxy.stop();
  });

  test('send after auth uses the transport sink', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('host:1', 'pw');
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 's'}),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    expect(proxy.trySendCommand({'type': 'PING'}), isTrue);
    final last = jsonDecode(factory.lastTransport!.channel.sent.last as String);
    expect(last['type'], 'PING');
    await proxy.stop();
  });

  test('stop closes the transport', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('host:1', 'pw');
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 's'}),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    final transport = factory.lastTransport!;
    await proxy.stop();
    expect(transport.closeCount, 1);
    expect(proxy.isConnected, isFalse);
  });

  test('connect timeout surfaces', () async {
    final factory = FakeTransportFactory(
      onConnect: (url, timeout) async {
        await Future<void>.delayed(timeout);
        throw TimeoutException('connect');
      },
    );
    final proxy = StreamProxy(transportFactory: factory);
    await expectLater(
      proxy.start(
        '127.0.0.1:9600',
        'pw',
        connectTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('auth timeout surfaces when HELLO never arrives', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    await expectLater(
      proxy.start(
        '127.0.0.1:9600',
        'pw',
        authTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('cancel via stop while connecting closes transport', () async {
    final gate = Completer<void>();
    late FakeConnectionTransport transport;
    final factory = FakeTransportFactory(
      onConnect: (url, timeout) async {
        await gate.future;
        transport = FakeConnectionTransport(FakeWebSocketChannel());
        return transport;
      },
    );
    final proxy = StreamProxy(transportFactory: factory);
    final connect = proxy.start(
      'host:1',
      'pw',
      authTimeout: const Duration(milliseconds: 50),
    );
    await Future<void>.delayed(Duration.zero);
    unawaited(proxy.stop());
    gate.complete();
    try {
      await connect;
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);
    expect(proxy.isConnected, isFalse);
  });

  test('socket close during auth fails start', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start('host:1', 'pw');
    await Future<void>.delayed(Duration.zero);
    await factory.lastTransport!.channel.incoming.close();
    await expectLater(started, throwsA(isA<StateError>()));
  });

  test('empty password with pairing HELLO waits then AUTH after PAIR_OK', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    PairingCode? shown;
    String? saved;
    final started = proxy.start(
      '127.0.0.1:9600',
      '',
      pairIfNeeded: true,
      onPairingCode: (code) => shown = code,
      onPairedPassword: (password) => saved = password,
      authTimeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);
    final incoming = factory.lastTransport!.channel.incoming;
    incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 'server-salt', 'pairing': true}),
    );
    await Future<void>.delayed(Duration.zero);
    final first = jsonDecode(
      factory.lastTransport!.channel.sent.single as String,
    );
    expect(first['type'], 'AUTH');
    expect(first['mode'], 'PAIR');
    incoming.add(
      jsonEncode({'type': 'PAIR_WAITING', 'code': 'ABCD2345', 'ttlMs': 180000}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(shown?.displayCode, 'ABCD-2345');
    incoming.add(jsonEncode({'type': 'PAIR_OK', 'password': 'long-secret'}));
    await Future<void>.delayed(Duration.zero);
    expect(saved, 'long-secret');
    incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    expect(proxy.isConnected, isTrue);
    await proxy.stop();
  });

  test('filled password sends HMAC AUTH even if HELLO.pairing is true', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start(
      'something.ts.net',
      'secret',
      pairIfNeeded: true,
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 'server-salt', 'pairing': true}),
    );
    await Future<void>.delayed(Duration.zero);
    final auth = jsonDecode(
      factory.lastTransport!.channel.sent.single as String,
    );
    expect(auth['type'], 'AUTH');
    expect(auth.containsKey('mode'), isFalse);
    expect(auth['signature'], _hmac('secret', 'server-salt${auth['salt']}'));
    factory.lastTransport!.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    expect(proxy.isConnected, isTrue);
    await proxy.stop();
  });

  test('does not send PAIR when HELLO.pairing is false', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start(
      '8.8.8.8:9600',
      '',
      pairIfNeeded: true,
      authTimeout: const Duration(milliseconds: 200),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'HELLO', 'salt': 'server-salt', 'pairing': false}),
    );
    await expectLater(started, throwsA(isA<PairingUnavailableException>()));
    expect(factory.lastTransport!.channel.sent, isEmpty);
    await proxy.stop();
  });

  test('HELLO keyId lookup HMACs even with empty start password', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    String? boundKey;
    String? boundPassword;
    final started = proxy.start(
      '127.0.0.1:9600',
      '',
      pairIfNeeded: true,
      lookupPassword: (keyId) => keyId == 'kid-1' ? 'stored-secret' : null,
      onBoundPassword: (keyId, password) {
        boundKey = keyId;
        boundPassword = password;
      },
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({
        'type': 'HELLO',
        'salt': 'server-salt',
        'pairing': true,
        'keyId': 'kid-1',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final auth = jsonDecode(
      factory.lastTransport!.channel.sent.single as String,
    );
    expect(auth['type'], 'AUTH');
    expect(auth.containsKey('mode'), isFalse);
    expect(
      auth['signature'],
      _hmac('stored-secret', 'server-salt${auth['salt']}'),
    );
    factory.lastTransport!.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    expect(boundKey, 'kid-1');
    expect(boundPassword, 'stored-secret');
    await proxy.stop();
  });

  test('unknown HELLO keyId does not use another stored password', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start(
      '127.0.0.1:9600',
      '',
      pairIfNeeded: true,
      lookupPassword: (keyId) => keyId == 'other' ? 'stale' : null,
      authTimeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({
        'type': 'HELLO',
        'salt': 'server-salt',
        'pairing': true,
        'keyId': 'kid-new',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final first = jsonDecode(
      factory.lastTransport!.channel.sent.single as String,
    );
    expect(first['type'], 'AUTH');
    expect(first['mode'], 'PAIR');
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({'type': 'PAIR_OK', 'password': 'paired'}),
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(jsonEncode({'type': 'AUTH_OK'}));
    await started;
    await proxy.stop();
  });

  test('lookup wins over a different typed password', () async {
    final factory = FakeTransportFactory();
    final proxy = StreamProxy(transportFactory: factory);
    final started = proxy.start(
      '127.0.0.1:9600',
      'typed-stale',
      lookupPassword: (keyId) => keyId == 'kid-1' ? 'stored-secret' : null,
    );
    await Future<void>.delayed(Duration.zero);
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({
        'type': 'HELLO',
        'salt': 'server-salt',
        'keyId': 'kid-1',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final auth = jsonDecode(
      factory.lastTransport!.channel.sent.single as String,
    );
    expect(auth['signature'], _hmac('stored-secret', 'server-salt${auth['salt']}'));
    factory.lastTransport!.channel.incoming.add(
      jsonEncode({
        'type': 'AUTH_RESPONSE',
        'success': false,
        'message': 'Invalid signature',
      }),
    );
    await expectLater(
      started,
      throwsA(
        isA<AuthFailureException>()
            .having((e) => e.isInvalidSignature, 'invalid', isTrue)
            .having((e) => e.keyId, 'keyId', 'kid-1'),
      ),
    );
  });
}
