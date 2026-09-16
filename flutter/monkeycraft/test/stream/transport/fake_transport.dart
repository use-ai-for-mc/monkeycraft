import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this.sent);

  final List<dynamic> sent;
  final Completer<void> _done = Completer<void>();
  int? closeCode;
  String? closeReason;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future close([int? code, String? reason]) {
    closeCode = code;
    closeReason = reason;
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future get done => _done.future;
}

class FakeWebSocketChannel implements WebSocketChannel {
  FakeWebSocketChannel() {
    sink = FakeWebSocketSink(sent);
  }

  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<dynamic> sent = [];
  @override
  late final FakeWebSocketSink sink;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => sink.closeCode;

  @override
  String? get closeReason => sink.closeReason;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnectionTransport implements ConnectionTransport {
  FakeConnectionTransport(this.channel);

  @override
  final FakeWebSocketChannel channel;

  var closeCount = 0;

  @override
  Future<void> close({int? code, String? reason}) async {
    closeCount += 1;
    await channel.sink.close(code, reason);
  }
}

class FakeTransportFactory implements TransportFactory {
  FakeTransportFactory({this.onConnect});

  final Future<ConnectionTransport> Function(Uri url, Duration timeout)?
  onConnect;
  final List<Uri> connectedUrls = [];
  FakeConnectionTransport? lastTransport;

  @override
  Future<ConnectionTransport> connect(
    Uri url, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    connectedUrls.add(url);
    if (onConnect != null) {
      return onConnect!(url, timeout);
    }
    lastTransport = FakeConnectionTransport(FakeWebSocketChannel());
    return lastTransport!;
  }
}
