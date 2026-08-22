import 'dart:convert';

class PairingPayload {
  static const version = 2;

  final String password;
  final String? certificateSha256;

  const PairingPayload({
    required this.password,
    required this.certificateSha256,
  });

  factory PairingPayload.parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) throw const FormatException('Pairing code is empty');
    if (!value.startsWith('{')) {
      return PairingPayload(password: value, certificateSha256: null);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return PairingPayload(password: value, certificateSha256: null);
    }
    if (decoded is! Map<String, dynamic> || !decoded.containsKey('v')) {
      return PairingPayload(password: value, certificateSha256: null);
    }
    if (decoded['v'] != version) {
      throw const FormatException('Unsupported pairing code');
    }
    final password = decoded['pw']?.toString() ?? '';
    final fingerprint = normalizeCertificateSha256(decoded['fp']?.toString());
    if (password.isEmpty || fingerprint == null) {
      throw const FormatException('Invalid pairing code');
    }
    return PairingPayload(password: password, certificateSha256: fingerprint);
  }
}

String? normalizeCertificateSha256(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalized)) return null;
  return normalized;
}
