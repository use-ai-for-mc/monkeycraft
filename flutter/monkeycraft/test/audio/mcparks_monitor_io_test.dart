import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/audio_background_session.dart';
import 'package:monkeycraft_client/audio/mcparks_v1_service_io.dart';

import 'fake_audio_web_view.dart';

void main() {
  const mcParksUrl = 'https://mcparks.us/audio?user=test';

  testWidgets(
    'MCParks monitor error is contained and a later period recovers',
    (tester) async {
      AudioBackgroundSession.resetForTest();
      final webView = FakeAudioWebView();
      final packets = <Map<String, dynamic>>[];
      var monitorCalls = 0;
      webView.onEvaluate = (source) {
        if (!source.contains('Connected!')) return Future.value(null);
        monitorCalls++;
        if (monitorCalls == 1) {
          return Future<dynamic>.error(StateError('expected monitor error'));
        }
        return Future.value({
          'status': 'connected',
          'clickedConnect': false,
          'howlerReady': false,
        });
      };
      final service = McParksV1Service(
        webViewFactory: ({initialScript}) => webView,
      );
      service.setInfoPacketHandler(packets.add);

      await service.connect(mcParksUrl);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        packets.any(
          (packet) =>
              packet['data']['connected'] == false &&
              packet['data']['error'] == 'monitor',
        ),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        packets.any((packet) => packet['data']['connected'] == true),
        isTrue,
      );
      await service.dispose();
    },
  );
}
