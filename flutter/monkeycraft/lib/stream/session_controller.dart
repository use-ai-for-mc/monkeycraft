import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monkeycraft_client/stream/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';
import 'package:monkeycraft_client/stream/session_state.dart';

export 'package:monkeycraft_client/stream/session_state.dart';

class SessionController extends ChangeNotifier {
  final StreamProxy proxy;
  final StreamSettingsStore settingsStore;

  SessionState _state = SessionState.initial();
  SessionState get state => _state;

  final StreamController<SessionState> _stateController =
      StreamController<SessionState>.broadcast();
  Stream<SessionState> get stateStream => _stateController.stream;

  HardwareH264Decoder? decoder;
  int? textureId;
  int streamWidth = 0;
  int streamHeight = 0;
  StreamSettings settings = StreamSettings.defaults;

  StreamSubscription<ServerStatus>? _serverStatusSub;
  StreamSubscription<StreamResolution>? _serverResolutionSub;

  bool _restarting = false;
  StreamResolution? _pendingResolution;
  StreamResolution? _expectedResolution;
  StreamResolution? _confirmedResolution;

  DateTime? _lastFrameTime;
  DateTime? _lastHeartbeatAckTime;

  Timer? _reconnectRetryTimer;
  static const int _maxReconnectRetries = 3;
  String? _server;
  String? _password;

  bool get supportedPlatform => Platform.isIOS || Platform.isAndroid;

  SessionController({required this.proxy, required this.settingsStore});

  void initialize() {
    _attachToProxy();
    _updateState(_state.copyWith(connected: proxy.isConnected));
  }

  void _attachToProxy() {
    _serverStatusSub?.cancel();
    _serverStatusSub = proxy.serverStatusEvents.listen(_handleServerStatus);
    _serverResolutionSub?.cancel();
    _serverResolutionSub = proxy.serverResolutionEvents.listen(
      _handleServerResolution,
    );
  }

  void _handleServerResolution(StreamResolution resolution) {
    final expected = _expectedResolution;
    if (expected == null) return;

    if (resolution.width != expected.width ||
        resolution.height != expected.height) {
      _handleResolutionMismatch(resolution, expected);
    } else {
      _confirmedResolution = resolution;
      if (_state.resolutionMismatch) {
        _updateState(_state.copyWith(clearResolutionMismatch: true));
      }
    }
  }

  void _handleResolutionMismatch(
    StreamResolution server,
    StreamResolution expected,
  ) {
    streamWidth = expected.width;
    streamHeight = expected.height;
    final msg =
        'Server: ${server.width}x${server.height}, Expected: ${expected.width}x${expected.height}';
    _updateState(
      _state.copyWith(resolutionMismatch: true, resolutionMismatchMessage: msg),
    );
    syncStatus(resolution: expected);
  }

  bool shouldAcceptFrame(StreamResolution? frameResolution) {
    if (frameResolution == null) {
      return _confirmedResolution != null && !_state.resolutionMismatch;
    }
    final expected = _expectedResolution;
    if (expected == null) return false;
    return frameResolution.width == expected.width &&
        frameResolution.height == expected.height;
  }

  void handleAccessUnit(Uint8List data, {int? frameWidth, int? frameHeight}) {
    final expected = _expectedResolution;
    if (expected == null) {
      return;
    }

    final resolution = frameWidth != null && frameHeight != null
        ? StreamResolution(frameWidth, frameHeight)
        : null;

    if (!shouldAcceptFrame(resolution)) {
      return;
    }

    decoder?.pushAccessUnit(data);
    updateFrameTime();
  }

  void reattachToProxy() {
    _attachToProxy();
  }

  void _updateState(SessionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
      _stateController.add(newState);
    }
  }

  void updateConnectionState(bool connected) {
    _updateState(_state.copyWith(connected: connected));
  }

  void setForeground(bool foreground) {
    _updateState(_state.copyWith(foreground: foreground));
  }

  void setWaitingForStream(bool waiting) {
    if (_state.waitingForStream != waiting) {
      _updateState(_state.copyWith(waitingForStream: waiting));
    }
  }

  void updateSettings(StreamSettings newSettings) {
    settings = newSettings;
    notifyListeners();
  }

  void _handleServerStatus(ServerStatus status) {
    // Reset frame time when exiting hibernation so we don't immediately show "waiting"
    if (_state.videoState == VideoState.hibernating &&
        status.videoState == VideoState.active) {
      _lastFrameTime = null;
      setWaitingForStream(false);
    }

    _updateState(
      _state.copyWith(
        videoState: status.videoState,
        videoStateMessage: status.message ?? '',
        timedFireAtEpochMs: status.timedFireAtEpochMs,
        timedTitle: status.timedTitle,
        timedBody: status.timedBody,
        timedSound: status.timedSound,
        timedCountDownText: status.timedCountDownText,
        clearTimedNotification: !status.hasTimedNotification,
      ),
    );
  }

  void setMode(ClientMode mode, {StreamResolution? resolution}) {
    if (resolution != null) {
      _expectedResolution = resolution;
      streamWidth = resolution.width;
      streamHeight = resolution.height;
      _updateState(_state.copyWith(mode: mode, clearResolutionMismatch: true));
    } else {
      _updateState(_state.copyWith(mode: mode));
    }
    proxy.sendClientStatus(
      mode,
      width: resolution?.width,
      height: resolution?.height,
      colorMode: settings.colorMode,
      fps: settings.fps,
      autoFaceMovement: settings.autoFaceMovement,
    );
  }

  void syncStatus({StreamResolution? resolution}) {
    if (resolution != null) {
      final previousExpected = _expectedResolution;
      _expectedResolution = resolution;
      streamWidth = resolution.width;
      streamHeight = resolution.height;

      final resolutionChanged =
          previousExpected == null ||
          previousExpected.width != resolution.width ||
          previousExpected.height != resolution.height;

      if (resolutionChanged) {
        _confirmedResolution = null;
        decoder?.reset();
        final msg = 'Waiting for ${resolution.width}x${resolution.height}...';
        _updateState(
          _state.copyWith(
            resolutionMismatch: true,
            resolutionMismatchMessage: msg,
          ),
        );
      }
    }
    proxy.sendClientStatus(
      _state.mode,
      width: resolution?.width,
      height: resolution?.height,
      colorMode: settings.colorMode,
      fps: settings.fps,
      autoFaceMovement: settings.autoFaceMovement,
    );
  }

  bool get shouldAutoNavigateToChat =>
      settings.autoSwitchRideChat &&
      _state.videoState == VideoState.hibernating &&
      _state.mode == ClientMode.streaming;

  void updateFrameTime() {
    _lastFrameTime = DateTime.now();
  }

  void updateHeartbeatAckTime() {
    _lastHeartbeatAckTime = DateTime.now();
  }

  void resetFrameTime() {
    _lastFrameTime = null;
    setWaitingForStream(false);
  }

  void checkWaitingForStream() {
    if (!_state.foreground ||
        _state.videoState == VideoState.hibernating ||
        _state.mode == ClientMode.chat ||
        _state.mode == ClientMode.map) {
      if (_state.waitingForStream) {
        setWaitingForStream(false);
      }
      return;
    }

    final now = DateTime.now();
    final lastFrame = _lastFrameTime;
    final lastHeartbeatAck = _lastHeartbeatAckTime;

    if (lastFrame == null) {
      // No frames yet, don't set waiting
      return;
    }

    final frameAge = now.difference(lastFrame).inSeconds;
    final heartbeatAckAge = lastHeartbeatAck != null
        ? now.difference(lastHeartbeatAck).inSeconds
        : null;

    final shouldWait =
        frameAge >= 3 && (heartbeatAckAge == null || heartbeatAckAge < 10);

    if (shouldWait != _state.waitingForStream) {
      setWaitingForStream(shouldWait);
    }
  }

  Future<void> restartStream(
    StreamResolution target, {
    Future<void> Function()? onDecoderNeeded,
  }) async {
    if (_restarting) {
      _pendingResolution = target;
      return;
    }

    if (_state.mode != ClientMode.streaming) {
      return;
    }

    if (_state.videoState == VideoState.hibernating) {
      return;
    }

    _restarting = true;

    streamWidth = target.width;
    streamHeight = target.height;

    syncStatus(resolution: target);

    if (supportedPlatform) {
      if (decoder == null && onDecoderNeeded != null) {
        await onDecoderNeeded();
      }
    }

    final pending = _pendingResolution;
    _pendingResolution = null;
    if (pending != null) {
      _restarting = false;
      await restartStream(pending, onDecoderNeeded: onDecoderNeeded);
      return;
    }

    _restarting = false;
  }

  void refreshVideo() {
    decoder?.reset();
    proxy.requestKeyframe();
  }

  Future<void> disposeDecoder() async {
    final d = decoder;
    decoder = null;
    textureId = null;
    await d?.dispose();
  }

  void setCredentials(String server, String password) {
    _server = server;
    _password = password;
  }

  void handleConnectionLost() {
    if (_state.shouldReturnToLogin) return;
    _updateState(_state.copyWith(isReconnecting: true));
    _scheduleReconnectRetry();
  }

  void _scheduleReconnectRetry() {
    _reconnectRetryTimer?.cancel();

    if (_state.reconnectRetryCount >= _maxReconnectRetries ||
        _state.authFailed) {
      _updateState(_state.copyWith(shouldReturnToLogin: true));
      return;
    }

    final delay = Duration(seconds: 1 << _state.reconnectRetryCount);
    _reconnectRetryTimer = Timer(delay, () {
      _attemptReconnect();
    });
  }

  Future<void> _attemptReconnect() async {
    if (_server == null || _password == null) return;

    try {
      await proxy.start(_server!, _password!);
      proxy.sendPing();

      _updateState(
        _state.copyWith(
          connected: true,
          clearReconnectionState: true,
        ),
      );
      _reconnectRetryTimer?.cancel();

      _onConnectionRestored();
    } on AuthFailureException {
      _updateState(
        _state.copyWith(
          authFailed: true,
          shouldReturnToLogin: true,
          isReconnecting: false,
        ),
      );
    } catch (_) {
      final newCount = _state.reconnectRetryCount + 1;
      _updateState(_state.copyWith(reconnectRetryCount: newCount));

      if (newCount >= _maxReconnectRetries) {
        _updateState(
          _state.copyWith(shouldReturnToLogin: true, isReconnecting: false),
        );
      } else {
        _scheduleReconnectRetry();
      }
    }
  }

  void _onConnectionRestored() {
    _attachToProxy();
  }

  Future<void> resumeConnection() async {
    if (proxy.isConnected) return;
    if (_server == null || _password == null) return;

    _updateState(_state.copyWith(isReconnecting: true));
    try {
      await proxy.start(_server!, _password!);
      proxy.sendPing();
      _updateState(
        _state.copyWith(
          connected: true,
          clearReconnectionState: true,
        ),
      );
      _onConnectionRestored();
    } on AuthFailureException {
      _updateState(
        _state.copyWith(
          authFailed: true,
          shouldReturnToLogin: true,
          isReconnecting: false,
        ),
      );
    } catch (e) {
      debugPrint('SessionController: resume failed: $e');
      handleConnectionLost();
    }
  }

  void resetReconnectionState() {
    _reconnectRetryTimer?.cancel();
    _updateState(_state.copyWith(clearReconnectionState: true));
  }

  @override
  void dispose() {
    _reconnectRetryTimer?.cancel();
    _serverStatusSub?.cancel();
    _serverResolutionSub?.cancel();
    _stateController.close();
    super.dispose();
  }
}
