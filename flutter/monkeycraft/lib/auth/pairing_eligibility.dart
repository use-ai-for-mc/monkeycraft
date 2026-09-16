import 'package:monkeycraft_client/stream/transport/server_url.dart';

bool isPairingEligibleServer(String server) {
  try {
    return isPairingEligibleHost(parseMonkeycraftServerUrl(server).host);
  } catch (_) {
    return false;
  }
}

bool isPairingEligibleHost(String host) {
  var name = host.trim().toLowerCase();
  if (name.startsWith('[') && name.endsWith(']')) {
    name = name.substring(1, name.length - 1);
  }
  if (name.endsWith('.')) {
    name = name.substring(0, name.length - 1);
  }
  if (name.isEmpty) return false;
  if (name == 'localhost' || name == '::1' || name == '0:0:0:0:0:0:0:1') {
    return true;
  }

  final v4 = _parseIpv4(name);
  if (v4 != null) {
    return _inCidr(v4, 0x7F000000, 8) ||
        _inCidr(v4, 0x0A000000, 8) ||
        _inCidr(v4, 0xAC100000, 12) ||
        _inCidr(v4, 0xC0A80000, 16) ||
        _inCidr(v4, 0xA9FE0000, 16) ||
        _inCidr(v4, 0x64400000, 10);
  }

  if (name.contains(':')) {
    if (name == '::1') return true;
    if (name.startsWith('fe80:')) return true;
    if (name.startsWith('fc') || name.startsWith('fd')) return true;
  }
  return false;
}

int? _parseIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    value = (value << 8) | octet;
  }
  return value;
}

bool _inCidr(int address, int network, int prefix) {
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return (address & mask) == (network & mask);
}
