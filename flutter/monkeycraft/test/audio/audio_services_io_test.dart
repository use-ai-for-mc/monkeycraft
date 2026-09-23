import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'fake_audio_web_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/audio_background_session.dart';
import 'package:monkeycraft_client/audio/mcparks_v1_service_io.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service_io.dart';

void main() {
  setUp(AudioBackgroundSession.resetForTest);
  const openUrl = 'https://session.openaudiomc.net/#test';
  const mcParksUrl = 'https://mcparks.us/audio?user=test';

  test(
    'OpenAudioMc shares delayed initialization for duplicate connects',
    () async {
      final gate = Completer<void>();
      final webView = FakeAudioWebView(runGate: gate);
      var created = 0;
      final service = OpenAudioMcService(
        webViewFactory: ({UserScript? initialScript}) {
          created++;
          return webView;
        },
      );

      final first = service.connect(openUrl);
      final second = service.connect(openUrl);

      await Future<void>.delayed(Duration.zero);
      expect(created, 1);
      expect(webView.loads, isEmpty);

      gate.complete();
      await Future.wait([first, second]);

      expect(webView.runCalls, 1);
      expect(webView.loads, [openUrl]);
      await service.dispose();
    },
  );

  test(
    'MCParks shares delayed initialization for duplicate connects',
    () async {
      final gate = Completer<void>();
      final webView = FakeAudioWebView(runGate: gate);
      var created = 0;
      final service = McParksV1Service(
        webViewFactory: ({UserScript? initialScript}) {
          created++;
          return webView;
        },
      );

      final first = service.connect(mcParksUrl);
      final second = service.connect(mcParksUrl);

      await Future<void>.delayed(Duration.zero);
      expect(created, 1);
      expect(webView.loads, isEmpty);

      gate.complete();
      await Future.wait([first, second]);

      expect(webView.runCalls, 1);
      expect(webView.loads, [mcParksUrl]);
      await service.dispose();
    },
  );

  test(
    'disconnect prevents an already-started refresh from reloading',
    () async {
      final webView = FakeAudioWebView();
      final refreshGate = Completer<dynamic>();
      webView.onEvaluate = (source) {
        if (source.contains('rangeInput')) return refreshGate.future;
        return Future.value(null);
      };
      final service = OpenAudioMcService(
        webViewFactory: ({initialScript}) => webView,
      );

      await service.connect(openUrl);
      final refresh = service.softRefresh();
      await Future<void>.delayed(Duration.zero);
      final disconnect = service.disconnect();
      refreshGate.complete({'hasRangeInput': false});
      await Future.wait([refresh, disconnect]);

      expect(webView.loads, [openUrl, 'about:blank']);
      expect(service.isActive, isFalse);
    },
  );

  test('a failed load permits retrying the same OpenAudioMc URL', () async {
    final webView = FakeAudioWebView(failLoads: 1);
    final service = OpenAudioMcService(
      webViewFactory: ({initialScript}) => webView,
    );

    await expectLater(service.connect(openUrl), throwsStateError);
    expect(service.isActive, isFalse);

    await service.connect(openUrl);

    expect(webView.loads, [openUrl, openUrl]);
    expect(service.isActive, isTrue);
    await service.dispose();
  });

  testWidgets('periodic OpenAudioMc monitor does not revive after disconnect', (
    tester,
  ) async {
    AudioBackgroundSession.resetForTest();
    final webView = FakeAudioWebView();
    final monitorGate = Completer<dynamic>();
    final packets = <Map<String, dynamic>>[];
    var monitorStarted = false;
    webView.onEvaluate = (source) {
      if (source.contains('currentUrl')) {
        monitorStarted = true;
        return monitorGate.future;
      }
      return Future.value(null);
    };
    final service = OpenAudioMcService(
      webViewFactory: ({initialScript}) => webView,
    );
    service.setInfoPacketHandler(packets.add);

    await service.connect(openUrl);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(monitorStarted, isTrue);

    final disconnect = service.disconnect();
    monitorGate.complete({
      'hasRangeInput': true,
      'hasStartButton': false,
      'hasSession': true,
      'currentUrl': openUrl,
    });
    await tester.pump();
    await disconnect;

    expect(webView.loads, [openUrl, 'about:blank']);
    expect(
      packets.where((packet) => packet['data']['connected'] == true),
      isEmpty,
    );
    await service.dispose();
  });
  test(
    'OpenAudioMc reports ownership before navigation and releases after teardown',
    () async {
      final webView = FakeAudioWebView();
      final service = OpenAudioMcService(
        webViewFactory: ({initialScript}) => webView,
      );
      final events = <Map<String, dynamic>>[];
      service.setInfoPacketHandler((packet) {
        events.add({
          'active': packet['data']['active'],
          'loads': [...webView.loads],
          'disposed': webView.disposeCalls,
        });
      });
      await service.connect(openUrl);
      expect(events.first['active'], false);
      expect(events.firstWhere((e) => e['active'] == true)['loads'], isEmpty);
      service.reportState();
      expect(events.last['active'], true);
      await service.disconnect();
      expect(events.last['active'], false);
      expect(events.last['loads'], [openUrl, 'about:blank']);
      await service.connect(openUrl);
      await service.dispose();
      expect(events.last['active'], false);
      expect(events.last['disposed'], 1);
    },
  );

  test(
    'OpenAudioMc failed navigation releases ownership after disposing the page',
    () async {
      final webView = FakeAudioWebView(failLoads: 1);
      final service = OpenAudioMcService(
        webViewFactory: ({initialScript}) => webView,
      );
      final events = <Map<String, dynamic>>[];
      service.setInfoPacketHandler((packet) {
        events.add({
          'active': packet['data']['active'],
          'disposed': webView.disposeCalls,
        });
      });
      await expectLater(service.connect(openUrl), throwsStateError);
      expect(events.last, {'active': false, 'disposed': 1});
      expect(service.isActive, false);
      await service.dispose();
    },
  );
  test(
    'failed OpenAudioMc refresh releases phone ownership and permits a new page',
    () async {
      final webView = FakeAudioWebView();
      final service = OpenAudioMcService(
        webViewFactory: ({initialScript}) => webView,
      );
      final states = <bool>[];
      service.setInfoPacketHandler(
        (packet) => states.add(packet['data']['active'] as bool),
      );
      await service.connect(openUrl);
      webView.failLoads = 1;
      await expectLater(service.reconnect(), throwsStateError);
      expect(states.last, false);
      expect(webView.disposeCalls, 1);
      expect(service.isActive, false);
      await service.reconnect();
      expect(webView.runCalls, 2);
      expect(service.isActive, true);
      await service.dispose();
    },
  );
}
