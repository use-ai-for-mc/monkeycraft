import 'package:monkeycraft_client/stream/transport/connection_transport.dart';

abstract class TailscaleClient {
  bool get isSupported;
  Stream<TailscaleEmbeddedSnapshot> get events;
  TransportFactory? get gameTransportFactory;
  Future<TailscaleDiagnostics> diagnostics();
  Future<TailscaleEmbeddedSnapshot> status();
  Future<List<TailscalePeer>> listPeers();
  Future<void> start();
  Future<void> loginInteractive();
  Future<void> cancel();
  Future<void> logout();
  Future<void> stop();
  Future<TailscaleBridgeLease> openBridge({
    required String nodeId,
    int port = 9600,
  });
  Future<void> closeBridge(String leaseId);
}

class TailscalePeer {
  const TailscalePeer({
    required this.nodeId,
    required this.hostName,
    required this.online,
    this.dnsName,
  });

  final String nodeId;
  final String hostName;
  final bool online;
  final String? dnsName;

  factory TailscalePeer.fromMap(Map<dynamic, dynamic> map) {
    String? str(Object? value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return TailscalePeer(
      nodeId: str(map['nodeId']) ?? '',
      hostName: str(map['hostName']) ?? '',
      online: map['online'] == true,
      dnsName: str(map['dnsName']),
    );
  }

  String get displayName {
    if (hostName.isNotEmpty) return hostName;
    final dns = dnsName;
    if (dns != null && dns.isNotEmpty) {
      return dns.endsWith('.') ? dns.substring(0, dns.length - 1) : dns;
    }
    return nodeId;
  }
}

class TailscaleEmbeddedSnapshot {
  const TailscaleEmbeddedSnapshot({
    required this.phase,
    this.errorCode,
    this.errorMessage,
    this.authUrlHost,
    this.nodeId,
    this.hostName,
    this.backendState,
    this.peers = const [],
  });

  final String phase;
  final String? errorCode;
  final String? errorMessage;
  final String? authUrlHost;
  final String? nodeId;
  final String? hostName;
  final String? backendState;
  final List<TailscalePeer> peers;

  factory TailscaleEmbeddedSnapshot.fromMap(Map<dynamic, dynamic> map) {
    String? str(Object? value) {
      if (value == null) return null;
      final text = value.toString();
      return text.isEmpty ? null : text;
    }

    final rawPeers = map['peers'];
    return TailscaleEmbeddedSnapshot(
      phase: str(map['phase']) ?? 'unavailable',
      errorCode: str(map['errorCode']),
      errorMessage: str(map['errorMessage']),
      authUrlHost: str(map['authUrlHost']),
      nodeId: str(map['nodeId']),
      hostName: str(map['hostName']),
      backendState: str(map['backendState']),
      peers: rawPeers is List
          ? rawPeers
                .whereType<Map>()
                .map(TailscalePeer.fromMap)
                .where((p) => p.nodeId.isNotEmpty)
                .toList()
          : const [],
    );
  }

  bool get isRunning => phase == 'running';
  bool get needsLogin => phase == 'needsLogin';
  bool get needsApproval => phase == 'needsApproval';
}

class TailscaleBridgeLease {
  const TailscaleBridgeLease({required this.url, required this.leaseId});

  final String url;
  final String leaseId;

  factory TailscaleBridgeLease.fromMap(Map<dynamic, dynamic> map) {
    return TailscaleBridgeLease(
      url: map['url']?.toString() ?? '',
      leaseId: map['leaseId']?.toString() ?? '',
    );
  }
}

class TailscaleDiagnostics {
  const TailscaleDiagnostics({
    required this.available,
    required this.libtailscaleLinked,
    required this.statusJsonAvailable,
    required this.reason,
    this.symbols = const [],
    this.libtailscaleCommit,
    this.tailscaleGoModule,
    this.deploymentTarget,
    this.kitIosMinimum,
  });

  final bool available;
  final bool libtailscaleLinked;
  final bool statusJsonAvailable;
  final String reason;
  final List<String> symbols;
  final String? libtailscaleCommit;
  final String? tailscaleGoModule;
  final String? deploymentTarget;
  final String? kitIosMinimum;

  factory TailscaleDiagnostics.fromMap(Map<dynamic, dynamic> map) {
    String? str(Object? value) {
      if (value == null) return null;
      final text = value.toString();
      return text.isEmpty ? null : text;
    }

    final rawSymbols = map['symbols'];
    return TailscaleDiagnostics(
      available: map['available'] == true,
      libtailscaleLinked: map['libtailscaleLinked'] == true,
      statusJsonAvailable: map['statusJsonAvailable'] == true,
      reason: str(map['reason']) ?? 'unknown',
      symbols: rawSymbols is List
          ? rawSymbols.map((e) => e.toString()).toList()
          : const [],
      libtailscaleCommit: str(map['libtailscaleCommit']),
      tailscaleGoModule: str(map['tailscaleGoModule']),
      deploymentTarget: str(map['deploymentTarget']),
      kitIosMinimum: str(map['kitIosMinimum']),
    );
  }
}
