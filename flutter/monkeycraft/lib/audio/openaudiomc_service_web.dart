import 'package:url_launcher/url_launcher.dart';

class OpenAudioMcService {
  static const _urlPrefix = 'https://session.openaudiomc.net/';

  void Function()? _onFailure;
  String? _savedSessionUrl;
  bool _isActive = false;

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
    final uri = Uri.tryParse(sessionUrl);
    if (uri == null || !isOpenAudioMcUrl(sessionUrl)) {
      _onFailure?.call();
      return;
    }
    _savedSessionUrl = sessionUrl;
    _isActive = true;
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened) {
      _onFailure?.call();
    }
  }

  Future<void> disconnect() async {
    _isActive = false;
  }

  Future<void> reconnect() async {
    final url = _savedSessionUrl;
    if (url == null) return;
    await connect(url);
  }

  Future<void> dispose() async {
    _isActive = false;
    _savedSessionUrl = null;
  }

  Future<void> softRefresh() async {}

  bool get isConnected => _isActive;
  bool get isActive => _isActive;
  String? get savedSessionUrl => _savedSessionUrl;
}
