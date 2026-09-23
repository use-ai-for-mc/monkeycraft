import 'package:monkeycraft_client/audio/openaudiomc_url.dart';

class OpenAudioMcService {
  void Function()? _onFailure;

  static bool isOpenAudioMcUrl(String url) {
    return isOpenAudioMcSessionUrl(url);
  }

  void setInfoPacketHandler(
    void Function(Map<String, dynamic> infoPacket) handler,
  ) {}

  void setOnFailureHandler(void Function() handler) {
    _onFailure = handler;
  }

  void reportState() {}

  Future<void> initialize() async {}

  Future<void> connect(String sessionUrl) async {
    _onFailure?.call();
  }

  Future<void> disconnect() async {}

  Future<void> reconnect() async {}

  Future<void> dispose() async {}

  Future<void> softRefresh() async {}

  bool get isConnected => false;
  bool get isActive => false;
  String? get savedSessionUrl => null;
}
