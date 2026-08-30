import 'package:flutter/foundation.dart';
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
      expect(prefs.getString('password'), isNull,
          reason: 'legacy copy is removed after migration');
      expect(
        await const FlutterSecureStorage().read(key: 'password'),
        'legacy-secret',
      );
    });

    test('load prefers the secure-storage password over a stale copy',
        () async {
      SharedPreferences.setMockInitialValues({'password': 'stale'});
      FlutterSecureStorage.setMockInitialValues({'password': 'current'});

      final credentials = await CredentialStore.load();

      expect(credentials.password, 'current');
    });

    test('save writes the password only to secure storage', () async {
      SharedPreferences.setMockInitialValues({'password': 'legacy-secret'});
      FlutterSecureStorage.setMockInitialValues({});

      await CredentialStore.save('host:9600', 'new-secret');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server'), 'host:9600');
      if (kIsWeb) {
        expect(prefs.getString('password'), 'new-secret');
      } else {
        expect(prefs.getString('password'), isNull);
      }
      expect(
        await const FlutterSecureStorage().read(key: 'password'),
        'new-secret',
      );
    });
  });
}
