import 'package:web_socket_channel/web_socket_channel.dart';

abstract class ConnectionTransport {
  WebSocketChannel get channel;

  Future<void> close({int? code, String? reason});
}

abstract class TransportFactory {
  Future<ConnectionTransport> connect(
    Uri url, {
    Duration timeout = const Duration(seconds: 5),
  });
}
