import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the login credentials. The server address stays in
/// SharedPreferences; the password lives in the platform keystore via
/// flutter_secure_storage. A password stored in SharedPreferences by an
/// older app version is migrated to secure storage on first load.
///
/// All storage failures degrade to "no saved value" so a broken keystore
/// never blocks the login flow.
class CredentialStore {
  static const _serverKey = 'server';
  static const _passwordKey = 'password';
  static const _defaultServer = '127.0.0.1:9600';
  static const _storage = FlutterSecureStorage();

  static Future<({String server, String password})> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final server = prefs?.getString(_serverKey) ?? _defaultServer;

    String? password;
    try {
      password = await _storage.read(key: _passwordKey);
    } catch (_) {}

    if (password == null) {
      final legacy = prefs?.getString(_passwordKey);
      if (legacy != null && legacy.isNotEmpty) {
        password = legacy;
        try {
          await _storage.write(key: _passwordKey, value: legacy);
          // Only drop the legacy copy once it is safely in secure storage.
          await prefs?.remove(_passwordKey);
        } catch (_) {}
      }
    }

    return (server: server, password: password ?? '');
  }

  static Future<void> save(String server, String password) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverKey, server);
    } catch (_) {}
    try {
      await _storage.write(key: _passwordKey, value: password);
      if (kIsWeb) {
        await prefs?.setString(_passwordKey, password);
      } else {
        await prefs?.remove(_passwordKey);
      }
    } catch (_) {
      try {
        await prefs?.setString(_passwordKey, password);
      } catch (_) {}
    }
  }
}
