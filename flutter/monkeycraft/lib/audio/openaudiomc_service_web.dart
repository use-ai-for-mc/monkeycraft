import 'package:url_launcher/url_launcher.dart';
import 'package:monkeycraft_client/audio/openaudiomc_url.dart';

typedef BrowserExternalUrlOpener = Future<bool> Function(Uri url);

class OpenAudioMcService {
  OpenAudioMcService({BrowserExternalUrlOpener? externalUrlOpener})
    : _externalUrlOpener = externalUrlOpener ?? _openExternalUrl;

  void Function()? _onFailure;
  final BrowserExternalUrlOpener _externalUrlOpener;
  String? _savedSessionUrl;
  bool _isActive = false;
  int _operationGeneration = 0;

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
    final uri = Uri.tryParse(sessionUrl);
    if (uri == null || !isOpenAudioMcUrl(sessionUrl)) {
      _onFailure?.call();
      return;
    }
    final generation = ++_operationGeneration;
    try {
      final opened = await _externalUrlOpener(uri);
      if (generation != _operationGeneration) return;
      if (opened) {
        _savedSessionUrl = sessionUrl;
        _isActive = true;
      } else {
        _isActive = false;
        _onFailure?.call();
      }
    } catch (_) {
      if (generation != _operationGeneration) return;
      _isActive = false;
      _onFailure?.call();
    }
  }

  Future<void> disconnect() async {
    _operationGeneration++;
    _isActive = false;
  }

  Future<void> reconnect() async {
    final url = _savedSessionUrl;
    if (url == null) return;
    await connect(url);
  }

  Future<void> dispose() async {
    _operationGeneration++;
    _isActive = false;
    _savedSessionUrl = null;
  }

  Future<void> softRefresh() async {}

  bool get isConnected => false;
  bool get isActive => _isActive;
  String? get savedSessionUrl => _savedSessionUrl;

  static Future<bool> _openExternalUrl(Uri url) {
    return launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }
}
