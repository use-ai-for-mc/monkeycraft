import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialStore', () {
    test(
      'web vault snapshots are isolated by normalized target and key id',
      () {
        final vault = <String, CredentialEntry>{
          CredentialStore.webCredentialSlot(
            'https://ALPHA.example:9600/',
            'key-a',
          ): const CredentialEntry(
            password: 'alpha',
          ),
          CredentialStore.webCredentialSlot('wss://beta.example:9600', 'key-a'):
              const CredentialEntry(password: 'beta'),
          CredentialStore.webCredentialSlot(
            'wss://alpha.example:9600',
            'legacy',
          ): const CredentialEntry(
            password: 'alpha-legacy',
          ),
        };

        final alpha = CredentialStore.webSnapshot(
          vault,
          ' wss://alpha.example:9600 ',
        );
        final beta = CredentialStore.webSnapshot(
          vault,
          'wss://beta.example:9600',
        );

        expect(alpha.lookup('key-a'), 'alpha');
        expect(alpha.lookup(null), 'alpha-legacy');
        expect(beta.lookup('key-a'), 'beta');
        expect(beta.lookup(null), isNull);
      },
    );

    test('load returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final credentials = await CredentialStore.load();

      expect(credentials.server, '127.0.0.1:9600');
      expect(credentials.password, '');
      expect(credentials.tailscaleNodeId, isNull);
      expect(credentials.rememberCredentials, isTrue);
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

    test('saveTailscaleNodeId persists a stable node id only', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.saveTailscaleNodeId('n123');
      final loaded = await CredentialStore.load();
      expect(loaded.tailscaleNodeId, 'n123');
      await CredentialStore.saveTailscaleNodeId(null);
      final cleared = await CredentialStore.load();
      expect(cleared.tailscaleNodeId, isNull);
    });

    test('rememberCredentials defaults on and can be cleared', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.save('host:9600', 'secret');
      expect((await CredentialStore.load()).password, 'secret');
      await CredentialStore.saveRememberCredentials(false);
      await CredentialStore.clearPassword();
      final loaded = await CredentialStore.load();
      expect(loaded.rememberCredentials, isFalse);
      expect(loaded.password, '');
      expect(loaded.server, 'host:9600');
    });

    test('put stores by keyId and unknown ids do not fall back', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.put(
        keyId: 'alpha',
        password: 'one',
        lastServer: 'a:9600',
      );
      await CredentialStore.put(
        keyId: 'beta',
        password: 'two',
        lastServer: 'b:9600',
      );

      expect(await CredentialStore.passwordFor('alpha'), 'one');
      expect(await CredentialStore.passwordFor('beta'), 'two');
      expect(await CredentialStore.passwordFor('missing'), isNull);
      expect(await CredentialStore.passwordFor(null), isNull);
    });

    test('legacy password is only used when HELLO has no keyId', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.save('host:9600', 'legacy-secret');

      expect(
        await CredentialStore.passwordFor(CredentialStore.legacyKeyId),
        'legacy-secret',
      );
      expect(await CredentialStore.passwordFor(null), 'legacy-secret');
      expect(await CredentialStore.passwordFor('other'), isNull);
    });

    test('remove deletes only that keyId', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.put(keyId: 'keep', password: 'keep-secret');
      await CredentialStore.put(keyId: 'drop', password: 'drop-secret');
      await CredentialStore.remove('drop');

      expect(await CredentialStore.passwordFor('keep'), 'keep-secret');
      expect(await CredentialStore.passwordFor('drop'), isNull);
      expect((await CredentialStore.load()).password, 'keep-secret');
    });

    test('clearPassword wipes the whole vault', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await CredentialStore.put(keyId: 'a', password: 'secret-a');
      await CredentialStore.clearPassword();

      expect(await CredentialStore.passwordFor('a'), isNull);
      expect((await CredentialStore.load()).password, '');
    });
  });
}
