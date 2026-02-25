import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:monkeycraft_client/services/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/services/protocol_models.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';
import 'package:monkeycraft_client/services/stream_resolution.dart';
import 'package:monkeycraft_client/services/stream_settings.dart';

class SessionState {
  final ClientMode mode;
  final VideoState videoState;
  final String videoStateMessage;
  final bool connected;
  final bool foreground;
  final bool waitingForStream;

  final int? timedFireAtEpochMs;
  final String? timedTitle;
  final String? timedBody;
  final bool timedSound;
  final String? timedCountDownText;

  const SessionState({
    required this.mode,
    required this.videoState,
    required this.videoStateMessage,
    required this.connected,
    required this.foreground,
    required this.waitingForStream,
    this.timedFireAtEpochMs,
    this.timedTitle,
    this.timedBody,
    this.timedSound = true,
    this.timedCountDownText,
  });

  factory SessionState.initial() => const SessionState(
    mode: ClientMode.streaming,
    videoState: VideoState.active,
    videoStateMessage: '',
    connected: false,
    foreground: true,
    waitingForStream: false,
  );

  bool get shouldShowVideo =>
      mode == ClientMode.streaming &&
      videoState == VideoState.active &&
      connected &&
      foreground;

  bool get shouldShowHibernation =>
      mode == ClientMode.streaming &&
      videoState == VideoState.hibernating &&
      foreground;

  bool get shouldShowWaiting =>
      waitingForStream &&
      mode == ClientMode.streaming &&
      connected &&
      foreground;

  bool get isInChat => mode == ClientMode.chat;

  bool get shouldStreamVideo =>
      mode == ClientMode.streaming &&
      videoState == VideoState.active &&
      connected &&
      foreground;

  bool get hasTimedNotification => timedFireAtEpochMs != null;

  TimedNotification? get timedNotification => hasTimedNotification
      ? TimedNotification(
          fireAtEpochMs: timedFireAtEpochMs,
          title: timedTitle,
          body: timedBody,
          sound: timedSound,
          countDownText: timedCountDownText,
        )
      : null;

  SessionState copyWith({
    ClientMode? mode,
    VideoState? videoState,
    String? videoStateMessage,
    bool? connected,
    bool? foreground,
    bool? waitingForStream,
    int? timedFireAtEpochMs,
    String? timedTitle,
    String? timedBody,
    bool? timedSound,
    String? timedCountDownText,
    bool clearVideoStateMessage = false,
    bool clearTimedNotification = false,
  }) {
    return SessionState(
      mode: mode ?? this.mode,
      videoState: videoState ?? this.videoState,
      videoStateMessage: clearVideoStateMessage
          ? ''
          : (videoStateMessage ?? this.videoStateMessage),
      connected: connected ?? this.connected,
      foreground: foreground ?? this.foreground,
      waitingForStream: waitingForStream ?? this.waitingForStream,
      timedFireAtEpochMs: clearTimedNotification
          ? null
          : (timedFireAtEpochMs ?? this.timedFireAtEpochMs),
      timedTitle: clearTimedNotification
          ? null
          : (timedTitle ?? this.timedTitle),
      timedBody: clearTimedNotification ? null : (timedBody ?? this.timedBody),
      timedSound: clearTimedNotification
          ? true
          : (timedSound ?? this.timedSound),
      timedCountDownText: clearTimedNotification
          ? null
          : (timedCountDownText ?? this.timedCountDownText),
    );
  }

  @override
  String toString() {
    return 'SessionState(mode=$mode, videoState=$videoState, connected=$connected, waiting=$waitingForStream)';
  }
}

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

  bool _restarting = false;
  StreamResolution? _pendingResolution;

  DateTime? _lastFrameTime;
  DateTime? _lastHeartbeatAckTime;

  bool get supportedPlatform => Platform.isIOS || Platform.isAndroid;

  SessionController({required this.proxy, required this.settingsStore});

  void initialize() {
    _attachToProxy();
    _updateState(_state.copyWith(connected: proxy.isConnected));
    
  }

  void _attachToProxy() {
    _serverStatusSub?.cancel();
    _serverStatusSub = proxy.serverStatusEvents.listen(_handleServerStatus);
    
  }

  void reattachToProxy() {
    
    _attachToProxy();
  }

  void _updateState(SessionState newState) {
    if (_state != newState) {
      final oldState = _state;
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
    
    _updateState(_state.copyWith(mode: mode));
    proxy.sendClientStatus(
      mode,
      width: resolution?.width,
      height: resolution?.height,
      colorMode: settings.colorMode,
      fps: settings.fps,
    );
  }

  void syncStatus({StreamResolution? resolution}) {
    
    proxy.sendClientStatus(
      _state.mode,
      width: resolution?.width,
      height: resolution?.height,
      colorMode: settings.colorMode,
      fps: settings.fps,
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
        _state.mode == ClientMode.chat) {
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

    if (supportedPlatform) {
      if (decoder == null && onDecoderNeeded != null) {
        await onDecoderNeeded();
      } else if (decoder != null) {
        await decoder?.reset();
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));
    streamWidth = target.width;
    streamHeight = target.height;

    // Sync status with server (which includes resolution and triggers streaming)
    syncStatus(resolution: target);

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

  @override
  void dispose() {
    _serverStatusSub?.cancel();
    _stateController.close();
    super.dispose();
  }
}
