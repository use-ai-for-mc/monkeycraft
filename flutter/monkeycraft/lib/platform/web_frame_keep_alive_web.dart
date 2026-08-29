import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class WebFrameKeepAlive extends StatefulWidget {
  final Widget child;

  const WebFrameKeepAlive({super.key, required this.child});

  @override
  State<WebFrameKeepAlive> createState() => _WebFrameKeepAliveState();
}

class _WebFrameKeepAliveState extends State<WebFrameKeepAlive> {
  Timer? _pump;
  bool _blurred = false;
  late final JSFunction _blurListener;
  late final JSFunction _focusListener;
  late final JSFunction _visibilityListener;

  @override
  void initState() {
    super.initState();
    _blurListener = ((web.Event _) {
      _blurred = true;
      _syncPump();
    }).toJS;
    _focusListener = ((web.Event _) {
      _blurred = false;
      _syncPump();
    }).toJS;
    _visibilityListener = ((web.Event _) {
      _syncPump();
    }).toJS;
    web.window.addEventListener('blur', _blurListener);
    web.window.addEventListener('focus', _focusListener);
    web.document.addEventListener('visibilitychange', _visibilityListener);
  }

  @override
  void dispose() {
    _stopPump();
    web.window.removeEventListener('blur', _blurListener);
    web.window.removeEventListener('focus', _focusListener);
    web.document.removeEventListener(
      'visibilitychange',
      _visibilityListener,
    );
    super.dispose();
  }

  void _syncPump() {
    final shouldPump = _blurred && !web.document.hidden;
    if (shouldPump) {
      _pump ??= Timer.periodic(const Duration(seconds: 1), (_) {
        SchedulerBinding.instance.scheduleWarmUpFrame();
      });
    } else {
      _stopPump();
    }
  }

  void _stopPump() {
    _pump?.cancel();
    _pump = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
