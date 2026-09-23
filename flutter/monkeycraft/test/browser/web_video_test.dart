@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/video/web_h264_decoder.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real H264 decodes before and after reset on the same canvas view', () async {
    const fixtureUrl = String.fromEnvironment('VIDEO_FIXTURE_URL');
    expect(fixtureUrl, isNotEmpty);
    final response = await web.window.fetch(fixtureUrl.toJS).toDart;
    final content = (await response.text().toDart).toDart;
    final frames = (jsonDecode(content) as List)
        .cast<String>()
        .map(base64Decode)
        .toList();
    final decoder = WebH264Decoder();
    await decoder.initialize();
    expect(decoder.isReady, isTrue, reason: decoder.lastError);
    for (final frame in frames.take(40)) {
      decoder.pushAccessUnit(frame);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final before = decoder.stats.decodedFrames;
    expect(before, greaterThan(15));
    expect(decoder.stats.displayWidth, 360);
    expect(decoder.stats.displayHeight, 640);
    final viewType = decoder.platformViewType;
    await decoder.reset();
    for (final frame in frames) {
      decoder.pushAccessUnit(frame);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(decoder.stats.decodedFrames, greaterThan(before + 15));
    expect(decoder.stats.decoderErrors, 0);
    expect(decoder.platformViewType, viewType);
    await decoder.dispose();
    expect(decoder.isReady, isFalse);
  });

  test('disposing during async support detection cannot revive decoder', () async {
    final decoder = WebH264Decoder();
    final initialization = decoder.initialize();
    await decoder.dispose();
    await initialization;
    decoder.pushAccessUnit(Uint8List.fromList([0, 0, 0, 1, 0x65]));
    expect(decoder.isReady, isFalse);
    expect(decoder.stats.decodedFrames, 0);
  });
}
