import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:monkeycraft_client/stream/transport/connection_transport.dart';
import 'package:monkeycraft_client/stream/transport/tailscale_web_channel.dart';

typedef TailscaleDial = Future<TailscaleTcpConn> Function(Uri url);

class TailscaleTcpConn {
  const TailscaleTcpConn({
    required this.write,
    required this.read,
    required this.close,
  });

  final Future<void> Function(Uint8List bytes) write;
  final Future<Uint8List?> Function() read;
  final Future<void> Function() close;
}

class TailscaleWebTransport implements ConnectionTransport {
  TailscaleWebTransport(this.channel);

  @override
  final WebSocketChannel channel;

  @override
  Future<void> close({int? code, String? reason}) async {
    await channel.sink.close(code ?? status.normalClosure, reason);
  }
}

class TailscaleWebTransportFactory implements TransportFactory {
  const TailscaleWebTransportFactory(this._dial);

  final TailscaleDial _dial;

  @override
  Future<ConnectionTransport> connect(
    Uri url, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (url.scheme != 'ws') {
      throw ArgumentError(
        'The Tailscale transport requires a private game address.',
      );
    }
    final pending = _dial(url);
    final TailscaleTcpConn conn;
    try {
      conn = await pending.timeout(timeout);
    } on TimeoutException {
      unawaited(pending.then((late) => late.close()).catchError((_) {}));
      rethrow;
    }
    final channel = await TailscaleWebSocketChannel.connect(
      url: url,
      write: conn.write,
      read: conn.read,
      close: conn.close,
      timeout: timeout,
    );
    await channel.ready.timeout(timeout);
    return TailscaleWebTransport(channel);
  }
}
