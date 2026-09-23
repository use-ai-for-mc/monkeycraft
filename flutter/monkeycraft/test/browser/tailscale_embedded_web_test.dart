@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_embedded.dart';

void main() {
  test(
    'browser leaves embedded Tailscale disabled and does not start a worker',
    () async {
      final client = TailscaleEmbeddedClient();

      expect(client.isSupported, isFalse);
      expect(client.gameTransportFactory, isNull);
      expect(await client.events.isEmpty, isTrue);
      expect((await client.status()).phase, 'unavailable');
      expect((await client.diagnostics()).available, isFalse);
      await client.start();
      expect(client.loginInteractive(), throwsA(isA<UnsupportedError>()));
    },
  );
}
