import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:monkeycraft_client/audio/audio_context_diagnostics.dart';
import 'package:monkeycraft_client/audio/audio_media_diagnostics.dart';

UserScript? openAudioMcWebViewScript({
  required bool isIOS,
  required bool diagnostics,
}) {
  final sources = [
    if (isIOS) openAudioMcIOSCompatibilitySource,
    if (diagnostics) audioContextDiagnosticSource,
    if (diagnostics) audioMediaDiagnosticSource,
  ];
  if (sources.isEmpty) return null;
  return UserScript(
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    source: sources.join('\n'),
  );
}

const openAudioMcIOSCompatibilitySource = r'''
(() => {
  if (location.hostname !== 'session.openaudiomc.net' || window.__monkeyNativeNoSleep) return;
  const original = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = new Proxy(original, {
    apply(target, media, args) {
      if (media?.tagName === 'VIDEO' && media.getAttribute('title') === 'No Sleep') {
        media.muted = true;
      }
      return Reflect.apply(target, media, args);
    }
  });
  window.__monkeyNativeNoSleep = true;
})();
''';
