import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:monkeycraft_client/services/hibernation_models.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/chat_models.dart';

class StreamProxy {
  ServerSocket? _serverSocket;
  WebSocketChannel? _wsChannel;
  bool _authenticated = false;
  final List<Socket> _activeClients = [];
  final List<Socket> _pendingClients = [];
  final _MpegTsMuxer _ts = _MpegTsMuxer();
  StreamController<Uint8List>? _accessUnitsController;
  StreamController<PlayerPose>? _playerPoseController;
  StreamController<TimedNotification>? _timedNotificationController;
  StreamController<NudgeNotification>? _nudgeNotificationController;
  StreamController<HibernationEvent>? _hibernationController;
  StreamController<CommandDeniedEvent>? _commandDeniedController;
  StreamController<ServerDisconnectEvent>? _serverDisconnectController;
  StreamController<ChatMessage>? _chatMessageController;
  StreamController<ChatDeniedEvent>? _chatDeniedController;
  StreamController<ChatModeEvent>? _chatModeController;
  Completer<List<ChatMessage>>? _chatSubscribeCompleter;
  final List<ChatMessageListener> _outgoingChatListeners = [];
  int _fps = 20;
  int _frameIndex = 0;
  int _port = 0;
  DateTime? _lastHibernationStatusTime;
  DateTime? _lastTimedStatusTime;
  Timer? _pingTimer;

  // Get the local proxy URL
  String get url => 'tcp://127.0.0.1:$_port';
  Stream<Uint8List> get accessUnits =>
      _accessUnitsController?.stream ?? const Stream.empty();
  Stream<PlayerPose> get playerPose =>
      _playerPoseController?.stream ?? const Stream.empty();
  Stream<TimedNotification> get timedNotifications =>
      _timedNotificationController?.stream ?? const Stream.empty();
  Stream<NudgeNotification> get nudges =>
      _nudgeNotificationController?.stream ?? const Stream.empty();
  Stream<HibernationEvent> get hibernationEvents =>
      _hibernationController?.stream ?? const Stream.empty();
  Stream<CommandDeniedEvent> get commandDeniedEvents =>
      _commandDeniedController?.stream ?? const Stream.empty();
  Stream<ServerDisconnectEvent> get serverDisconnectEvents =>
      _serverDisconnectController?.stream ?? const Stream.empty();
  Stream<ChatMessage> get chatMessages =>
      _chatMessageController?.stream ?? const Stream.empty();
  Stream<ChatDeniedEvent> get chatDeniedEvents =>
      _chatDeniedController?.stream ?? const Stream.empty();
  Stream<ChatModeEvent> get chatModeEvents =>
      _chatModeController?.stream ?? const Stream.empty();

  bool _isIdrFrame(List<int> data) {
    if (data.length < 5) return false;
    for (int i = 0; i < data.length - 4; i++) {
      if (data[i] == 0 &&
          data[i + 1] == 0 &&
          data[i + 2] == 0 &&
          data[i + 3] == 1) {
        final type = data[i + 4] & 0x1F;
        if (type == 5) return true;
        i += 4;
      }
    }
    return false;
  }

  String _generateSalt() {
    final random = List.generate(
      16,
      (_) => DateTime.now().microsecondsSinceEpoch ^ (Object().hashCode),
    );
    return base64Encode(random.map((e) => e & 0xFF).toList());
  }

  String _computeHmac(String key, String data) {
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(data));
    return base64Encode(digest.bytes);
  }

  Future<void> start(
    String host,
    int port,
    String password, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration authTimeout = const Duration(seconds: 5),
  }) async {
    await stop();
    _frameIndex = 0;
    _authenticated = false;
    _accessUnitsController = StreamController<Uint8List>.broadcast();
    _playerPoseController = StreamController<PlayerPose>.broadcast();
    _timedNotificationController =
        StreamController<TimedNotification>.broadcast();
    _nudgeNotificationController =
        StreamController<NudgeNotification>.broadcast();
    _hibernationController = StreamController<HibernationEvent>.broadcast();
    _commandDeniedController = StreamController<CommandDeniedEvent>.broadcast();
    _serverDisconnectController =
        StreamController<ServerDisconnectEvent>.broadcast();
    _chatMessageController = StreamController<ChatMessage>.broadcast();
    _chatDeniedController = StreamController<ChatDeniedEvent>.broadcast();
    _chatModeController = StreamController<ChatModeEvent>.broadcast();

    // 1. Start Local TCP Server
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

    // 2. Connect to WebSocket
    final wsUrl = Uri.parse('ws://$host:$port');

    try {
      _wsChannel = WebSocketChannel.connect(wsUrl);
      await _wsChannel!.ready.timeout(connectTimeout);

      final authCompleter = Completer<void>();
      void completeAuthError(Object error, [StackTrace? st]) {
        if (authCompleter.isCompleted) return;
        authCompleter.completeError(error, st);
      }

      // 3. Listen for messages (including AUTH_RESPONSE)
      String? serverSalt;
      _wsChannel!.stream.listen(
        (message) {
          if (message is List<int>) {
            if (!_authenticated) return;
            // Binary Video Data
            _accessUnitsController?.add(Uint8List.fromList(message));
            // ACK immediately
            _wsChannel!.sink.add(jsonEncode({'type': 'ACK'}));

            if (_isIdrFrame(message)) {
              for (final c in _pendingClients) {
                _ts.writeTables(c);
                _activeClients.add(c);
              }
              _pendingClients.clear();
            }

            final pts90k = (_frameIndex * 90000) ~/ (_fps > 0 ? _fps : 20);
            _frameIndex += 1;

            if (_activeClients.isEmpty) {
              return;
            }

            final tsPackets = _ts.muxH264AccessUnit(
              Uint8List.fromList(message),
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
          } else {
            // Text Message
            try {
              final data = jsonDecode(message);
              if (data['type'] == 'HELLO') {
                serverSalt = data['salt']?.toString();
                if (serverSalt != null) {
                  final clientSalt = _generateSalt();
                  final signature = _computeHmac(
                    password,
                    '$serverSalt$clientSalt',
                  );
                  final authMsg = jsonEncode({
                    'type': 'AUTH',
                    'salt': clientSalt,
                    'signature': signature,
                  });
                  _wsChannel!.sink.add(authMsg);
                } else {
                  completeAuthError(Exception('Server did not provide salt'));
                }
              } else if (data['type'] == 'AUTH_OK') {
                _authenticated = true;
                _startPingTimer();
                if (!authCompleter.isCompleted) {
                  authCompleter.complete();
                }
              } else if (data['type'] == 'AUTH_RESPONSE') {
                final success = data['success'] == true;
                if (success) {
                  _authenticated = true;
                  _startPingTimer();
                  if (!authCompleter.isCompleted) {
                    authCompleter.complete();
                  }
                } else {
                  final msg = data['message']?.toString().trim();
                  completeAuthError(
                    Exception(
                      msg == null || msg.isEmpty
                          ? 'Authentication failed'
                          : 'Authentication failed: $msg',
                    ),
                  );
                  _wsChannel?.sink.close(status.normalClosure);
                }
              } else if (!_authenticated) {
                return;
              } else if (data['type'] == 'PLAYER_POSE') {
                final yaw = data['yaw'];
                final pitch = data['pitch'];
                if (yaw is num && pitch is num) {
                  _playerPoseController?.add(
                    PlayerPose(yaw: yaw.toDouble(), pitch: pitch.toDouble()),
                  );
                }
              } else if (data['type'] == 'COMMAND_DENIED') {
                final command = data['command']?.toString() ?? '';
                _commandDeniedController?.add(
                  CommandDeniedEvent(command: command),
                );
              } else if (data['type'] == 'DISCONNECT') {
                final reason = data['reason']?.toString() ?? '';
                _serverDisconnectController?.add(
                  ServerDisconnectEvent(reason: reason),
                );
              } else if (data['type'] == 'CHAT_MESSAGE') {
                _chatMessageController?.add(ChatMessage.fromJson(data));
              } else if (data['type'] == 'CACHED_CHAT_MESSAGES') {
                final messagesList = data['messages'] as List<dynamic>?;
                final cachedMessages = messagesList
                        ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                        .toList() ??
                    <ChatMessage>[];
                if (_chatSubscribeCompleter != null &&
                    !_chatSubscribeCompleter!.isCompleted) {
                  _chatSubscribeCompleter!.complete(cachedMessages);
                }
              } else if (data['type'] == 'CHAT_DENIED') {
                _chatDeniedController?.add(ChatDeniedEvent.fromJson(data));
              } else if (data['type'] == 'CHAT_MODE_STARTED' ||
                  data['type'] == 'CHAT_MODE_ENDED') {
                _chatModeController?.add(ChatModeEvent.fromJson(data));
              } else {
                final timed = timedFromJson(data);
                if (timed != null) {
                  if (data['type'] == 'TIMED_STATUS') {
                    _lastTimedStatusTime = DateTime.now();
                  }
                  _timedNotificationController?.add(timed);
                }
                final nudge = nudgeFromJson(data);
                if (nudge != null) {
                  _nudgeNotificationController?.add(nudge);
                }
                final status = hibernationStatusFromJson(data);
                if (status != null) {
                  _lastHibernationStatusTime = DateTime.now();
                  _hibernationController?.add(status);
                }
              }
            } catch (_) {}
          }
        },
        onError: (e, st) {
          _stopPingTimer();
          _wsChannel = null;
          _authenticated = false;
          if (_timedNotificationController != null &&
              !_timedNotificationController!.isClosed) {
            _timedNotificationController!.add(
              TimedNotification(
                fireAtEpochMs: null,
                title: null,
                body: null,
                sound: false,
              ),
            );
          }
          completeAuthError(e, st);
        },
        onDone: () {
          _stopPingTimer();
          _wsChannel = null;
          _authenticated = false;
          if (_timedNotificationController != null &&
              !_timedNotificationController!.isClosed) {
            _timedNotificationController!.add(
              TimedNotification(
                fireAtEpochMs: null,
                title: null,
                body: null,
                sound: false,
              ),
            );
          }
          completeAuthError(StateError('WebSocket closed'));
        },
      );

      await authCompleter.future.timeout(authTimeout);
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  bool trySendCommand(Map<String, dynamic> command) {
    final ws = _wsChannel;
    if (ws == null) return false;
    if (!_authenticated) return false;
    try {
      ws.sink.add(jsonEncode(command));
    } catch (_) {
      _wsChannel = null;
      _authenticated = false;
      return false;
    }
    if (command['type'] == 'START_STREAM') {
      final fps = command['fps'];
      if (fps is int && fps > 0) {
        _fps = fps;
      }
      _frameIndex = 0;
      _ts.reset();
    } else if (command['type'] == 'STOP_STREAM') {
      _frameIndex = 0;
      _ts.reset();
      _pendingClients.addAll(_activeClients);
      _activeClients.clear();
    }
    return true;
  }

  void sendCommand(Map<String, dynamic> command) {
    trySendCommand(command);
  }

  bool trySendRunCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.startsWith('/')) return false;
    return trySendCommand({'type': 'RUN_COMMAND', 'command': trimmed});
  }

  void sendRunCommand(String command) {
    trySendRunCommand(command);
  }

  void requestKeyframe() {
    trySendCommand({'type': 'REQUEST_KEYFRAME'});
  }

  void sendPing() {
    trySendCommand({'type': 'PING'});
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _lastHibernationStatusTime = DateTime.now();
    _lastTimedStatusTime = DateTime.now();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_authenticated) return;
      final now = DateTime.now();
      final hibernationAge = now.difference(_lastHibernationStatusTime ?? now);
      final timedAge = now.difference(_lastTimedStatusTime ?? now);
      if (hibernationAge.inSeconds >= 10 || timedAge.inSeconds >= 10) {
        sendPing();
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  bool trySendChatMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('/')) return false;

    for (final listener in _outgoingChatListeners) {
      final result = listener(
        ChatMessage(
          sender: 'Me',
          message: trimmed,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isOutgoing: true,
        ),
      );
      if (result == ChatMessageResult.deny) {
        return false;
      }
    }

    return trySendCommand({'type': 'SEND_CHAT', 'message': trimmed});
  }

  void sendChatMessage(String message) {
    trySendChatMessage(message);
  }

  void enterChatMode() {
    trySendCommand({'type': 'ENTER_CHAT'});
  }

  void exitChatMode() {
    trySendCommand({'type': 'EXIT_CHAT'});
  }

  Future<List<ChatMessage>> subscribeToChat({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_authenticated || _wsChannel == null) {
      return <ChatMessage>[];
    }
    _chatSubscribeCompleter = Completer<List<ChatMessage>>();
    trySendCommand({'type': 'SUBSCRIBE_CHAT'});
    return _chatSubscribeCompleter!.future.timeout(timeout, onTimeout: () {
      _chatSubscribeCompleter = null;
      return <ChatMessage>[];
    });
  }

  void unsubscribeFromChat() {
    _chatSubscribeCompleter = null;
    trySendCommand({'type': 'UNSUBSCRIBE_CHAT'});
  }

  void addOutgoingChatListener(ChatMessageListener listener) {
    _outgoingChatListeners.add(listener);
  }

  void removeOutgoingChatListener(ChatMessageListener listener) {
    _outgoingChatListeners.remove(listener);
  }

  Future<void> stop() async {
    _stopPingTimer();
    final ws = _wsChannel;
    if (ws != null) {
      try {
        await ws.sink
            .close(status.normalClosure)
            .timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    _wsChannel = null;
    _authenticated = false;
    await _accessUnitsController?.close();
    _accessUnitsController = null;
    await _playerPoseController?.close();
    _playerPoseController = null;
    if (_timedNotificationController != null &&
        !_timedNotificationController!.isClosed) {
      _timedNotificationController!.add(
        TimedNotification(
          fireAtEpochMs: null,
          title: null,
          body: null,
          sound: false,
        ),
      );
    }
    await _timedNotificationController?.close();
    _timedNotificationController = null;
    await _nudgeNotificationController?.close();
    _nudgeNotificationController = null;
    await _hibernationController?.close();
    _hibernationController = null;
    await _commandDeniedController?.close();
    _commandDeniedController = null;
    await _serverDisconnectController?.close();
    _serverDisconnectController = null;
    await _chatMessageController?.close();
    _chatMessageController = null;
    await _chatDeniedController?.close();
    _chatDeniedController = null;
    await _chatModeController?.close();
    _chatModeController = null;

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

class PlayerPose {
  final double yaw;
  final double pitch;

  const PlayerPose({required this.yaw, required this.pitch});
}

class CommandDeniedEvent {
  final String command;

  const CommandDeniedEvent({required this.command});
}

class ServerDisconnectEvent {
  final String reason;

  const ServerDisconnectEvent({required this.reason});
}

class _MpegTsMuxer {
  static const int _patPid = 0x0000;
  static const int _pmtPid = 0x1000;
  static const int _videoPid = 0x0100;
  static const int _programNumber = 1;
  static const int _pcrPid = _videoPid;

  int _patCc = 0;
  int _pmtCc = 0;
  int _videoCc = 0;

  void reset() {
    _patCc = 0;
    _pmtCc = 0;
    _videoCc = 0;
  }

  void writeTables(Socket client) {
    client.add(_buildPatPacket());
    client.add(_buildPmtPacket());
  }

  List<Uint8List> muxH264AccessUnit(Uint8List accessUnit, int pts90k) {
    final pes = _buildPes(accessUnit, pts90k);
    return _packetizePes(_videoPid, pes);
  }

  Uint8List _buildPatPacket() {
    final section = BytesBuilder(copy: false);
    section.addByte(0x00);
    section.addByte(0xB0);
    section.addByte(0x0D);
    section.addByte(0x00);
    section.addByte(0x01);
    section.addByte(0xC1);
    section.addByte(0x00);
    section.addByte(0x00);
    section.addByte((_programNumber >> 8) & 0xFF);
    section.addByte(_programNumber & 0xFF);
    section.addByte(0xE0 | ((_pmtPid >> 8) & 0x1F));
    section.addByte(_pmtPid & 0xFF);

    final crc = _crc32(section.toBytes());
    section.add(_u32be(crc));

    final payload = BytesBuilder(copy: false);
    payload.addByte(0x00);
    payload.add(section.toBytes());

    final packet = _tsPacket(
      pid: _patPid,
      payloadUnitStart: true,
      continuityCounter: _patCc,
      payload: payload.toBytes(),
    );
    _patCc = (_patCc + 1) & 0x0F;
    return packet;
  }

  Uint8List _buildPmtPacket() {
    final section = BytesBuilder(copy: false);
    section.addByte(0x02);
    section.addByte(0xB0);
    section.addByte(0x12);
    section.addByte((_programNumber >> 8) & 0xFF);
    section.addByte(_programNumber & 0xFF);
    section.addByte(0xC1);
    section.addByte(0x00);
    section.addByte(0x00);
    section.addByte(0xE0 | ((_pcrPid >> 8) & 0x1F));
    section.addByte(_pcrPid & 0xFF);
    section.addByte(0xF0);
    section.addByte(0x00);
    section.addByte(0x1B);
    section.addByte(0xE0 | ((_videoPid >> 8) & 0x1F));
    section.addByte(_videoPid & 0xFF);
    section.addByte(0xF0);
    section.addByte(0x00);

    final crc = _crc32(section.toBytes());
    section.add(_u32be(crc));

    final payload = BytesBuilder(copy: false);
    payload.addByte(0x00);
    payload.add(section.toBytes());

    final packet = _tsPacket(
      pid: _pmtPid,
      payloadUnitStart: true,
      continuityCounter: _pmtCc,
      payload: payload.toBytes(),
    );
    _pmtCc = (_pmtCc + 1) & 0x0F;
    return packet;
  }

  Uint8List _buildPes(Uint8List payload, int pts90k) {
    final b = BytesBuilder(copy: false);
    b.add(const [0x00, 0x00, 0x01]);
    b.addByte(0xE0);
    b.add(const [0x00, 0x00]);
    b.add(const [0x80, 0x80, 0x05]);
    b.add(_encodePts(pts90k));
    b.add(payload);
    return b.toBytes();
  }

  List<Uint8List> _packetizePes(int pid, Uint8List pes) {
    final packets = <Uint8List>[];
    int offset = 0;
    bool first = true;
    while (offset < pes.length) {
      final remaining = pes.length - offset;
      final payloadLen = remaining >= 184 ? 184 : remaining;
      final payload = pes.sublist(offset, offset + payloadLen);
      final packet = _tsPacket(
        pid: pid,
        payloadUnitStart: first,
        continuityCounter: _videoCc,
        payload: payload,
      );
      packets.add(packet);
      _videoCc = (_videoCc + 1) & 0x0F;
      offset += payloadLen;
      first = false;
    }
    return packets;
  }

  Uint8List _tsPacket({
    required int pid,
    required bool payloadUnitStart,
    required int continuityCounter,
    required List<int> payload,
  }) {
    final packet = Uint8List(188);
    packet[0] = 0x47;
    packet[1] = ((payloadUnitStart ? 0x40 : 0x00) | ((pid >> 8) & 0x1F));
    packet[2] = pid & 0xFF;

    int adaptationControl = 1;
    int headerIndex = 4;

    final payloadCapacity = 184;
    final remaining = payloadCapacity - payload.length;
    if (remaining > 0) {
      adaptationControl = 3;
      final adaptationLen = remaining - 1;
      packet[3] =
          ((adaptationControl & 0x03) << 4) | (continuityCounter & 0x0F);
      packet[4] = adaptationLen & 0xFF;
      headerIndex = 5;
      if (adaptationLen > 0) {
        packet[5] = 0x00;
        for (int i = 6; i < 5 + adaptationLen; i++) {
          packet[i] = 0xFF;
        }
        headerIndex = 5 + adaptationLen;
      }
    } else {
      packet[3] =
          ((adaptationControl & 0x03) << 4) | (continuityCounter & 0x0F);
    }

    packet.setRange(headerIndex, headerIndex + payload.length, payload);
    if (headerIndex + payload.length < 188) {
      packet.fillRange(headerIndex + payload.length, 188, 0xFF);
    }
    return packet;
  }

  static Uint8List _encodePts(int pts90k) {
    final pts = pts90k & 0x1FFFFFFFF;
    return Uint8List.fromList([
      0x21 | (((pts >> 30) & 0x07) << 1),
      (pts >> 22) & 0xFF,
      0x01 | (((pts >> 15) & 0x7F) << 1),
      (pts >> 7) & 0xFF,
      0x01 | (((pts) & 0x7F) << 1),
    ]);
  }

  static Uint8List _u32be(int v) {
    return Uint8List.fromList([
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= (byte & 0xFF) << 24;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x80000000) != 0) {
          crc = (crc << 1) ^ 0x04C11DB7;
        } else {
          crc <<= 1;
        }
        crc &= 0xFFFFFFFF;
      }
    }
    return crc & 0xFFFFFFFF;
  }
}
