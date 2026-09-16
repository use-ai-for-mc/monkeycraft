import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/login_auth_policy.dart';
import 'package:monkeycraft_client/auth/pairing_eligibility.dart';

void main() {
  group('LoginAuthPolicy', () {
    test('LAN empty defaults to pair', () {
      const mode = LoginAuthMode.pair;
      expect(
        LoginAuthPolicy.showPasswordField(mode: mode, hasPassword: false),
        isFalse,
      );
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isTrue,
      );
      expect(
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isFalse,
      );
    });

    test('saved password stays in password mode after last character deleted', () {
      const mode = LoginAuthMode.password;
      expect(
        LoginAuthPolicy.showPasswordField(mode: mode, hasPassword: false),
        isTrue,
      );
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isFalse,
      );
      expect(
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isTrue,
      );
    });

    test('public and MagicDNS hostnames default to password, not pair', () {
      expect(isPairingEligibleServer('something.ts.net'), isFalse);
      expect(isPairingEligibleServer('desk.tail1234.ts.net'), isFalse);
      expect(isPairingEligibleServer('example.ngrok-free.app'), isFalse);
      final mode = LoginAuthPolicy.defaultMode(
        hasPassword: false,
        addressPairingEligible: false,
      );
      expect(mode, LoginAuthMode.password);
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isFalse,
      );
      expect(
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: mode,
          hasPassword: false,
          tailscalePath: false,
        ),
        isTrue,
      );
    });

    test('explicit pair on MagicDNS hostname still attempts pairing', () {
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: LoginAuthMode.pair,
          hasPassword: false,
          tailscalePath: false,
        ),
        isTrue,
      );
      expect(
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: LoginAuthMode.pair,
          hasPassword: false,
          tailscalePath: false,
        ),
        isFalse,
      );
    });

    test('filled password never pairs, including Funnel HELLO.pairing true', () {
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: LoginAuthMode.password,
          hasPassword: true,
          tailscalePath: false,
        ),
        isFalse,
      );
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: LoginAuthMode.pair,
          hasPassword: true,
          tailscalePath: true,
        ),
        isFalse,
      );
    });

    test('embedded Tailscale empty password pairs even in password mode', () {
      expect(
        LoginAuthPolicy.pairIfNeeded(
          mode: LoginAuthMode.password,
          hasPassword: false,
          tailscalePath: true,
        ),
        isTrue,
      );
      expect(
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: LoginAuthMode.password,
          hasPassword: false,
          tailscalePath: true,
        ),
        isFalse,
      );
    });

    test('defaultMode uses saved password then LAN eligibility', () {
      expect(
        LoginAuthPolicy.defaultMode(
          hasPassword: true,
          addressPairingEligible: true,
        ),
        LoginAuthMode.password,
      );
      expect(
        LoginAuthPolicy.defaultMode(
          hasPassword: false,
          addressPairingEligible: true,
        ),
        LoginAuthMode.pair,
      );
      expect(
        LoginAuthPolicy.defaultMode(
          hasPassword: false,
          addressPairingEligible: false,
        ),
        LoginAuthMode.password,
      );
    });
  });
}
