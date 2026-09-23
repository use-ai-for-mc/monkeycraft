import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

abstract interface class AudioWebView {
  Future<void> run();
  Future<void> loadUrl(String url);
  Future<dynamic> evaluateJavascript(String source);
  Future<void> dispose();
}

typedef AudioWebViewFactory =
    AudioWebView Function({UserScript? initialScript});

AudioWebView createAudioWebView({UserScript? initialScript}) {
  if (const bool.fromEnvironment('MONKEYCRAFT_AUDIO_DIAGNOSTICS')) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  }
  return _InAppAudioWebView(initialScript: initialScript);
}

class _InAppAudioWebView implements AudioWebView {
  _InAppAudioWebView({UserScript? initialScript})
    : _webView = HeadlessInAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
          ignoresViewportScaleLimits: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        initialUserScripts: initialScript == null
            ? null
            : UnmodifiableListView([initialScript]),
      );

  final HeadlessInAppWebView _webView;

  @override
  Future<void> run() => _webView.run();

  @override
  Future<void> loadUrl(String url) async {
    await _webView.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  @override
  Future<dynamic> evaluateJavascript(String source) async {
    return await _webView.webViewController?.evaluateJavascript(source: source);
  }

  @override
  Future<void> dispose() => _webView.dispose();
}
