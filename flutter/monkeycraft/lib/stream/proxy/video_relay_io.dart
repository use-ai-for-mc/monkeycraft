import 'dart:io';
import 'dart:typed_data';

import 'package:monkeycraft_client/stream/mpeg_ts_muxer.dart';

class VideoRelay {
  ServerSocket? _serverSocket;
  final List<Socket> _activeClients = [];
  final List<Socket> _pendingClients = [];
  final MpegTsMuxer _ts = MpegTsMuxer();
  int _fps = 10;
  int _frameIndex = 0;
  int _port = 0;

  int get port => _port;
  String get url => 'tcp://127.0.0.1:$_port';

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = _serverSocket!.port;

    _serverSocket!.listen((client) {
      _pendingClients.add(client);

      client.done
          .then((_) {
            _pendingClients.remove(client);
            _activeClients.remove(client);
          })
          .catchError((_) {
            _pendingClients.remove(client);
            _activeClients.remove(client);
            client.destroy();
          });
    });
  }

  void onVideoFrame(List<int> h264Data, bool isIdr) {
    if (isIdr) {
      for (final c in _pendingClients) {
        _ts.writeTables(c.add);
        _activeClients.add(c);
      }
      _pendingClients.clear();
    }

    final pts90k = (_frameIndex * 90000) ~/ (_fps > 0 ? _fps : 20);
    _frameIndex += 1;

    if (_activeClients.isEmpty) return;

    final tsPackets = _ts.muxH264AccessUnit(
      Uint8List.fromList(h264Data),
      pts90k,
    );

    for (final client in _activeClients.toList()) {
      try {
        for (final packet in tsPackets) {
          client.add(packet);
        }
      } catch (_) {
        client.destroy();
        _activeClients.remove(client);
      }
    }
  }

  void updateFps(int fps) {
    if (fps > 0) _fps = fps;
  }

  void reset() {
    _frameIndex = 0;
    _ts.reset();
  }

  Future<void> stop() async {
    for (final client in _activeClients) {
      client.destroy();
    }
    _activeClients.clear();

    for (final client in _pendingClients) {
      client.destroy();
    }
    _pendingClients.clear();

    await _serverSocket?.close();
    _serverSocket = null;
  }
}
