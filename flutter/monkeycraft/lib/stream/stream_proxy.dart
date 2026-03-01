import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/chat/chat_models.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/mpeg_ts_muxer.dart';

class AuthFailureException implements Exception {
  final String message;
  AuthFailureException([String? message])
    : message = message ?? 'Authentication failed';
  @override
  String toString() => 'AuthFailureException: $message';
}

class StreamProxy {
  ServerSocket? _serverSocket;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _authenticated = false;
  bool _starting = false;
  Completer<void>? _startCompleter;
  final List<Socket> _activeClients = [];
  final List<Socket> _pendingClients = [];
  final MpegTsMuxer _ts = MpegTsMuxer();
  StreamController<Uint8List>? _accessUnitsController;
  StreamController<StreamResolution>? _serverResolutionController;
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
  bool _screenOpen = false;
  bool get screenOpen => _screenOpen;
  Completer<List<ChatMessage>>? _chatSubscribeCompleter;
  int _fps = 10;
  int _frameIndex = 0;
  int _port = 0;
  DateTime? _lastServerMessageTime;
  DateTime? _heartbeatSentTime;
  bool _waitingForHeartbeatAck = false;
  Timer? _heartbeatTimer;

  int? _lastReceivedWidth;
  int? _lastReceivedHeight;

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
  Stream<StreamResolution> get serverResolutionEvents =>
      _serverResolutionController?.stream ?? const Stream.empty();
  int? get lastFrameWidth => _lastReceivedWidth;
  int? get lastFrameHeight => _lastReceivedHeight;
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
      _serverResolutionController =
          StreamController<StreamResolution>.broadcast();
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

            List<int> h264Data = message;
            int? frameWidth;
            int? frameHeight;

            if (message.length >= 6 &&
                message[0] == 0x4D &&
                message[1] == 0x43) {
              frameWidth = (message[2] << 8) | message[3];
              frameHeight = (message[4] << 8) | message[5];
              _serverResolutionController?.add(
                StreamResolution(frameWidth, frameHeight),
              );
              h264Data = message.sublist(6);
            }

            if (frameWidth != null && frameHeight != null) {
              _lastReceivedWidth = frameWidth;
              _lastReceivedHeight = frameHeight;
            }

            _accessUnitsController?.add(Uint8List.fromList(h264Data));
            _wsChannel!.sink.add(jsonEncode({'type': 'ACK'}));

            if (_isIdrFrame(h264Data)) {
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
                    AuthFailureException(
                      msg == null || msg.isEmpty ? null : msg,
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
                  _screenOpen = isOpen;
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
    bool? autoFaceMovement,
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
    if (autoFaceMovement != null) {
      cmd['autoFaceMovement'] = autoFaceMovement;
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

  void sendScreenHover(double normalizedX, double normalizedY) {
    trySendCommand({
      'type': 'SCREEN_HOVER',
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
    await _serverResolutionController?.close();
    _serverResolutionController = null;
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
    _screenOpen = false;
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
