class OpenAudioMcService {
  static const _urlPrefix = 'https://session.openaudiomc.net/';

  void Function()? _onFailure;

  static bool isOpenAudioMcUrl(String url) {
    return url.startsWith(_urlPrefix);
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

  Future<void> disconnect() async {}

  Future<void> reconnect() async {}

  Future<void> dispose() async {}

  Future<void> softRefresh() async {}

  bool get isConnected => false;
  bool get isActive => false;
  String? get savedSessionUrl => null;
}
