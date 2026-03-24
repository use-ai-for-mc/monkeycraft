import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/session_state.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';

void main() {
  group('SessionState', () {
    test('initial state has correct defaults', () {
      final state = SessionState.initial();
      expect(state.mode, ClientMode.streaming);
      expect(state.videoState, VideoState.active);
      expect(state.videoStateMessage, '');
      expect(state.connected, false);
      expect(state.foreground, true);
      expect(state.waitingForStream, false);
      expect(state.resolutionMismatch, false);
      expect(state.authFailed, false);
      expect(state.reconnectRetryCount, 0);
      expect(state.shouldReturnToLogin, false);
      expect(state.isReconnecting, false);
    });

    test('shouldShowVideo requires all conditions', () {
      final base = SessionState.initial().copyWith(connected: true);
      expect(base.shouldShowVideo, isTrue);

      expect(base.copyWith(mode: ClientMode.chat).shouldShowVideo, isFalse);
      expect(
        base.copyWith(videoState: VideoState.hibernating).shouldShowVideo,
        isFalse,
      );
      expect(base.copyWith(connected: false).shouldShowVideo, isFalse);
      expect(base.copyWith(foreground: false).shouldShowVideo, isFalse);
      expect(
        base.copyWith(resolutionMismatch: true).shouldShowVideo,
        isFalse,
      );
    });

    test('shouldShowHibernation checks mode and videoState', () {
      final state = SessionState.initial().copyWith(
        videoState: VideoState.hibernating,
      );
      expect(state.shouldShowHibernation, isTrue);

      expect(
        state.copyWith(mode: ClientMode.chat).shouldShowHibernation,
        isFalse,
      );
      expect(
        state.copyWith(foreground: false).shouldShowHibernation,
        isFalse,
      );
    });

    test('shouldShowWaiting requires connected and waiting', () {
      final state = SessionState.initial().copyWith(
        connected: true,
        waitingForStream: true,
      );
      expect(state.shouldShowWaiting, isTrue);

      expect(
        state.copyWith(waitingForStream: false).shouldShowWaiting,
        isFalse,
      );
      expect(state.copyWith(connected: false).shouldShowWaiting, isFalse);
    });

    test('isInChat returns true only in chat mode', () {
      final streaming = SessionState.initial();
      expect(streaming.isInChat, isFalse);

      final chat = streaming.copyWith(mode: ClientMode.chat);
      expect(chat.isInChat, isTrue);
    });

    test('hasTimedNotification checks fireAtEpochMs', () {
      final state = SessionState.initial();
      expect(state.hasTimedNotification, isFalse);

      final withNotification = state.copyWith(
        timedFireAtEpochMs: 1234567890,
      );
      expect(withNotification.hasTimedNotification, isTrue);
    });

    test('copyWith clearTimedNotification resets all timed fields', () {
      final state = SessionState.initial().copyWith(
        timedFireAtEpochMs: 1234567890,
        timedTitle: 'Title',
        timedBody: 'Body',
        timedSound: false,
        timedCountDownText: '5:00',
      );

      final cleared = state.copyWith(clearTimedNotification: true);
      expect(cleared.timedFireAtEpochMs, isNull);
      expect(cleared.timedTitle, isNull);
      expect(cleared.timedBody, isNull);
      expect(cleared.timedSound, isTrue);
      expect(cleared.timedCountDownText, isNull);
    });

    test('copyWith clearResolutionMismatch resets mismatch fields', () {
      final state = SessionState.initial().copyWith(
        resolutionMismatch: true,
        resolutionMismatchMessage: 'mismatch',
      );

      final cleared = state.copyWith(clearResolutionMismatch: true);
      expect(cleared.resolutionMismatch, isFalse);
      expect(cleared.resolutionMismatchMessage, '');
    });

    test('copyWith clearReconnectionState resets auth and retry', () {
      final state = SessionState.initial().copyWith(
        authFailed: true,
        reconnectRetryCount: 3,
        shouldReturnToLogin: true,
      );

      final cleared = state.copyWith(clearReconnectionState: true);
      expect(cleared.authFailed, isFalse);
      expect(cleared.reconnectRetryCount, 0);
      expect(cleared.shouldReturnToLogin, isFalse);
      expect(cleared.isReconnecting, isFalse);
    });

    test('copyWith isReconnecting sets and clears', () {
      final state = SessionState.initial().copyWith(isReconnecting: true);
      expect(state.isReconnecting, isTrue);

      final cleared = state.copyWith(isReconnecting: false);
      expect(cleared.isReconnecting, isFalse);
    });

    test('copyWith clearVideoStateMessage resets message', () {
      final state = SessionState.initial().copyWith(
        videoStateMessage: 'hibernating',
      );

      final cleared = state.copyWith(clearVideoStateMessage: true);
      expect(cleared.videoStateMessage, '');
    });

    test('timedNotification getter returns correct object', () {
      final state = SessionState.initial().copyWith(
        timedFireAtEpochMs: 1000,
        timedTitle: 'Test',
        timedBody: 'Body',
        timedSound: true,
        timedCountDownText: '0:01',
      );

      final notification = state.timedNotification;
      expect(notification, isNotNull);
      expect(notification!.fireAtEpochMs, 1000);
      expect(notification.title, 'Test');
      expect(notification.body, 'Body');
    });

    test('timedNotification getter returns null when no notification', () {
      final state = SessionState.initial();
      expect(state.timedNotification, isNull);
    });
  });
}
