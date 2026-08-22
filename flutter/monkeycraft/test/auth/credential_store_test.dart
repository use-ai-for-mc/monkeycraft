import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialStore', () {
    test('load returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final credentials = await CredentialStore.load();

      expect(credentials.server, '127.0.0.1:9600');
      expect(credentials.password, '');
      expect(credentials.certificateSha256, isNull);
    });

    test('load migrates a legacy SharedPreferences password', () async {
      SharedPreferences.setMockInitialValues({
        'server': 'example.com:9600',
        'password': 'legacy-secret',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final credentials = await CredentialStore.load();

      expect(credentials.server, 'example.com:9600');
      expect(credentials.password, 'legacy-secret');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('password'),
        isNull,
        reason: 'legacy copy is removed after migration',
      );
      expect(
        await const FlutterSecureStorage().read(key: 'password'),
        'legacy-secret',
      );
    });

    test(
      'load prefers the secure-storage password over a stale copy',
      () async {
        SharedPreferences.setMockInitialValues({'password': 'stale'});
        FlutterSecureStorage.setMockInitialValues({'password': 'current'});

        final credentials = await CredentialStore.load();

        expect(credentials.password, 'current');
      },
    );

    test('load returns a stored certificate pin', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'password': 'secret',
        'certificate_sha256': 'stored-pin',
      });

      final credentials = await CredentialStore.load();

      expect(credentials.certificateSha256, 'stored-pin');
    });

    test('save writes the password only to secure storage', () async {
      SharedPreferences.setMockInitialValues({'password': 'legacy-secret'});
      FlutterSecureStorage.setMockInitialValues({});

      await CredentialStore.save(
        'host:9600',
        'new-secret',
        certificateSha256: 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server'), 'host:9600');
      expect(prefs.getString('password'), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'password'),
        'new-secret',
      );
      expect(
        await const FlutterSecureStorage().read(key: 'certificate_sha256'),
        'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
      );
    });

    test('save removes a stale certificate pin', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'certificate_sha256': 'stale-pin',
      });

      await CredentialStore.save('host:9600', 'secret');

      expect(
        await const FlutterSecureStorage().read(key: 'certificate_sha256'),
        isNull,
      );
    });
  });
}
