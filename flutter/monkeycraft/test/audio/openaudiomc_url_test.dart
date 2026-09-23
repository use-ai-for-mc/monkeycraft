import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service_io.dart' as io;
import 'package:monkeycraft_client/audio/openaudiomc_service_stub.dart' as stub;

void main() {
  const accepted = [
    'https://session.openaudiomc.net#opaque',
    'https://session.openaudiomc.net/#opaque',
    'https://session.openaudiomc.net:443#opaque',
  ];
  const rejected = [
    'http://session.openaudiomc.net#opaque',
    'https://session.openaudiomc.net:444#opaque',
    'https://session.openaudiomc.net.evil.example#opaque',
    'https://session.openaudiomc.net@evil.example#opaque',
    'https://user@session.openaudiomc.net#opaque',
    'https://session.openaudiomc.net%2eevil.example#opaque',
  ];

  test('IO and stub accept the exact HTTPS OpenAudioMc session host', () {
    for (final url in accepted) {
      expect(io.OpenAudioMcService.isOpenAudioMcUrl(url), isTrue, reason: url);
      expect(
        stub.OpenAudioMcService.isOpenAudioMcUrl(url),
        isTrue,
        reason: url,
      );
    }
  });

  test('IO and stub reject unsafe or lookalike OpenAudioMc URLs', () {
    for (final url in rejected) {
      expect(io.OpenAudioMcService.isOpenAudioMcUrl(url), isFalse, reason: url);
      expect(
        stub.OpenAudioMcService.isOpenAudioMcUrl(url),
        isFalse,
        reason: url,
      );
    }
  });
}
