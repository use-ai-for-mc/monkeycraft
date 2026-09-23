export 'tailscale_models.dart';
export 'tailscale_embedded_stub.dart'
    if (dart.library.io) 'tailscale_embedded_io.dart'
    if (dart.library.html) 'tailscale_embedded_web_disabled.dart';
