import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() listenPageHidden(void Function(bool hidden) onHidden) {
  void handle(web.Event _) {
    onHidden(web.document.hidden);
  }

  final listener = handle.toJS;
  web.document.addEventListener('visibilitychange', listener);
  return () {
    web.document.removeEventListener('visibilitychange', listener);
  };
}
