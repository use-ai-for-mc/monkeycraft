import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:monkeycraft_client/shared/protocol_models.dart';

typedef OnClientStatusSent = void Function(int? fps);

class CommandSender {
  WebSocketChannel? _wsChannel;
  bool _authenticated = false;
  OnClientStatusSent? onClientStatusSent;

  void attach(WebSocketChannel channel) {
    _wsChannel = channel;
  }

  void setAuthenticated(bool value) {
    _authenticated = value;
  }

  void detach() {
    _wsChannel = null;
    _authenticated = false;
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
      onClientStatusSent?.call(fps is int && fps > 0 ? fps : null);
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
}
