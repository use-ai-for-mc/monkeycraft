import 'package:flutter/material.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

class ExactAlarmSettingsTile extends StatefulWidget {
  final TimedNotificationService? service;
  final Future<void> Function()? onGranted;
  final bool? isAndroid;

  const ExactAlarmSettingsTile({
    super.key,
    this.service,
    this.onGranted,
    this.isAndroid,
  });

  @override
  State<ExactAlarmSettingsTile> createState() => _ExactAlarmSettingsTileState();
}

class _ExactAlarmSettingsTileState extends State<ExactAlarmSettingsTile>
    with WidgetsBindingObserver {
  ExactAlarmAccess? _access;
  String? _error;
  int _refreshGeneration = 0;
  bool _restorePending = false;

  TimedNotificationService get _service =>
      widget.service ?? notificationService;
  bool get _isAndroid => widget.isAndroid ?? platformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final access = await _service.getExactAlarmAccess();
      if (!mounted || generation != _refreshGeneration) return;
      final wasDenied = _access?.supported == true && _access?.granted == false;
      setState(() {
        _access = access;
        _error = null;
      });
      if (wasDenied && access.supported && access.granted) {
        _restorePending = true;
      }
      if (_restorePending && access.supported && access.granted) {
        try {
          await widget.onGranted?.call();
          if (!mounted || generation != _refreshGeneration) return;
          _restorePending = false;
        } catch (_) {
          if (mounted && generation == _refreshGeneration) {
            setState(() => _error = 'Unable to restore this reminder.');
          }
        }
      }
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _error = 'Unable to check exact alarm access.');
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      final opened = await _service.openExactAlarmSettings();
      if (!opened && mounted) {
        setState(() => _error = 'Unable to open exact alarm settings.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to open exact alarm settings.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) return const SizedBox.shrink();
    final access = _access;
    if (access != null && !access.supported) return const SizedBox.shrink();
    final granted = access?.granted == true;
    final subtitle =
        _error ??
        (access == null
            ? 'Checking…'
            : granted
            ? 'Exact ride reminders are enabled.'
            : 'Ride reminders can be delayed unless exact alarms are allowed.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Exact Ride Reminders'),
          subtitle: Text(subtitle),
          trailing: granted
              ? null
              : TextButton(
                  onPressed: access == null ? null : _openSettings,
                  child: const Text('Allow'),
                ),
        ),
      ],
    );
  }
}
