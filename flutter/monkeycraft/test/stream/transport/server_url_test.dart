import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/transport/server_url.dart';

void main() {
  group('parseMonkeycraftServerUrl', () {
    test('https becomes wss', () {
      expect(
        parseMonkeycraftServerUrl('https://example.com:9600'),
        Uri.parse('wss://example.com:9600'),
      );
    });

    test('http becomes ws', () {
      expect(
        parseMonkeycraftServerUrl('http://192.168.1.10:9600'),
        Uri.parse('ws://192.168.1.10:9600'),
      );
    });

    test('keeps ws and wss', () {
      expect(
        parseMonkeycraftServerUrl('ws://host:1'),
        Uri.parse('ws://host:1'),
      );
      expect(
        parseMonkeycraftServerUrl('wss://host'),
        Uri.parse('wss://host'),
      );
    });

    test('host:port becomes ws', () {
      expect(
        parseMonkeycraftServerUrl('100.64.1.2:9600'),
        Uri.parse('ws://100.64.1.2:9600'),
      );
    });

    test('bare host becomes wss', () {
      expect(
        parseMonkeycraftServerUrl('pc.tailnet.ts.net'),
        Uri.parse('wss://pc.tailnet.ts.net'),
      );
    });
  });
}
