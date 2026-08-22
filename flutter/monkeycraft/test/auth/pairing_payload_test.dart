import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/pairing_payload.dart';

void main() {
  group('PairingPayload', () {
    const fingerprint = 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789';

    test('parses a versioned pairing code', () {
      final payload = PairingPayload.parse(
        '{"v":2,"pw":"secret","fp":"$fingerprint"}',
      );

      expect(payload.password, 'secret');
      expect(payload.certificateSha256, fingerprint);
    });

    test('accepts a legacy password QR without a pin', () {
      final payload = PairingPayload.parse('legacy-secret');

      expect(payload.password, 'legacy-secret');
      expect(payload.certificateSha256, isNull);
    });

    test('accepts legacy passwords beginning with a brace', () {
      final payload = PairingPayload.parse('{legacy-secret');

      expect(payload.password, '{legacy-secret');
      expect(payload.certificateSha256, isNull);
    });

    test('rejects malformed structured codes', () {
      expect(
        () => PairingPayload.parse('{"v":2,"pw":"secret","fp":"bad"}'),
        throwsFormatException,
      );
    });
  });
}
