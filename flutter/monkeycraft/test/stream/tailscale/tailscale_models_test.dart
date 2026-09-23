import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';

void main() {
  test('snapshot decoder maps login and running', () {
    final login = TailscaleEmbeddedSnapshot.fromMap({
      'phase': 'needsLogin',
      'authUrlHost': 'login.tailscale.com',
    });
    expect(login.needsLogin, isTrue);
    expect(login.authUrlHost, 'login.tailscale.com');

    final running = TailscaleEmbeddedSnapshot.fromMap({
      'phase': 'running',
      'nodeId': 'n123',
      'hostName': 'mac',
      'peers': [
        {
          'nodeId': 'pc1',
          'hostName': 'desk',
          'online': true,
          'dnsName': 'desk.ts.net.',
          'tailscaleIPs': ['fd7a:115c:a1e0::2', '100.64.1.2'],
        },
      ],
    });
    expect(running.isRunning, isTrue);
    expect(running.nodeId, 'n123');
    expect(running.peers.single.displayName, 'desk');
    expect(running.peers.single.online, isTrue);
    expect(
      running.peers.single.addressSummary,
      '100.64.1.2 · fd7a:115c:a1e0::2',
    );
  });

  test('diagnostics decoder', () {
    final d = TailscaleDiagnostics.fromMap({
      'available': true,
      'libtailscaleLinked': true,
      'statusJsonAvailable': true,
      'reason': 'libtailscale linked',
      'symbols': ['tailscale_new', 'tailscale_status_json'],
      'libtailscaleCommit': '80771313ac4127973677c993889fe215abcf1fbd',
      'deploymentTarget': '16.6',
      'kitIosMinimum': '18.1',
    });
    expect(d.available, isTrue);
    expect(d.symbols, contains('tailscale_status_json'));
    expect(d.deploymentTarget, '16.6');
    expect(d.kitIosMinimum, '18.1');
  });

  test('bridge lease decoder', () {
    final lease = TailscaleBridgeLease.fromMap({
      'url': 'ws://127.0.0.1:41234',
      'leaseId': 'abc',
    });
    expect(lease.url, 'ws://127.0.0.1:41234');
    expect(lease.leaseId, 'abc');
  });
}
