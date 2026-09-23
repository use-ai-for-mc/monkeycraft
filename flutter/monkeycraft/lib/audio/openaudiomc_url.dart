bool isOpenAudioMcSessionUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  return uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'session.openaudiomc.net' &&
      uri.userInfo.isEmpty &&
      uri.port == 443;
}
