import 'package:monkeycraft_client/stream/transport/server_url.dart';

String webOriginServer(Uri page) {
  if (page.host.isEmpty) {
    return '';
  }
  return page.origin;
}

bool isHostedWebPage(Uri page) {
  final host = page.host.toLowerCase();
  return host == 'github.io' || host.endsWith('.github.io');
}

String webInitialServer(Uri page, String rememberedServer) {
  if (tryParseMonkeycraftServerUrl(rememberedServer) != null) {
    return rememberedServer;
  }
  if (isHostedWebPage(page)) return '';
  return webOriginServer(page);
}

String? webServerError(Uri page, String server) {
  final target = tryParseMonkeycraftServerUrl(server);
  if (target == null) return 'Enter a valid ws:// or wss:// server address';
  if (page.scheme == 'https' && target.scheme == 'ws') {
    return 'This HTTPS page cannot connect to a bare ws:// server. Use wss://, such as your Tailscale HTTPS address.';
  }
  return null;
}

class WebPasswordAutofill {
  WebPasswordAutofill(String target)
    : _target = canonicalMonkeycraftServerTarget(target);

  String? _target;

  bool get isActive => _target != null;

  bool clearForTarget(String target) {
    final next = canonicalMonkeycraftServerTarget(target);
    if (_target == null || _target == next) return false;
    _target = null;
    return true;
  }

  void clear() {
    _target = null;
  }

  void setTarget(String target) {
    _target = canonicalMonkeycraftServerTarget(target);
  }
}
