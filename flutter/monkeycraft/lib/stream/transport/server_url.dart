Uri parseMonkeycraftServerUrl(String server) {
  server = server.trim();

  if (server.startsWith('https://')) {
    return Uri.parse(server.replaceFirst('https://', 'wss://'));
  }
  if (server.startsWith('http://')) {
    return Uri.parse(server.replaceFirst('http://', 'ws://'));
  }
  if (server.startsWith('wss://') || server.startsWith('ws://')) {
    return Uri.parse(server);
  }

  final hasPort = RegExp(r':\d+$').hasMatch(server);

  if (hasPort) {
    return Uri.parse('ws://$server');
  }
  return Uri.parse('wss://$server');
}
