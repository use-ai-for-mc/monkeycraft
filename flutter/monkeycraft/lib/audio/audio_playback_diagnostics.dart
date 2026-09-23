import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:monkeycraft_client/audio/audio_web_view.dart';

class AudioPlaybackDiagnostics {
  static const enabled = bool.fromEnvironment('MONKEYCRAFT_AUDIO_DIAGNOSTICS');
  static const _channel = MethodChannel('monkeycraft/audio_background');

  static Future<void> capture(
    String event,
    AudioWebView? webView, {
    required bool active,
    required bool connected,
  }) async {
    if (!enabled || !Platform.isIOS) return;
    final data = <String, dynamic>{
      'event': event,
      'active': active,
      'connected': connected,
    };
    try {
      final media = await webView
          ?.evaluateJavascript(r'''
        (() => ({
          hidden: document.hidden,
          range: !!document.querySelector('input[type="range"]'),
          contexts: window.__monkeyAudioDiagnostics
            ? window.__monkeyAudioDiagnostics.snapshot() : null,
          trackedMedia: window.__monkeyMediaDiagnostics?.snapshot(),
          media: Array.from(document.querySelectorAll('audio,video')).slice(0, 8).map(e => ({
            paused: e.paused, ended: e.ended, muted: e.muted,
            volume: e.volume, time: e.currentTime,
            ready: e.readyState, network: e.networkState,
            hasSource: !!e.currentSrc, hasStream: !!e.srcObject,
            error: e.error ? e.error.code : null,
            tracks: e.srcObject && e.srcObject.getAudioTracks
              ? e.srcObject.getAudioTracks().slice(0, 4).map(t => ({
                  enabled: t.enabled, muted: t.muted,
                  live: t.readyState === 'live'
                })) : []
          }))
        }))()
      ''')
          .timeout(const Duration(seconds: 1));
      data['page'] = media;
    } catch (_) {
      data['pageUnavailable'] = true;
    }
    try {
      final resume = await _channel.invokeMethod<bool>('diagnostic', data);
      if (resume == true && webView != null) {
        await webView.evaluateJavascript(
          'window.__monkeyAudioDiagnostics?.resumeOnce()',
        );
      }
    } catch (_) {}
  }
}
