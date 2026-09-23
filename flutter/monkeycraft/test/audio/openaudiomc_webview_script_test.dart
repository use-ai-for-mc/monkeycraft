import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/audio/openaudiomc_webview_script.dart';

void main() {
  test(
    'normal iOS installs compatibility before page scripts without diagnostics',
    () {
      final script = openAudioMcWebViewScript(isIOS: true, diagnostics: false)!;
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.source, contains('__monkeyNativeNoSleep'));
      expect(script.source, isNot(contains('__monkeyMediaDiagnostics')));
      expect(script.source, isNot(contains('__monkeyAudioDiagnostics')));
    },
  );

  test(
    'normal other native platforms do not receive the iOS compatibility patch',
    () {
      expect(
        openAudioMcWebViewScript(isIOS: false, diagnostics: false),
        isNull,
      );
    },
  );

  test(
    'explicit diagnostics preserve compatibility and observe detached media',
    () {
      final script = openAudioMcWebViewScript(isIOS: true, diagnostics: true)!;
      expect(script.source, contains('__monkeyNativeNoSleep'));
      expect(script.source, contains('__monkeyMediaDiagnostics'));
      expect(script.source, contains('__monkeyAudioDiagnostics'));
    },
  );
}
