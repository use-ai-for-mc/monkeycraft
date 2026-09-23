import 'dart:async';

import 'package:monkeycraft_client/audio/audio_web_view.dart';

class FakeAudioWebView implements AudioWebView {
  FakeAudioWebView({this.runGate, this.failLoads = 0});

  final Completer<void>? runGate;
  int failLoads;
  int runCalls = 0;
  int disposeCalls = 0;
  final loads = <String>[];
  Future<dynamic> Function(String source)? onEvaluate;

  @override
  Future<void> run() async {
    runCalls++;
    await runGate?.future;
  }

  @override
  Future<void> loadUrl(String url) async {
    loads.add(url);
    if (failLoads > 0) {
      failLoads--;
      throw StateError('load failed');
    }
  }

  @override
  Future<dynamic> evaluateJavascript(String source) async {
    return await onEvaluate?.call(source);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
