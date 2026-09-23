import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service.dart';
import 'package:monkeycraft_client/chat/chat_models.dart';
import 'package:monkeycraft_client/chat/chat_rich_text.dart';

void main() {
  testWidgets('OpenAudioMc fragment link stays in the in-app audio route', (
    tester,
  ) async {
    const url = 'https://session.openaudiomc.net#opaque';
    final service = _RecordingOpenAudioMcService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatRichText(
            openAudioMc: service,
            segments: const [
              ChatSegment(
                text: url,
                clickAction: ClickAction(action: 'open_url', value: url),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text(url));
    await tester.pump();

    expect(service.urls, [url]);
  });
}

class _RecordingOpenAudioMcService extends OpenAudioMcService {
  final urls = <String>[];

  @override
  Future<void> connect(String sessionUrl) async {
    urls.add(sessionUrl);
  }
}
