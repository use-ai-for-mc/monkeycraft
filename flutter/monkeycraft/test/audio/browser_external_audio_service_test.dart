import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/mcparks_v1_service_web.dart'
    as mcparks;
import 'package:monkeycraft_client/audio/openaudiomc_service_web.dart'
    as openaudio;

void main() {
  test('OpenAudioMc web validates the exact session origin', () {
    expect(
      openaudio.OpenAudioMcService.isOpenAudioMcUrl(
        'https://session.openaudiomc.net/#session',
      ),
      isTrue,
    );
    for (final invalid in [
      'https://session.openaudiomc.net.evil.example/#session',
      'https://attacker@session.openaudiomc.net/#session',
      'https://session.openaudiomc.net:444/#session',
    ]) {
      expect(openaudio.OpenAudioMcService.isOpenAudioMcUrl(invalid), isFalse);
    }
  });

  test('MCParks web permits only pinned HTTPS origins', () {
    expect(
      mcparks.McParksV1Service.isMcParksUrl('https://mcparks.us/audio'),
      isTrue,
    );
    expect(
      mcparks.McParksV1Service.isMcParksUrl('https://audio.mcparks.us/audio'),
      isTrue,
    );
    for (final invalid in [
      'http://mcparks.us/audio',
      'https://attacker@mcparks.us/audio',
      'https://mcparks.us:444/audio',
      'https://mcparks.us.evil.example/audio',
    ]) {
      expect(mcparks.McParksV1Service.isMcParksUrl(invalid), isFalse);
    }
  });

  test(
    'OpenAudioMc reports a blocked popup without retaining an active state',
    () async {
      var failures = 0;
      final service = openaudio.OpenAudioMcService(
        externalUrlOpener: (_) async => false,
      )..setOnFailureHandler(() => failures++);

      await service.connect('https://session.openaudiomc.net/#session');

      expect(failures, 1);
      expect(service.isActive, isFalse);
      expect(service.savedSessionUrl, isNull);
    },
  );

  test(
    'MCParks records an accepted external launch without claiming connection',
    () async {
      final service = mcparks.McParksV1Service(
        externalUrlOpener: (_) async => true,
      );

      await service.connect('https://mcparks.us/audio?user=test');

      expect(service.isActive, isTrue);
      expect(service.isConnected, isFalse);
      expect(service.savedSessionUrl, 'https://mcparks.us/audio?user=test');
    },
  );

  test(
    'a late external launch cannot revive an audio status after disconnect',
    () async {
      final pending = Completer<bool>();
      final service = mcparks.McParksV1Service(
        externalUrlOpener: (_) => pending.future,
      );

      final opening = service.connect('https://mcparks.us/audio?user=test');
      await service.disconnect();
      pending.complete(true);
      await opening;

      expect(service.isActive, isFalse);
      expect(service.savedSessionUrl, isNull);
    },
  );
}
