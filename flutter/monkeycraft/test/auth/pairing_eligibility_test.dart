import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/pairing_eligibility.dart';

void main() {
  group('isPairingEligibleServer', () {
    test('loopback and RFC1918 are eligible', () {
      expect(isPairingEligibleServer('127.0.0.1:9600'), isTrue);
      expect(isPairingEligibleServer('localhost:9600'), isTrue);
      expect(isPairingEligibleServer('10.0.0.8:9600'), isTrue);
      expect(isPairingEligibleServer('192.168.1.20:9600'), isTrue);
      expect(isPairingEligibleServer('172.16.4.1:9600'), isTrue);
      expect(isPairingEligibleServer('169.254.1.1:9600'), isTrue);
    });

    test('Tailscale CGNAT is eligible', () {
      expect(isPairingEligibleServer('100.64.1.2:9600'), isTrue);
      expect(isPairingEligibleServer('100.127.0.1:9600'), isTrue);
    });

    test('public addresses are not eligible', () {
      expect(isPairingEligibleServer('8.8.8.8:9600'), isFalse);
      expect(isPairingEligibleServer('1.1.1.1'), isFalse);
      expect(isPairingEligibleServer('example.ngrok-free.app'), isFalse);
      expect(isPairingEligibleServer('desk.tail1234.ts.net'), isFalse);
      expect(isPairingEligibleServer('something.ts.net'), isFalse);
      expect(isPairingEligibleServer('100.63.255.255:9600'), isFalse);
      expect(isPairingEligibleServer('100.128.0.1:9600'), isFalse);
    });
  });
}
