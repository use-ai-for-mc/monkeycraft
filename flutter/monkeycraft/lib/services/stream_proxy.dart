import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:monkeycraft_client/services/protocol_models.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/chat_models.dart';

class StreamProxy {
  ServerSocket? _serverSocket;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _authenticated = false;
  bool _starting = false;
  Completer<void>? _startCompleter;
  final List<Socket> _activeClients = [];
  final List<Socket> _pendingClients = [];
  final _MpegTsMuxer _ts = _MpegTsMuxer();
  StreamController<Uint8List>? _accessUnitsController;
  StreamController<PlayerPose>? _playerPoseController;
  StreamController<TimedNotification>? _timedNotificationController;
  StreamController<ImmediateNotification>? _immediateNotificationController;
  StreamController<NudgeNotification>? _nudgeNotificationController;
  StreamController<ServerStatus>? _serverStatusController;
  StreamController<CommandDeniedEvent>? _commandDeniedController;
  StreamController<ServerDisconnectEvent>? _serverDisconnectController;
  StreamController<ChatMessage>? _chatMessageController;
  StreamController<ChatDeniedEvent>? _chatDeniedController;
  StreamController<ChatModeEvent>? _chatModeController;
  StreamController<DateTime>? _nonVideoPacketController;
  StreamController<DateTime>? _heartbeatAckController;
  StreamController<bool>? _screenStateController;
  Completer<List<ChatMessage>>? _chatSubscribeCompleter;
  int _fps = 10;
  int _frameIndex = 0;
  int _port = 0;
  int _colorMode = 0;
  DateTime? _lastServerMessageTime;
  DateTime? _heartbeatSentTime;
  bool _waitingForHeartbeatAck = false;
  Timer? _heartbeatTimer;

  // Lifecycle controllers - these persist across reconnections
  final StreamController<void> _connectionLostController =
      StreamController<void>.broadcast();
  final StreamController<void> _connectionRestoredController =
      StreamController<void>.broadcast();

  // Video state tracking (for staleness check)
  VideoState _videoState = VideoState.active;
  DateTime? _lastVideoStateEventTime;
  VideoState get videoState => _videoState;
  Duration? get timeSinceLastVideoStateEvent {
    final t = _lastVideoStateEventTime;
    return t == null ? null : DateTime.now().difference(t);
  }

  // Get the local proxy URL
  String get url => 'tcp://127.0.0.1:$_port';
  Stream<Uint8List> get accessUnits =>
      _accessUnitsController?.stream ?? const Stream.empty();
  Stream<PlayerPose> get playerPose =>
      _playerPoseController?.stream ?? const Stream.empty();
  Stream<TimedNotification> get timedNotifications =>
      _timedNotificationController?.stream ?? const Stream.empty();
  Stream<ImmediateNotification> get immediateNotifications =>
      _immediateNotificationController?.stream ?? const Stream.empty();
  Stream<NudgeNotification> get nudges =>
      _nudgeNotificationController?.stream ?? const Stream.empty();
  Stream<ServerStatus> get serverStatusEvents =>
      _serverStatusController?.stream ?? const Stream.empty();
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
  Stream<DateTime> get nonVideoPackets =>
      _nonVideoPacketController?.stream ?? const Stream.empty();
  Stream<DateTime> get heartbeatAcks =>
      _heartbeatAckController?.stream ?? const Stream.empty();
  Stream<bool> get screenStateEvents =>
      _screenStateController?.stream ?? const Stream.empty();
  Stream<void> get connectionLostEvents => _connectionLostController.stream;
  Stream<void> get connectionRestoredEvents =>
      _connectionRestoredController.stream;
  bool get isConnected => _authenticated && _wsChannel != null;

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

  Uri _parseServerUrl(String server) {
    server = server.trim();

    // If it already has a scheme, use it
    if (server.startsWith('https://')) {
      return Uri.parse(server.replaceFirst('https://', 'wss://'));
    }
    if (server.startsWith('http://')) {
      return Uri.parse(server.replaceFirst('http://', 'ws://'));
    }
    if (server.startsWith('wss://') || server.startsWith('ws://')) {
      return Uri.parse(server);
    }

    // No scheme - determine based on whether there's a port
    // IP:port format -> ws://
    // Domain without port -> wss:// (likely ngrok or similar)
    final hasPort = RegExp(r':\d+$').hasMatch(server);

    if (hasPort) {
      return Uri.parse('ws://$server');
    } else {
      // Domain without port - assume wss
      return Uri.parse('wss://$server');
    }
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
    String server,
    String password, {
    Duration connectTimeout = const Duration(seconds: 5),
    Duration authTimeout = const Duration(seconds: 5),
  }) async {
    // If already starting, wait for the existing operation to complete
    if (_starting && _startCompleter != null) {
      try {
        await _startCompleter!.future;
      } catch (e) {
        rethrow;
      }
      return;
    }

    _starting = true;
    _startCompleter = Completer<void>();
    try {
      await stop();
      _frameIndex = 0;
      _authenticated = false;
      _accessUnitsController = StreamController<Uint8List>.broadcast();
      _playerPoseController = StreamController<PlayerPose>.broadcast();
      _timedNotificationController =
          StreamController<TimedNotification>.broadcast();
      _immediateNotificationController =
          StreamController<ImmediateNotification>.broadcast();
      _nudgeNotificationController =
          StreamController<NudgeNotification>.broadcast();
      _serverStatusController = StreamController<ServerStatus>.broadcast();
      _commandDeniedController =
          StreamController<CommandDeniedEvent>.broadcast();
      _serverDisconnectController =
          StreamController<ServerDisconnectEvent>.broadcast();
      _chatMessageController = StreamController<ChatMessage>.broadcast();
      _chatDeniedController = StreamController<ChatDeniedEvent>.broadcast();
      _chatModeController = StreamController<ChatModeEvent>.broadcast();
      _nonVideoPacketController = StreamController<DateTime>.broadcast();
      _heartbeatAckController = StreamController<DateTime>.broadcast();
      _screenStateController = StreamController<bool>.broadcast();
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

      // 2. Parse server string and build WebSocket URL
      final wsUrl = _parseServerUrl(server);

      // 3. Connect to WebSocket
      _wsChannel = WebSocketChannel.connect(wsUrl);
      await _wsChannel!.ready.timeout(connectTimeout);

      final authCompleter = Completer<void>();
      void completeAuthError(Object error, [StackTrace? st]) {
        if (authCompleter.isCompleted) return;
        authCompleter.completeError(error, st);
      }

      // 3. Listen for messages (including AUTH_RESPONSE)
      String? serverSalt;
      _wsSubscription = _wsChannel!.stream.listen(
        (message) {
          _lastServerMessageTime = DateTime.now();
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
            _nonVideoPacketController?.add(DateTime.now());
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
                _startHeartbeatTimer();
                _notifyConnectionRestored();
                if (!authCompleter.isCompleted) {
                  authCompleter.complete();
                }
              } else if (data['type'] == 'AUTH_RESPONSE') {
                final success = data['success'] == true;
                if (success) {
                  _authenticated = true;
                  _startHeartbeatTimer();
                  _notifyConnectionRestored();
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
                final cachedMessages =
                    messagesList
                        ?.map(
                          (m) =>
                              ChatMessage.fromJson(m as Map<String, dynamic>),
                        )
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
                  _timedNotificationController?.add(timed);
                }
                final immediate = immediateFromJson(data);
                if (immediate != null) {
                  _immediateNotificationController?.add(immediate);
                }
                final nudge = nudgeFromJson(data);
                if (nudge != null) {
                  _nudgeNotificationController?.add(nudge);
                }
                // Parse SERVER_STATUS
                if (data['type'] == 'SERVER_STATUS') {
                  final serverStatus = ServerStatus.fromJson(data);

                  _lastVideoStateEventTime = DateTime.now();
                  _videoState = serverStatus.videoState;

                  _serverStatusController?.add(serverStatus);
                }
                // Parse SCREEN_STATE
                if (data['type'] == 'SCREEN_STATE') {
                  final isOpen = data['isOpen'] == true;
                  _screenStateController?.add(isOpen);
                }
              }
              if (data['type'] == 'HEARTBEAT_ACK') {
                _waitingForHeartbeatAck = false;
                _heartbeatSentTime = null;
                _heartbeatAckController?.add(DateTime.now());
              }
            } catch (e) {
              // Ignore parsing errors
            }
          }
        },
        onError: (e, st) {
          _stopHeartbeatTimer();
          _wsSubscription = null;
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
          _stopHeartbeatTimer();
          _wsSubscription = null;
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
      _startCompleter?.complete();
    } catch (e) {
      await stop();
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _starting = false;
      _startCompleter = null;
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
    if (command['type'] == 'CLIENT_STATUS') {
      final fps = command['fps'];
      if (fps is int && fps > 0) {
        _fps = fps;
      }
      final colorMode = command['colorMode'];
      if (colorMode is int) {
        _colorMode = colorMode;
      }
      _frameIndex = 0;
      _ts.reset();
    }
    return true;
  }

  void sendCommand(Map<String, dynamic> command) {
    trySendCommand(command);
  }

  bool sendClientStatus(
    ClientMode mode, {
    int? width,
    int? height,
    int? colorMode,
    int? fps,
  }) {
    final cmd = <String, dynamic>{
      'type': 'CLIENT_STATUS',
      'mode': mode == ClientMode.streaming ? 'STREAMING' : 'CHAT',
    };
    if (mode == ClientMode.streaming) {
      if (width != null) cmd['width'] = width;
      if (height != null) cmd['height'] = height;
      if (colorMode != null) cmd['colorMode'] = colorMode;
      if (fps != null) cmd['fps'] = fps;
    }

    return trySendCommand(cmd);
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

  void sendPing() {
    trySendCommand({'type': 'PING'});
  }

  void requestKeyframe() {
    trySendCommand({'type': 'REQUEST_KEYFRAME'});
  }

  void sendScreenTap(double normalizedX, double normalizedY) {
    trySendCommand({
      'type': 'SCREEN_TAP',
      'normalizedX': normalizedX,
      'normalizedY': normalizedY,
    });
  }

  void sendScreenKey(String key, bool pressed) {
    trySendCommand({'type': 'SCREEN_KEY', 'key': key, 'pressed': pressed});
  }

  void sendScreenClick(int button, double normalizedX, double normalizedY) {
    trySendCommand({
      'type': 'SCREEN_CLICK',
      'button': button,
      'normalizedX': normalizedX,
      'normalizedY': normalizedY,
    });
  }

  void sendScreenModifier(String modifier, bool active) {
    trySendCommand({
      'type': 'SCREEN_MODIFIER',
      'modifier': modifier,
      'active': active,
    });
  }

  void _notifyConnectionRestored() {
    if (!_connectionRestoredController.isClosed) {
      _connectionRestoredController.add(null);
    }
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _lastServerMessageTime = DateTime.now();
    _heartbeatSentTime = null;
    _waitingForHeartbeatAck = false;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_authenticated) return;
      final now = DateTime.now();
      final lastMessageAge = now.difference(_lastServerMessageTime ?? now);

      if (_waitingForHeartbeatAck && _heartbeatSentTime != null) {
        final heartbeatAge = now.difference(_heartbeatSentTime!);
        if (heartbeatAge.inSeconds >= 2) {
          _waitingForHeartbeatAck = false;
          _heartbeatSentTime = null;
          _connectionLostController.add(null);
          _wsChannel?.sink.close(status.normalClosure);
          return;
        }
      }

      if (lastMessageAge.inSeconds >= 3 && !_waitingForHeartbeatAck) {
        trySendCommand({'type': 'HEARTBEAT'});
        _waitingForHeartbeatAck = true;
        _heartbeatSentTime = now;
      }
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _waitingForHeartbeatAck = false;
    _heartbeatSentTime = null;
  }

  bool trySendChatMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return false;
    return trySendCommand({'type': 'SEND_CHAT', 'message': trimmed});
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
    return _chatSubscribeCompleter!.future.timeout(
      timeout,
      onTimeout: () {
        _chatSubscribeCompleter = null;
        return <ChatMessage>[];
      },
    );
  }

  void unsubscribeFromChat() {
    _chatSubscribeCompleter = null;
    trySendCommand({'type': 'UNSUBSCRIBE_CHAT'});
  }

  Future<void> stop() async {
    _stopHeartbeatTimer();
    await _wsSubscription?.cancel();
    _wsSubscription = null;
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
    await _immediateNotificationController?.close();
    _immediateNotificationController = null;
    await _nudgeNotificationController?.close();
    _nudgeNotificationController = null;
    await _serverStatusController?.close();
    _serverStatusController = null;
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
    await _nonVideoPacketController?.close();
    _nonVideoPacketController = null;
    await _heartbeatAckController?.close();
    _heartbeatAckController = null;
    await _screenStateController?.close();
    _screenStateController = null;
    // Note: _connectionLostController and _connectionRestoredController persist

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
