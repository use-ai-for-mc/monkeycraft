import 'package:url_launcher/url_launcher.dart';
import 'package:monkeycraft_client/audio/mcparks_models.dart';

typedef McParksBrowserExternalUrlOpener = Future<bool> Function(Uri url);

class McParksV1Service {
  McParksV1Service({McParksBrowserExternalUrlOpener? externalUrlOpener})
    : _externalUrlOpener = externalUrlOpener ?? _openExternalUrl;

  void Function()? _onFailure;
  final McParksBrowserExternalUrlOpener _externalUrlOpener;
  double _volume = 0.5;
  String? _savedSessionUrl;
  bool _active = false;
  int _operationGeneration = 0;

  static bool isMcParksUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return uri.userInfo.isEmpty &&
        uri.port == 443 &&
        (host == 'mcparks.us' || host.endsWith('.mcparks.us'));
  }

  void setInfoPacketHandler(
    void Function(Map<String, dynamic> infoPacket) handler,
  ) {}

  void setOnFailureHandler(void Function() handler) {
    _onFailure = handler;
  }

  Future<void> initialize() async {}

  Future<void> connect(String sessionUrl) async {
    if (!isMcParksUrl(sessionUrl)) {
      _onFailure?.call();
      return;
    }
    final generation = ++_operationGeneration;
    try {
      final opened = await _externalUrlOpener(Uri.parse(sessionUrl));
      if (generation != _operationGeneration) return;
      _active = opened;
      if (_active) {
        _savedSessionUrl = sessionUrl;
      } else {
        _onFailure?.call();
      }
    } catch (_) {
      if (generation != _operationGeneration) return;
      _active = false;
      _onFailure?.call();
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
  }

  Future<void> disconnect() async {
    _operationGeneration++;
    _active = false;
  }

  Future<void> reconnect() async {
    final url = _savedSessionUrl;
    if (url != null) await connect(url);
  }

  Future<void> dispose() async {
    _operationGeneration++;
    _active = false;
    _savedSessionUrl = null;
  }

  Future<void> softRefresh() async {}

  Future<List<McParksActiveTrack>> snapshotActive() async => const [];

  Future<bool> stopSoundByName(String name) async => false;

  bool get isConnected => false;
  bool get isActive => _active;
  String? get savedSessionUrl => _savedSessionUrl;
  double get volume => _volume;

  static Future<bool> _openExternalUrl(Uri url) {
    return launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }
}
