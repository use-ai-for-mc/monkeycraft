import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monkeycraft_client/notifications/browser_notification_event.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

class BrowserReminderOverlay extends StatefulWidget {
  const BrowserReminderOverlay({
    super.key,
    required this.child,
    this.eventStream,
    this.now,
  });

  final Widget child;
  final Stream<BrowserNotificationEvent>? eventStream;
  final DateTime Function()? now;

  @override
  State<BrowserReminderOverlay> createState() => _BrowserReminderOverlayState();
}

class _BrowserReminderOverlayState extends State<BrowserReminderOverlay> {
  static const _displayDuration = Duration(seconds: 12);

  StreamSubscription<BrowserNotificationEvent>? _subscription;
  BrowserNotificationEvent? _reminder;
  BrowserNotificationEvent? _pendingImmediate;
  DateTime? _pendingImmediateAt;
  Timer? _dismissTimer;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final events = widget.eventStream;
    if (events != null || platformCapabilities.isWeb) {
      _subscription = (events ?? TimedNotificationService().browserEvents)
          .listen(_handleEvent);
    }
  }

  void _handleEvent(BrowserNotificationEvent event) {
    if (!mounted) return;
    if (event.kind == BrowserNotificationKind.timed) {
      _pendingImmediate = null;
      _pendingImmediateAt = null;
      _show(event);
      return;
    }
    if (_reminder?.kind == BrowserNotificationKind.timed) {
      _pendingImmediate = event;
      _pendingImmediateAt = _now;
      return;
    }
    _show(event);
  }

  void _show(BrowserNotificationEvent event) {
    _dismissTimer?.cancel();
    setState(() => _reminder = event);
    _dismissTimer = Timer(_displayDuration, _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final timed = _reminder?.kind == BrowserNotificationKind.timed;
    final pending = _pendingImmediate;
    final pendingAt = _pendingImmediateAt;
    _pendingImmediate = null;
    _pendingImmediateAt = null;
    if (timed &&
        pending != null &&
        pendingAt != null &&
        _now.difference(pendingAt) < _displayDuration) {
      _show(pending);
      return;
    }
    if (mounted) setState(() => _reminder = null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismissTimer?.cancel();
    _pendingImmediate = null;
    _pendingImmediateAt = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminder;
    if (reminder == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 72,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  elevation: 6,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                reminder.title,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (reminder.body.isNotEmpty) Text(reminder.body),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss reminder',
                          onPressed: _dismiss,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
