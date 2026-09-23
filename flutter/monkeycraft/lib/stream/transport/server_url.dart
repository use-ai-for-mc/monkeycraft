Uri parseMonkeycraftServerUrl(String server) {
  final uri = tryParseMonkeycraftServerUrl(server);
  if (uri == null) throw FormatException('Invalid server address', server);
  return uri;
}

Uri? tryParseMonkeycraftServerUrl(String server) {
  server = server.trim();
  if (server.isEmpty) return null;
  if (server.contains(RegExp(r'\s'))) return null;
  try {
    final lower = server.toLowerCase();
    Uri uri;
    if (lower.startsWith('https://')) {
      uri = Uri.parse(
        server.replaceFirst(
          RegExp(r'https://', caseSensitive: false),
          'wss://',
        ),
      );
    } else if (lower.startsWith('http://')) {
      uri = Uri.parse(
        server.replaceFirst(RegExp(r'http://', caseSensitive: false), 'ws://'),
      );
    } else if (lower.startsWith('wss://') || lower.startsWith('ws://')) {
      uri = Uri.parse(server);
    } else {
      final hasPort = RegExp(r':\d+$').hasMatch(server);
      uri = Uri.parse('${hasPort ? 'ws' : 'wss'}://$server');
    }
    if ((uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: uri.path == '/' ? '' : uri.path,
    );
  } on FormatException {
    return null;
  }
}

String? canonicalMonkeycraftServerTarget(String server) =>
    tryParseMonkeycraftServerUrl(server)?.toString();
