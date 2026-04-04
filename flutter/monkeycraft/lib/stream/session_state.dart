import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';

class SessionState {
  final ClientMode mode;
  final VideoState videoState;
  final String videoStateMessage;
  final bool connected;
  final bool foreground;
  final bool waitingForStream;
  final bool resolutionMismatch;
  final String resolutionMismatchMessage;

  final int? timedFireAtEpochMs;
  final String? timedTitle;
  final String? timedBody;
  final bool timedSound;
  final String? timedCountDownText;

  final bool authFailed;
  final int reconnectRetryCount;
  final bool shouldReturnToLogin;
  final bool isReconnecting;

  const SessionState({
    required this.mode,
    required this.videoState,
    required this.videoStateMessage,
    required this.connected,
    required this.foreground,
    required this.waitingForStream,
    this.resolutionMismatch = false,
    this.resolutionMismatchMessage = '',
    this.timedFireAtEpochMs,
    this.timedTitle,
    this.timedBody,
    this.timedSound = true,
    this.timedCountDownText,
    this.authFailed = false,
    this.reconnectRetryCount = 0,
    this.shouldReturnToLogin = false,
    this.isReconnecting = false,
  });

  factory SessionState.initial() => const SessionState(
    mode: ClientMode.streaming,
    videoState: VideoState.active,
    videoStateMessage: '',
    connected: false,
    foreground: true,
    waitingForStream: false,
    resolutionMismatch: false,
    resolutionMismatchMessage: '',
    authFailed: false,
    reconnectRetryCount: 0,
    shouldReturnToLogin: false,
    isReconnecting: false,
  );

  bool get shouldShowVideo =>
      mode == ClientMode.streaming &&
      videoState == VideoState.active &&
      connected &&
      foreground &&
      !resolutionMismatch;

  bool get shouldShowHibernation =>
      mode == ClientMode.streaming &&
      videoState == VideoState.hibernating &&
      foreground;

  bool get shouldShowWaiting =>
      waitingForStream &&
      mode == ClientMode.streaming &&
      videoState == VideoState.active &&
      connected &&
      foreground;

  bool get shouldShowResolutionMismatch =>
      resolutionMismatch &&
      mode == ClientMode.streaming &&
      videoState == VideoState.active &&
      connected &&
      foreground;

  bool get isInChat => mode == ClientMode.chat;
  bool get isInMap => mode == ClientMode.map;

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
    bool? resolutionMismatch,
    String? resolutionMismatchMessage,
    int? timedFireAtEpochMs,
    String? timedTitle,
    String? timedBody,
    bool? timedSound,
    String? timedCountDownText,
    bool? authFailed,
    int? reconnectRetryCount,
    bool? shouldReturnToLogin,
    bool? isReconnecting,
    bool clearVideoStateMessage = false,
    bool clearTimedNotification = false,
    bool clearResolutionMismatch = false,
    bool clearReconnectionState = false,
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
      resolutionMismatch: clearResolutionMismatch
          ? false
          : (resolutionMismatch ?? this.resolutionMismatch),
      resolutionMismatchMessage: clearResolutionMismatch
          ? ''
          : (resolutionMismatchMessage ?? this.resolutionMismatchMessage),
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
      authFailed: clearReconnectionState
          ? false
          : (authFailed ?? this.authFailed),
      reconnectRetryCount: clearReconnectionState
          ? 0
          : (reconnectRetryCount ?? this.reconnectRetryCount),
      shouldReturnToLogin: clearReconnectionState
          ? false
          : (shouldReturnToLogin ?? this.shouldReturnToLogin),
      isReconnecting: clearReconnectionState
          ? false
          : (isReconnecting ?? this.isReconnecting),
    );
  }

  @override
  String toString() {
    return 'SessionState(mode=$mode, videoState=$videoState, connected=$connected, waiting=$waitingForStream, resolutionMismatch=$resolutionMismatch)';
  }
}
