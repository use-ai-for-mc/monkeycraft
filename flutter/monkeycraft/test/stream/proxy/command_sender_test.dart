import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';

import 'package:monkeycraft_client/stream/proxy/command_sender.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';

class MockWebSocketChannel implements WebSocketChannel {
  final List<String> sentMessages = [];
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  late final MockWebSocketSink _sink;

  MockWebSocketChannel() {
    _sink = MockWebSocketSink(sentMessages);
  }

  @override
  MockWebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockWebSocketSink implements WebSocketSink {
  final List<String> sentMessages;
  MockWebSocketSink(this.sentMessages);

  @override
  void add(dynamic data) {
    sentMessages.add(data as String);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CommandSender sender;
  late MockWebSocketChannel mockChannel;

  setUp(() {
    sender = CommandSender();
    mockChannel = MockWebSocketChannel();
  });

  group('CommandSender', () {
    test('trySendCommand returns false when not attached', () {
      expect(sender.trySendCommand({'type': 'PING'}), isFalse);
    });

    test('trySendCommand returns false when not authenticated', () {
      sender.attach(mockChannel);
      expect(sender.trySendCommand({'type': 'PING'}), isFalse);
    });

    test('trySendCommand sends when attached and authenticated', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      final result = sender.trySendCommand({'type': 'PING'});
      expect(result, isTrue);
      expect(mockChannel.sentMessages.length, 1);
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'PING');
    });

    test('detach clears channel and authentication', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.detach();
      expect(sender.trySendCommand({'type': 'PING'}), isFalse);
    });

    test('sendClientStatus sends correct format for streaming', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.sendClientStatus(
        ClientMode.streaming,
        width: 320,
        height: 240,
        fps: 20,
      );
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'CLIENT_STATUS');
      expect(decoded['mode'], 'STREAMING');
      expect(decoded['width'], 320);
      expect(decoded['height'], 240);
      expect(decoded['fps'], 20);
    });

    test('sendClientStatus sends correct format for chat', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.sendClientStatus(ClientMode.chat);
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'CLIENT_STATUS');
      expect(decoded['mode'], 'CHAT');
      expect(decoded.containsKey('width'), isFalse);
    });

    test('sendClientStatus invokes onClientStatusSent callback', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      int? reportedFps;
      sender.onClientStatusSent = (fps) => reportedFps = fps;
      sender.sendClientStatus(ClientMode.streaming, fps: 15);
      expect(reportedFps, 15);
    });

    test('trySendRunCommand rejects empty commands', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      expect(sender.trySendRunCommand(''), isFalse);
      expect(sender.trySendRunCommand('   '), isFalse);
    });

    test('trySendRunCommand rejects non-slash commands', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      expect(sender.trySendRunCommand('hello'), isFalse);
    });

    test('trySendRunCommand sends slash commands', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      final result = sender.trySendRunCommand('/warp home');
      expect(result, isTrue);
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'RUN_COMMAND');
      expect(decoded['command'], '/warp home');
    });

    test('trySendChatMessage rejects empty messages', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      expect(sender.trySendChatMessage(''), isFalse);
      expect(sender.trySendChatMessage('   '), isFalse);
    });

    test('trySendChatMessage sends trimmed messages', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.trySendChatMessage('  hello world  ');
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'SEND_CHAT');
      expect(decoded['message'], 'hello world');
    });

    test('sendPing sends ping command', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.sendPing();
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'PING');
    });

    test('requestKeyframe sends keyframe request', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.requestKeyframe();
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'REQUEST_KEYFRAME');
    });

    test('sendScreenTap sends normalized coordinates', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.sendScreenTap(0.5, 0.75);
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['type'], 'SCREEN_TAP');
      expect(decoded['normalizedX'], 0.5);
      expect(decoded['normalizedY'], 0.75);
    });

    test('sendClientStatus includes autoFaceMovement when provided', () {
      sender.attach(mockChannel);
      sender.setAuthenticated(true);
      sender.sendClientStatus(ClientMode.streaming, autoFaceMovement: true);
      final decoded = jsonDecode(mockChannel.sentMessages.first);
      expect(decoded['autoFaceMovement'], true);
    });
  });
}
