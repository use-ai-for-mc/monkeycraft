import 'package:flutter/material.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/shared/app_settings.dart';

enum _NudgeChoice { openSettings, later, keepTemporary }

/// Detects when iOS notification banners are set to "Temporary" (auto-dismiss)
/// and nudges the user toward "Persistent". The prompt appears at most once per
/// fresh app launch, and never once the user picks "Keep Temporary".
class BannerStyleNudge {
  BannerStyleNudge({required this.service, required this.settings});

  final TimedNotificationService service;
  final AppSettings settings;

  // In-memory only: resets on every fresh process launch, so "Later" re-surfaces
  // the next time the app is launched freshly.
  bool _promptedThisSession = false;

  Future<NotificationSettingsInfo> currentSettings() => service.getSettings();

  Future<void> openSystemSettings() => service.openSettings();

  /// Shows the nudge once per fresh launch when banners are enabled but set to
  /// Temporary, unless the user previously chose "Keep Temporary".
  Future<void> maybePromptAtLaunch(BuildContext context) async {
    if (_promptedThisSession) return;
    if (settings.keepTemporaryBanner) return;

    final info = await service.getSettings();
    // Only worth nudging when banners are on but auto-dismiss (Temporary).
    if (info.authStatus != NotificationAuthStatus.authorized) return;
    if (info.alertStyle != NotificationAlertStyle.banner) return;

    _promptedThisSession = true;
    if (!context.mounted) return;
    await _prompt(context);
  }

  Future<void> _prompt(BuildContext context) async {
    final choice = await showDialog<_NudgeChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep alerts on screen?'),
        content: const Text(
          'MonkeyCraft notifications currently show as a Temporary banner that '
          'disappears after a few seconds. Set Banner Style to Persistent in '
          'iOS Settings to keep them pinned until you act on them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_NudgeChoice.keepTemporary),
            child: const Text('Keep Temporary'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_NudgeChoice.later),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_NudgeChoice.openSettings),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (choice == _NudgeChoice.keepTemporary) {
      await settings.setKeepTemporaryBanner(true);
    } else if (choice == _NudgeChoice.openSettings) {
      await service.openSettings();
    }
    // _NudgeChoice.later or dismissed (null): do nothing, re-check next launch.
  }
}

/// Drop-in wrapper that fires [BannerStyleNudge.maybePromptAtLaunch] once after
/// the first frame, using a context beneath the app's [Navigator].
class BannerStyleNudgeGate extends StatefulWidget {
  const BannerStyleNudgeGate({
    super.key,
    required this.nudge,
    required this.child,
  });

  final BannerStyleNudge nudge;
  final Widget child;

  @override
  State<BannerStyleNudgeGate> createState() => _BannerStyleNudgeGateState();
}

class _BannerStyleNudgeGateState extends State<BannerStyleNudgeGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nudge.maybePromptAtLaunch(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
