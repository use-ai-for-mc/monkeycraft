import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

class DirectWebSocketTransport implements ConnectionTransport {
  DirectWebSocketTransport(this.channel);

  @override
  final WebSocketChannel channel;

  @override
  Future<void> close({int? code, String? reason}) async {
    await channel.sink.close(code ?? status.normalClosure, reason);
  }
}

class DirectWebSocketTransportFactory implements TransportFactory {
  const DirectWebSocketTransportFactory();

  @override
  Future<ConnectionTransport> connect(
    Uri url, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final channel = WebSocketChannel.connect(url);
    await channel.ready.timeout(timeout);
    return DirectWebSocketTransport(channel);
  }
}
