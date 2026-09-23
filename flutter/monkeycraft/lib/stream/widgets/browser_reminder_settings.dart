import 'package:flutter/material.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';

class BrowserReminderSettings extends StatefulWidget {
  const BrowserReminderSettings({super.key});

  @override
  State<BrowserReminderSettings> createState() =>
      _BrowserReminderSettingsState();
}

class _BrowserReminderSettingsState extends State<BrowserReminderSettings> {
  final _service = TimedNotificationService();
  String? _status;

  Future<void> _enable() async {
    try {
      final granted = await _service.requestBrowserPermission();
      if (!mounted) return;
      setState(() {
        _status = granted
            ? 'System notifications enabled.'
            : 'Page reminders remain available. System notifications were not enabled.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'System notifications are unavailable in this browser.',
        );
      }
    }
  }

  Future<void> _testSound() async {
    try {
      await _service.playBrowserTestSound();
      if (mounted) setState(() => _status = 'Test sound played.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Sound could not start. Tap Test sound to try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        SwitchListTile(
          title: const Text('Reminder sounds'),
          value: _service.browserSoundEnabled,
          onChanged: (enabled) async {
            try {
              await _service.setBrowserSoundEnabled(enabled);
              if (mounted) setState(() {});
            } catch (_) {
              if (mounted) {
                setState(
                  () => _status =
                      'Sound could not start. Tap Test sound to try again.',
                );
              }
            }
          },
        ),
        const ListTile(
          title: Text('Browser reminders'),
          subtitle: Text(
            'Keep this page open. Browsers may pause reminders while a phone is locked.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _enable,
                child: const Text('Enable reminders'),
              ),
              OutlinedButton(
                onPressed: _testSound,
                child: const Text('Test sound'),
              ),
            ],
          ),
        ),
        if (_status != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_status!)),
      ],
    );
  }
}
