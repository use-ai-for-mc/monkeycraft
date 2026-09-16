import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CredentialEntry {
  const CredentialEntry({
    required this.password,
    this.lastServer = '',
    this.lastSeen = 0,
  });

  final String password;
  final String lastServer;
  final int lastSeen;

  Map<String, dynamic> toJson() => {
    'password': password,
    'lastServer': lastServer,
    'lastSeen': lastSeen,
  };

  static CredentialEntry fromJson(Map<String, dynamic> json) {
    return CredentialEntry(
      password: json['password']?.toString() ?? '',
      lastServer: json['lastServer']?.toString() ?? '',
      lastSeen: json['lastSeen'] is num ? (json['lastSeen'] as num).toInt() : 0,
    );
  }
}

class CredentialSnapshot {
  const CredentialSnapshot(this._passwords);

  final Map<String, String> _passwords;

  String? lookup(String? keyId) {
    if (keyId != null && keyId.isNotEmpty) {
      return _passwords[keyId];
    }
    return _passwords[CredentialStore.legacyKeyId];
  }
}

class CredentialStore {
  static const _serverKey = 'server';
  static const _passwordKey = 'password';
  static const _vaultKey = 'credentialVault';
  static const _tailscaleNodeIdKey = 'tailscaleNodeId';
  static const _rememberCredentialsKey = 'rememberCredentials';
  static const _defaultServer = '127.0.0.1:9600';
  static const legacyKeyId = 'legacy';
  static const _maxEntries = 8;
  static const _storage = FlutterSecureStorage();

  static Future<
    ({
      String server,
      String password,
      String? tailscaleNodeId,
      bool rememberCredentials,
    })
  >
  load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final server = prefs?.getString(_serverKey) ?? _defaultServer;
    final vault = await _readVault(prefs);
    return (
      server: server,
      password: _displayPassword(vault),
      tailscaleNodeId: prefs?.getString(_tailscaleNodeIdKey),
      rememberCredentials: prefs?.getBool(_rememberCredentialsKey) ?? true,
    );
  }

  static Future<CredentialSnapshot> snapshot() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final vault = await _readVault(prefs);
    return CredentialSnapshot({
      for (final entry in vault.entries)
        if (entry.value.password.isNotEmpty) entry.key: entry.value.password,
    });
  }

  static Future<String?> passwordFor(String? keyId) async {
    return (await snapshot()).lookup(keyId);
  }

  static Future<void> put({
    required String keyId,
    required String password,
    String lastServer = '',
  }) async {
    if (keyId.isEmpty || password.isEmpty) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final vault = await _readVault(prefs);
    vault[keyId] = CredentialEntry(
      password: password,
      lastServer: lastServer,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );
    _evict(vault);
    await _writeVault(prefs, vault);
    await _writePasswordKey(prefs, password);
  }

  static Future<void> remove(String keyId) async {
    if (keyId.isEmpty) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final vault = await _readVault(prefs);
    vault.remove(keyId);
    await _writeVault(prefs, vault);
    final display = _displayPassword(vault);
    if (display.isEmpty) {
      await _deletePasswordKey(prefs);
    } else {
      await _writePasswordKey(prefs, display);
    }
  }

  static Future<void> save(String server, String password) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverKey, server);
    } catch (_) {}
    if (password.isEmpty) return;
    await put(keyId: legacyKeyId, password: password, lastServer: server);
  }

  static Future<void> saveRememberCredentials(bool remember) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberCredentialsKey, remember);
    } catch (_) {}
  }

  static Future<void> clearPassword() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.remove(_passwordKey);
      await prefs.remove(_vaultKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _passwordKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _vaultKey);
    } catch (_) {}
  }

  static Future<void> saveTailscaleNodeId(String? nodeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (nodeId == null || nodeId.isEmpty) {
        await prefs.remove(_tailscaleNodeIdKey);
      } else {
        await prefs.setString(_tailscaleNodeIdKey, nodeId);
      }
    } catch (_) {}
  }

  static String _displayPassword(Map<String, CredentialEntry> vault) {
    CredentialEntry? best;
    for (final entry in vault.values) {
      if (entry.password.isEmpty) continue;
      if (best == null || entry.lastSeen > best.lastSeen) {
        best = entry;
      }
    }
    return best?.password ?? '';
  }

  static Future<Map<String, CredentialEntry>> _readVault(
    SharedPreferences? prefs,
  ) async {
    String? raw;
    try {
      raw = await _storage.read(key: _vaultKey);
    } catch (_) {}
    raw ??= prefs?.getString(_vaultKey);
    final vault = <String, CredentialEntry>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is Map) {
              final parsed = CredentialEntry.fromJson(
                value.map((key, val) => MapEntry(key.toString(), val)),
              );
              if (parsed.password.isNotEmpty) {
                vault[entry.key.toString()] = parsed;
              }
            }
          }
        }
      } catch (_) {}
    }
    if (vault.isNotEmpty) return vault;

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
          await prefs?.remove(_passwordKey);
        } catch (_) {}
      }
    }
    if (password != null && password.isNotEmpty) {
      vault[legacyKeyId] = CredentialEntry(password: password);
      await _writeVault(prefs, vault);
    }
    return vault;
  }

  static Future<void> _writeVault(
    SharedPreferences? prefs,
    Map<String, CredentialEntry> vault,
  ) async {
    final raw = jsonEncode({
      for (final entry in vault.entries) entry.key: entry.value.toJson(),
    });
    try {
      await _storage.write(key: _vaultKey, value: raw);
      if (kIsWeb) {
        await prefs?.setString(_vaultKey, raw);
      } else {
        await prefs?.remove(_vaultKey);
      }
    } catch (_) {
      try {
        await prefs?.setString(_vaultKey, raw);
      } catch (_) {}
    }
  }

  static Future<void> _writePasswordKey(
    SharedPreferences? prefs,
    String password,
  ) async {
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

  static Future<void> _deletePasswordKey(SharedPreferences? prefs) async {
    try {
      await prefs?.remove(_passwordKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _passwordKey);
    } catch (_) {}
  }

  static void _evict(Map<String, CredentialEntry> vault) {
    while (vault.length > _maxEntries) {
      String? oldestKey;
      var oldestSeen = 1 << 62;
      for (final entry in vault.entries) {
        if (entry.value.lastSeen < oldestSeen) {
          oldestSeen = entry.value.lastSeen;
          oldestKey = entry.key;
        }
      }
      if (oldestKey == null) break;
      vault.remove(oldestKey);
    }
  }
}
