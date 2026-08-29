import 'package:monkeycraft_client/audio/mcparks_models.dart';

class McParksV1Service {
  void Function()? _onFailure;
  double _volume = 0.5;

  static bool isMcParksUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'mcparks.us' || host.endsWith('.mcparks.us');
  }

  void setInfoPacketHandler(
    void Function(Map<String, dynamic> infoPacket) handler,
  ) {}

  void setOnFailureHandler(void Function() handler) {
    _onFailure = handler;
  }

  Future<void> initialize() async {}

  Future<void> connect(String sessionUrl) async {
    _onFailure?.call();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
  }

  Future<void> disconnect() async {}

  Future<void> reconnect() async {}

  Future<void> dispose() async {}

  Future<void> softRefresh() async {}

  Future<List<McParksActiveTrack>> snapshotActive() async => const [];

  Future<bool> stopSoundByName(String name) async => false;

  bool get isConnected => false;
  bool get isActive => false;
  String? get savedSessionUrl => null;
  double get volume => _volume;
}
