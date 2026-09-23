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
      expect(client.gameTransportFactory, isNotNull);
      expect((await client.status()).phase, 'stopped');
      expect((await client.diagnostics()).available, isFalse);
      expect(client.start(), throwsA(isA<StateError>()));
    },
  );
}
