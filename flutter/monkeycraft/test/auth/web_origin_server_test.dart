import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/auth/web_origin_server.dart';

void main() {
  test('uses page origin including port', () {
    expect(
      webOriginServer(Uri.parse('http://127.0.0.1:9600/')),
      'http://127.0.0.1:9600',
    );
    expect(
      webOriginServer(Uri.parse('https://mac.tail977122.ts.net:10800/play')),
      'https://mac.tail977122.ts.net:10800',
    );
  });

  test('empty host is not a server', () {
    expect(webOriginServer(Uri.parse('file:///tmp/index.html')), '');
  });
}
