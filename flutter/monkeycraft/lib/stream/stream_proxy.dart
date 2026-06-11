import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/chat/chat_models.dart';
import 'package:monkeycraft_client/stream/h264_nal.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/proxy/video_relay.dart';
import 'package:monkeycraft_client/stream/proxy/command_sender.dart';

class AuthFailureException implements Exception {
  final String message;
  AuthFailureException([String? message])
    : message = message ?? 'Authentication failed';
  @override
  String toString() => 'AuthFailureException: $message';
}

class StreamProxy {
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _authenticated = false;
  Set<String> _serverCapabilities = {};
  bool _starting = false;
  Completer<void>? _startCompleter;

  final VideoRelay _videoRelay = VideoRelay();
  final CommandSender _commandSender = CommandSender();

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
  StreamController<MapData>? _mapDataController;
  StreamController<WorldState>? _worldStateController;
  StreamController<List<ServerListEntry>>? _serverListController;
  StreamController<JoinResult>? _joinResultController;
  StreamController<List<String>>? _playerListController;
  List<String> _playerList = const [];
  StreamController<int>? _playerCountController;
  int _playerCount = 0;
  WorldState? _worldState;
  bool _screenOpen = false;
  bool get screenOpen => _screenOpen;
  Completer<List<ChatMessage>>? _chatSubscribeCompleter;

  DateTime? _lastServerMessageTime;
  DateTime? _heartbeatSentTime;
  bool _waitingForHeartbeatAck = false;
  Timer? _heartbeatTimer;

  int? _lastReceivedWidth;
  int? _lastReceivedHeight;

  final StreamController<void> _connectionLostController =
      StreamController<void>.broadcast();
  final StreamController<void> _connectionRestoredController =
      StreamController<void>.broadcast();

  VideoState _videoState = VideoState.active;
  DateTime? _lastVideoStateEventTime;
  VideoState get videoState => _videoState;
  Duration? get timeSinceLastVideoStateEvent {
    final t = _lastVideoStateEventTime;
    return t == null ? null : DateTime.now().difference(t);
  }

  String get url => _videoRelay.url;
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
  Stream<MapData> get mapDataEvents =>
      _mapDataController?.stream ?? const Stream.empty();
  Stream<WorldState> get worldStateEvents =>
      _worldStateController?.stream ?? const Stream.empty();
  Stream<List<ServerListEntry>> get serverListEvents =>
      _serverListController?.stream ?? const Stream.empty();
  Stream<JoinResult> get joinResultEvents =>
      _joinResultController?.stream ?? const Stream.empty();
  Stream<List<String>> get playerListEvents =>
      _playerListController?.stream ?? const Stream.empty();
  List<String> get playerList => _playerList;
  Stream<int> get playerCountEvents =>
      _playerCountController?.stream ?? const Stream.empty();
  int get playerCount => _playerCount;
  WorldState? get worldState => _worldState;
  Stream<void> get connectionLostEvents => _connectionLostController.stream;
  Stream<void> get connectionRestoredEvents =>
      _connectionRestoredController.stream;
  bool get isConnected => _authenticated && _wsChannel != null;
  Set<String> get serverCapabilities => _serverCapabilities;
  bool serverSupports(String capability) =>
      _serverCapabilities.contains(capability);

  // Delegate command methods to CommandSender
  bool trySendCommand(Map<String, dynamic> command) =>
      _commandSender.trySendCommand(command);
  void sendCommand(Map<String, dynamic> command) =>
      _commandSender.sendCommand(command);
  bool sendClientStatus(
    ClientMode mode, {
    int? width,
    int? height,
    int? colorMode,
    int? fps,
    bool? autoFaceMovement,
    bool? dataSaver,
  }) => _commandSender.sendClientStatus(
    mode,
    width: width,
    height: height,
    colorMode: colorMode,
    fps: fps,
    autoFaceMovement: autoFaceMovement,
    dataSaver: dataSaver,
  );
  bool trySendRunCommand(String command) =>
      _commandSender.trySendRunCommand(command);
  void sendRunCommand(String command) => _commandSender.sendRunCommand(command);
  void sendPing() => _commandSender.sendPing();
  void requestKeyframe() => _commandSender.requestKeyframe();
  void sendScreenTap(double normalizedX, double normalizedY) =>
      _commandSender.sendScreenTap(normalizedX, normalizedY);
  void sendScreenKey(String key, bool pressed) =>
      _commandSender.sendScreenKey(key, pressed);
  void sendScreenClick(int button, double normalizedX, double normalizedY) =>
      _commandSender.sendScreenClick(button, normalizedX, normalizedY);
  void sendScreenHover(double normalizedX, double normalizedY) =>
      _commandSender.sendScreenHover(normalizedX, normalizedY);
  void sendScreenModifier(String modifier, bool active) =>
      _commandSender.sendScreenModifier(modifier, active);
  bool trySendChatMessage(String message) =>
      _commandSender.trySendChatMessage(message);
  void enterChatMode() => _commandSender.enterChatMode();
  void exitChatMode() => _commandSender.exitChatMode();
  void sendMapInteract(int entityId) =>
      _commandSender.sendMapInteract(entityId);
  void requestServerList() =>
      _commandSender.trySendCommand({'type': 'LIST_SERVERS'});
  void joinServer(
    String address, {
    String? name,
    bool acceptResourcePack = true,
  }) {
    final cmd = <String, dynamic>{
      'type': 'JOIN_SERVER',
      'address': address,
      'acceptResourcePack': acceptResourcePack,
    };
    if (name != null && name.isNotEmpty) cmd['name'] = name;
    _commandSender.trySendCommand(cmd);
  }

  void leaveWorld() => _commandSender.trySendCommand({'type': 'LEAVE_WORLD'});

  void requestPlayerList() =>
      _commandSender.trySendCommand({'type': 'GET_PLAYER_LIST'});

  void requestPlayerCount() =>
      _commandSender.trySendCommand({'type': 'GET_PLAYER_COUNT'});

  /// Returns the latest world phase, waiting briefly for the first WORLD_STATE
  /// after authentication. Returns null if the mod never reports one.
  Future<WorldState?> awaitWorldState({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_worldState != null) return _worldState;
    final controller = _worldStateController;
    if (controller == null) return null;
    try {
      return await controller.stream.first.timeout(timeout);
    } catch (_) {
      return _worldState;
    }
  }

  Uri _parseServerUrl(String server) {
    server = server.trim();

    if (server.startsWith('https://')) {
      return Uri.parse(server.replaceFirst('https://', 'wss://'));
    }
    if (server.startsWith('http://')) {
      return Uri.parse(server.replaceFirst('http://', 'ws://'));
    }
    if (server.startsWith('wss://') || server.startsWith('ws://')) {
      return Uri.parse(server);
    }

    final hasPort = RegExp(r':\d+$').hasMatch(server);

    if (hasPort) {
      return Uri.parse('ws://$server');
    } else {
      return Uri.parse('wss://$server');
    }
  }

  static final Random _saltRandom = Random.secure();

  String _generateSalt() {
    final random = List<int>.generate(16, (_) => _saltRandom.nextInt(256));
    return base64Encode(random);
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
      _authenticated = false;
      _initStreamControllers();

      // Start video relay (local TCP server)
      await _videoRelay.start();

      // Connect to WebSocket
      final wsUrl = _parseServerUrl(server);
      _wsChannel = WebSocketChannel.connect(wsUrl);
      await _wsChannel!.ready.timeout(connectTimeout);

      // Attach command sender
      _commandSender.attach(_wsChannel!);
      _commandSender.onClientStatusSent = (fps) {
        if (fps != null) _videoRelay.updateFps(fps);
        _videoRelay.reset();
      };

      final authCompleter = Completer<void>();
      void completeAuthError(Object error, [StackTrace? st]) {
        if (authCompleter.isCompleted) return;
        authCompleter.completeError(error, st);
      }

      String? serverSalt;
      _wsSubscription = _wsChannel!.stream.listen(
        (message) {
          _lastServerMessageTime = DateTime.now();
          if (message is List<int>) {
            _handleBinaryMessage(message);
          } else {
            _handleTextMessage(
              message,
              serverSalt: serverSalt,
              password: password,
              onServerSalt: (salt) => serverSalt = salt,
              completeAuthError: completeAuthError,
              onAuthSuccess: () {
                if (!authCompleter.isCompleted) authCompleter.complete();
              },
            );
          }
        },
        onError: (e, st) {
          _handleConnectionLoss();
          completeAuthError(e, st);
        },
        onDone: () {
          _handleConnectionLoss();
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

  void _initStreamControllers() {
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
    _mapDataController = StreamController<MapData>.broadcast();
    _worldStateController = StreamController<WorldState>.broadcast();
    _serverListController =
        StreamController<List<ServerListEntry>>.broadcast();
    _joinResultController = StreamController<JoinResult>.broadcast();
    _playerListController = StreamController<List<String>>.broadcast();
    _playerCountController = StreamController<int>.broadcast();
  }

  void _handleBinaryMessage(List<int> message) {
    if (!_authenticated) return;

    // Check for map data frame (magic: 0x4D 0x4D = "MM")
    if (message.length >= 24 && message[0] == 0x4D && message[1] == 0x4D) {
      _handleMapDataFrame(message);
      return;
    }

    List<int> h264Data = message;
    int? frameWidth;
    int? frameHeight;

    if (message.length >= 6 && message[0] == 0x4D && message[1] == 0x43) {
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
    // Null-safe: a binary frame can be handled after the channel is torn down
    // by a connection-loss callback; a missed ACK is harmless.
    _wsChannel?.sink.add(jsonEncode({'type': 'ACK'}));

    final isIdr = containsIdrNal(h264Data);
    _videoRelay.onVideoFrame(h264Data, isIdr);
  }

  void _handleMapDataFrame(List<int> message) {
    try {
      final data = ByteData.sublistView(Uint8List.fromList(message));
      int offset = 2; // skip magic bytes

      final playerX = data.getFloat64(offset, Endian.big);
      offset += 8;
      final playerZ = data.getFloat64(offset, Endian.big);
      offset += 8;
      final playerYaw = data.getFloat32(offset, Endian.big);
      offset += 4;
      final uuidLength = data.getInt16(offset, Endian.big);
      offset += 2;
      final uuidBytes = message.sublist(offset, offset + uuidLength);
      final playerUuid = utf8.decode(uuidBytes);
      offset += uuidLength;
      final entityCount = data.getInt16(offset, Endian.big);
      offset += 2;

      final entities = <MapEntity>[];
      for (int i = 0; i < entityCount; i++) {
        final type = data.getUint8(offset);
        offset += 1;
        final x = data.getFloat64(offset, Endian.big);
        offset += 8;
        final z = data.getFloat64(offset, Endian.big);
        offset += 8;
        final entityId = data.getInt32(offset, Endian.big);
        offset += 4;
        final nameLength = data.getInt16(offset, Endian.big);
        offset += 2;
        final nameBytes = message.sublist(offset, offset + nameLength);
        final name = utf8.decode(nameBytes);
        offset += nameLength;

        entities.add(MapEntity(
          type: type,
          x: x,
          z: z,
          entityId: entityId,
          name: name,
        ));
      }

      _mapDataController?.add(MapData(
        playerX: playerX,
        playerZ: playerZ,
        playerYaw: playerYaw.toDouble(),
        playerUuid: playerUuid,
        entities: entities,
      ));
    } catch (e) {
      debugPrint('StreamProxy: error parsing map data: $e');
    }
  }

  void _handleTextMessage(
    dynamic message, {
    required String? serverSalt,
    required String password,
    required void Function(String) onServerSalt,
    required void Function(Object, [StackTrace?]) completeAuthError,
    required void Function() onAuthSuccess,
  }) {
    _nonVideoPacketController?.add(DateTime.now());
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'HELLO') {
        final salt = data['salt']?.toString();
        if (salt != null) {
          onServerSalt(salt);
          final clientSalt = _generateSalt();
          final signature = _computeHmac(password, '$salt$clientSalt');
          final authMsg = jsonEncode({
            'type': 'AUTH',
            'salt': clientSalt,
            'signature': signature,
            'protocolVersion': 2,
          });
          _wsChannel!.sink.add(authMsg);
        } else {
          completeAuthError(Exception('Server did not provide salt'));
        }
      } else if (data['type'] == 'AUTH_OK') {
        final versionWarning = data['versionWarning'];
        if (versionWarning is String && versionWarning.isNotEmpty) {
          debugPrint('StreamProxy: server protocol version warning: $versionWarning');
        }
        final caps = data['capabilities'];
        _serverCapabilities = caps is List
            ? caps.map((e) => e.toString()).toSet()
            : <String>{};
        _authenticated = true;
        _commandSender.setAuthenticated(true);
        _startHeartbeatTimer();
        _notifyConnectionRestored();
        onAuthSuccess();
      } else if (data['type'] == 'AUTH_RESPONSE') {
        final success = data['success'] == true;
        if (success) {
          _authenticated = true;
          _commandSender.setAuthenticated(true);
          _startHeartbeatTimer();
          _notifyConnectionRestored();
          onAuthSuccess();
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
                  (m) => ChatMessage.fromJson(m as Map<String, dynamic>),
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
        _dispatchMiscMessage(data);
      }
      if (data['type'] == 'HEARTBEAT_ACK') {
        _waitingForHeartbeatAck = false;
        _heartbeatSentTime = null;
        _heartbeatAckController?.add(DateTime.now());
      }
    } catch (e) {
      debugPrint('StreamProxy: error parsing message: $e');
    }
  }

  void _dispatchMiscMessage(dynamic data) {
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
    if (data['type'] == 'SERVER_STATUS') {
      final serverStatus = ServerStatus.fromJson(data);
      _lastVideoStateEventTime = DateTime.now();
      _videoState = serverStatus.videoState;
      _serverStatusController?.add(serverStatus);
    }
    if (data['type'] == 'SCREEN_STATE') {
      final isOpen = data['isOpen'] == true;
      _screenOpen = isOpen;
      _screenStateController?.add(isOpen);
    }
    if (data['type'] == 'WORLD_STATE') {
      final worldState = WorldState.fromJson(data);
      _worldState = worldState;
      _worldStateController?.add(worldState);
    }
    if (data['type'] == 'SERVER_LIST') {
      final servers =
          (data['servers'] as List<dynamic>?)
              ?.map((e) => ServerListEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <ServerListEntry>[];
      _serverListController?.add(servers);
    }
    if (data['type'] == 'JOIN_RESULT') {
      _joinResultController?.add(JoinResult.fromJson(data));
    }
    if (data['type'] == 'PLAYER_LIST') {
      final names =
          (data['players'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];
      _playerList = names;
      _playerListController?.add(names);
    }
    if (data['type'] == 'PLAYER_COUNT') {
      final count = data['count'];
      if (count is num) {
        _playerCount = count.toInt();
        _playerCountController?.add(_playerCount);
      }
    }
  }

  void _handleConnectionLoss() {
    final wasAuthenticated = _authenticated;
    _stopHeartbeatTimer();
    _wsSubscription = null;
    _wsChannel = null;
    _authenticated = false;
    _serverCapabilities = {};
    _commandSender.detach();
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
    if (wasAuthenticated && !_connectionLostController.isClosed) {
      _connectionLostController.add(null);
    }
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
        if (heartbeatAge.inSeconds >= 5) {
          _waitingForHeartbeatAck = false;
          _heartbeatSentTime = null;
          _connectionLostController.add(null);
          _wsChannel?.sink.close(status.normalClosure);
          return;
        }
      }

      if (lastMessageAge.inSeconds >= 3 && !_waitingForHeartbeatAck) {
        _commandSender.trySendCommand({'type': 'HEARTBEAT'});
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

  Future<List<ChatMessage>> subscribeToChat({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_authenticated || _wsChannel == null) {
      return <ChatMessage>[];
    }
    _chatSubscribeCompleter = Completer<List<ChatMessage>>();

    _commandSender.trySendCommand({'type': 'SUBSCRIBE_CHAT'});
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
    _commandSender.trySendCommand({'type': 'UNSUBSCRIBE_CHAT'});
  }

  Future<void> stop() async {
    _stopHeartbeatTimer();
    _commandSender.detach();
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
    await _closeStreamControllers();
    _screenOpen = false;
    _worldState = null;
    await _videoRelay.stop();
  }

  Future<void> _closeStreamControllers() async {
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
    await _mapDataController?.close();
    _mapDataController = null;
    await _worldStateController?.close();
    _worldStateController = null;
    await _serverListController?.close();
    _serverListController = null;
    await _joinResultController?.close();
    _joinResultController = null;
    await _playerListController?.close();
    _playerListController = null;
    _playerList = const [];
    await _playerCountController?.close();
    _playerCountController = null;
    _playerCount = 0;
    _serverCapabilities = {};
  }
}
