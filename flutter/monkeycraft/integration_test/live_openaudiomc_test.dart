import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monkeycraft_client/audio/audio_background_session.dart';
import 'package:monkeycraft_client/audio/audio_web_view.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service_io.dart';

const _configUrl = String.fromEnvironment('liveAudioConfigUrl');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;

  testWidgets(
    'connects, refreshes, and releases a live OpenAudioMc session',
    (tester) async {
      final config = await _loadLiveConfig();
      late _ObservingAudioWebView observer;
      final service = OpenAudioMcService(
        webViewFactory: ({initialScript}) {
          observer = _ObservingAudioWebView(
            createAudioWebView(initialScript: initialScript),
          );
          return observer;
        },
      );
      var connectedInfoEvents = 0;
      final infoErrors = <String>{};
      service.setInfoPacketHandler((packet) {
        final data = packet['data'];
        if (packet['title'] == 'openaudiomc' &&
            data is Map &&
            data['connected'] == true) {
          connectedInfoEvents++;
        }
        if (packet['title'] == 'openaudiomc' && data is Map) {
          final error = data['error'];
          if (error is String) infoErrors.add(_infoErrorClass(error));
        }
      });
      addTearDown(service.dispose);

      await tester.pumpWidget(const SizedBox.shrink());
      try {
        await service.connect(config.sessionUrl);
      } catch (_) {
        throw TestFailure('OpenAudioMc connection could not be started');
      }

      final connected = await _waitForConnected(
        tester,
        service,
        observer,
        connectedInfoEvents: () => connectedInfoEvents,
        infoErrors: infoErrors,
      );
      expect(service.isActive, isTrue);
      expect(service.isConnected, isTrue);
      expect(connectedInfoEvents, greaterThanOrEqualTo(1));
      expect(AudioBackgroundSession.activeLeases, 1);
      _printObservation('connected', connected, connectedInfoEvents);

      try {
        await service.softRefresh();
      } catch (_) {
        throw TestFailure('OpenAudioMc refresh failed');
      }
      final refreshed = await _waitForConnected(
        tester,
        service,
        observer,
        connectedInfoEvents: () => connectedInfoEvents,
        infoErrors: infoErrors,
      );
      expect(service.isActive, isTrue);
      expect(service.isConnected, isTrue);
      _printObservation('refreshed', refreshed, connectedInfoEvents);

      await service.disconnect();
      expect(service.isActive, isFalse);
      expect(service.isConnected, isFalse);
      expect(AudioBackgroundSession.activeLeases, 0);
      debugPrint(
        'OpenAudioMc disconnected: active=false connected=false leases=0',
      );
    },
    skip: _configUrl.isEmpty,
  );
}

Future<_MediaObservation> _waitForConnected(
  WidgetTester tester,
  OpenAudioMcService service,
  _ObservingAudioWebView observer, {
  required int Function() connectedInfoEvents,
  required Set<String> infoErrors,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    if (service.isConnected) return observer.observe();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
  _printTimeoutDiagnostic(
    observer.lastSafeObservation,
    connectedInfoEvents(),
    infoErrors,
  );
  throw TestFailure('OpenAudioMc did not report a connected session in time');
}

String _infoErrorClass(String error) {
  return switch (error) {
    'timeout' || 'monitor' || 'max_reconnect' => error,
    _ => 'other',
  };
}

void _printObservation(
  String phase,
  _MediaObservation observation,
  int connectedInfoEvents,
) {
  debugPrint(
    'OpenAudioMc $phase: htmlMedia=${observation.htmlMedia} '
    'playingHtmlMedia=${observation.playingHtmlMedia} '
    'howlerAvailable=${observation.howlerAvailable} '
    'playingHowler=${observation.playingHowler ?? 'unavailable'} '
    'connectedInfoEvents=$connectedInfoEvents',
  );
}

void _printTimeoutDiagnostic(
  _SafePageObservation observation,
  int connectedInfoEvents,
  Set<String> infoErrors,
) {
  final errors = infoErrors.toList()..sort();
  debugPrint(
    'OpenAudioMc timeout diagnostics: '
    'observationAvailable=${observation.available} '
    'readyState=${observation.readyState} '
    'bodyLength=${observation.bodyLength} '
    'rangeInputs=${observation.rangeInputs} '
    'buttons=${observation.buttons} '
    'hasStartAudioSessionButton=${observation.hasStartAudioSessionButton} '
    'hasInvalidText=${observation.hasInvalidText} '
    'hasExpiredText=${observation.hasExpiredText} '
    'hasErrorText=${observation.hasErrorText} '
    'expectedHost=${observation.expectedHost} '
    'hasSessionQuery=${observation.hasSessionQuery} '
    'hasFragment=${observation.hasFragment} '
    'connectedInfoEvents=$connectedInfoEvents '
    'infoErrors=${errors.join(',')}',
  );
}

class _LiveConfig {
  const _LiveConfig(this.sessionUrl);

  final String sessionUrl;
}

Future<_LiveConfig> _loadLiveConfig() async {
  try {
    final configUri = Uri.parse(_configUrl);
    if (configUri.scheme != 'http' ||
        configUri.host != '127.0.0.1' ||
        configUri.path.isEmpty) {
      throw const FormatException();
    }
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        configUri,
      )).close().timeout(const Duration(seconds: 3));
      if (response.statusCode != HttpStatus.ok) throw const FormatException();
      final value = jsonDecode(await utf8.decoder.bind(response).join());
      if (value is! Map || value['sessionUrl'] is! String) {
        throw const FormatException();
      }
      final sessionUrl = value['sessionUrl'] as String;
      if (!OpenAudioMcService.isOpenAudioMcUrl(sessionUrl)) {
        throw const FormatException();
      }
      return _LiveConfig(sessionUrl);
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    throw TestFailure('live audio configuration is unavailable');
  }
}

class _ObservingAudioWebView implements AudioWebView {
  _ObservingAudioWebView(this._delegate);

  final AudioWebView _delegate;
  _SafePageObservation _lastSafeObservation =
      const _SafePageObservation.unavailable();

  _SafePageObservation get lastSafeObservation => _lastSafeObservation;

  @override
  Future<void> run() => _delegate.run();

  @override
  Future<void> loadUrl(String url) => _delegate.loadUrl(url);

  @override
  Future<dynamic> evaluateJavascript(String source) async {
    final result = await _delegate.evaluateJavascript(source);
    await _captureSafeObservation();
    return result;
  }

  @override
  Future<void> dispose() => _delegate.dispose();

  Future<_MediaObservation> observe() async {
    try {
      final observation = await _readSafeObservation();
      _lastSafeObservation = observation;
      final result = await _delegate.evaluateJavascript('''
      (function() {
        const media = Array.from(document.querySelectorAll('audio,video'));
        let playingHowler = 0;
        try {
          const howls = globalThis.Howler && Array.isArray(globalThis.Howler._howls)
            ? globalThis.Howler._howls
            : [];
          playingHowler = howls.filter((howl) => howl && howl.playing && howl.playing()).length;
        } catch (_) {}
        return {
          htmlMedia: media.length,
          playingHtmlMedia: media.filter((element) => !element.paused && !element.ended).length,
          howlerAvailable: !!globalThis.Howler,
          playingHowler: playingHowler
        };
      })();
    ''');
      return _MediaObservation.fromResult(result);
    } catch (_) {
      throw TestFailure('safe media observation is unavailable');
    }
  }

  Future<void> _captureSafeObservation() async {
    try {
      _lastSafeObservation = await _readSafeObservation();
    } catch (_) {
      _lastSafeObservation = const _SafePageObservation.unavailable();
    }
  }

  Future<_SafePageObservation> _readSafeObservation() async {
    final result = await _delegate.evaluateJavascript('''
      (function() {
        const bodyText = document.body ? document.body.innerText.toLowerCase() : '';
        const buttons = Array.from(document.querySelectorAll('button'));
        return {
          readyState: document.readyState,
          bodyLength: document.body ? document.body.innerText.length : 0,
          rangeInputs: document.querySelectorAll('input[type="range"]').length,
          buttons: buttons.length,
          hasStartAudioSessionButton: buttons.some((button) => button.innerText.trim().toLowerCase() === 'start audio session'),
          hasInvalidText: bodyText.includes('invalid'),
          hasExpiredText: bodyText.includes('expired'),
          hasErrorText: bodyText.includes('error'),
          expectedHost: window.location.hostname === 'session.openaudiomc.net',
          hasSessionQuery: new URLSearchParams(window.location.search).has('session'),
          hasFragment: window.location.hash.length > 1
        };
      })();
    ''');
    return _SafePageObservation.fromResult(result);
  }
}

class _SafePageObservation {
  const _SafePageObservation({
    required this.available,
    required this.readyState,
    required this.bodyLength,
    required this.rangeInputs,
    required this.buttons,
    required this.hasStartAudioSessionButton,
    required this.hasInvalidText,
    required this.hasExpiredText,
    required this.hasErrorText,
    required this.expectedHost,
    required this.hasSessionQuery,
    required this.hasFragment,
  });

  const _SafePageObservation.unavailable()
    : available = false,
      readyState = 'unavailable',
      bodyLength = 0,
      rangeInputs = 0,
      buttons = 0,
      hasStartAudioSessionButton = false,
      hasInvalidText = false,
      hasExpiredText = false,
      hasErrorText = false,
      expectedHost = false,
      hasSessionQuery = false,
      hasFragment = false;

  factory _SafePageObservation.fromResult(dynamic result) {
    if (result is! Map) return const _SafePageObservation.unavailable();
    return _SafePageObservation(
      available: true,
      readyState: _readyState(result['readyState']),
      bodyLength: _asCount(result['bodyLength']),
      rangeInputs: _asCount(result['rangeInputs']),
      buttons: _asCount(result['buttons']),
      hasStartAudioSessionButton: result['hasStartAudioSessionButton'] == true,
      hasInvalidText: result['hasInvalidText'] == true,
      hasExpiredText: result['hasExpiredText'] == true,
      hasErrorText: result['hasErrorText'] == true,
      expectedHost: result['expectedHost'] == true,
      hasSessionQuery: result['hasSessionQuery'] == true,
      hasFragment: result['hasFragment'] == true,
    );
  }

  final bool available;
  final String readyState;
  final int bodyLength;
  final int rangeInputs;
  final int buttons;
  final bool hasStartAudioSessionButton;
  final bool hasInvalidText;
  final bool hasExpiredText;
  final bool hasErrorText;
  final bool expectedHost;
  final bool hasSessionQuery;
  final bool hasFragment;
}

class _MediaObservation {
  const _MediaObservation({
    required this.htmlMedia,
    required this.playingHtmlMedia,
    required this.howlerAvailable,
    required this.playingHowler,
  });

  factory _MediaObservation.fromResult(dynamic result) {
    if (result is! Map) {
      throw TestFailure('safe media observation is unavailable');
    }
    return _MediaObservation(
      htmlMedia: _asCount(result['htmlMedia']),
      playingHtmlMedia: _asCount(result['playingHtmlMedia']),
      howlerAvailable: result['howlerAvailable'] == true,
      playingHowler: result['howlerAvailable'] == true
          ? _asCount(result['playingHowler'])
          : null,
    );
  }

  final int htmlMedia;
  final int playingHtmlMedia;
  final bool howlerAvailable;
  final int? playingHowler;
}

int _asCount(dynamic value) => value is num && value >= 0 ? value.toInt() : 0;

String _readyState(dynamic value) {
  return switch (value) {
    'loading' || 'interactive' || 'complete' => value as String,
    _ => 'unknown',
  };
}
