import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';

class TimedReminderCountdown extends StatefulWidget {
  const TimedReminderCountdown({
    super.key,
    required this.notification,
    this.now = DateTime.now,
  });

  final TimedNotification? notification;
  final DateTime Function() now;

  @override
  State<TimedReminderCountdown> createState() => _TimedReminderCountdownState();
}

class _TimedReminderCountdownState extends State<TimedReminderCountdown> {
  Timer? _timer;

  int get _secondsRemaining {
    final deadline = widget.notification?.fireAtEpochMs;
    if (deadline == null) return 0;
    final milliseconds = deadline - widget.now().millisecondsSinceEpoch;
    return milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
  }

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(TimedReminderCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notification?.fireAtEpochMs !=
            widget.notification?.fireAtEpochMs ||
        oldWidget.now != widget.now) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_secondsRemaining == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) timer.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _secondsRemaining;
    if (seconds == 0) return const SizedBox.shrink();
    final countdown = widget.notification?.countDownText?.trim();
    final title = widget.notification?.title?.trim();
    final label = countdown != null && countdown.isNotEmpty
        ? countdown
        : title != null && title.isNotEmpty
        ? title
        : 'Reminder';
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    final time = seconds >= 3600
        ? '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:$remainingSeconds'
        : '$minutes:$remainingSeconds';

    return IgnorePointer(
      child: Semantics(
        container: true,
        label: '$label, $time remaining',
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
