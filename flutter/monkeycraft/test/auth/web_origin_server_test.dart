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

  test('a valid remembered game target takes priority on GitHub Pages', () {
    final pages = Uri.parse('https://use-ai-for-mc.github.io/monkeycraft/');
    expect(isHostedWebPage(pages), isTrue);
    expect(
      webInitialServer(pages, 'wss://mac.tail977122.ts.net:9600'),
      'wss://mac.tail977122.ts.net:9600',
    );
    expect(webInitialServer(pages, ''), '');
  });

  test(
    'a valid remembered target takes priority on a page served by the Mod',
    () {
      final mod = Uri.parse('https://mac.tail977122.ts.net:8443/');
      expect(isHostedWebPage(mod), isFalse);
      expect(
        webInitialServer(mod, 'wss://another.tailnet.ts.net:9600'),
        'wss://another.tailnet.ts.net:9600',
      );
    },
  );

  test('uses the Mod origin only when no valid remembered target exists', () {
    final mod = Uri.parse('https://mac.tail977122.ts.net:8443/');
    expect(webInitialServer(mod, ''), 'https://mac.tail977122.ts.net:8443');
    expect(
      webInitialServer(mod, 'not a URL'),
      'https://mac.tail977122.ts.net:8443',
    );
  });

  test('HTTPS pages reject an insecure websocket target', () {
    final page = Uri.parse('https://use-ai-for-mc.github.io/monkeycraft/');
    expect(webServerError(page, 'mac.tailnet.ts.net:9600'), isNotNull);
    expect(webServerError(page, 'https://mac.tailnet.ts.net:9600'), isNull);
  });

  test('an autofilled password is cleared when its target changes', () {
    final autofill = WebPasswordAutofill('https://HOST.example:9600/');
    expect(autofill.clearForTarget('wss://host.example:9600'), isFalse);
    expect(autofill.isActive, isTrue);
    expect(autofill.clearForTarget('wss://other.example:9600'), isTrue);
    expect(autofill.isActive, isFalse);
  });
}
