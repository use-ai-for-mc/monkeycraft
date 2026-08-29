import 'package:flutter/material.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';

/// Settings-screen control that shows the current iOS notification Banner Style
/// and offers a shortcut into iOS Settings to change it. iOS-only.
class BannerStyleSettingsTile extends StatefulWidget {
  const BannerStyleSettingsTile({super.key});

  @override
  State<BannerStyleSettingsTile> createState() =>
      _BannerStyleSettingsTileState();
}

class _BannerStyleSettingsTileState extends State<BannerStyleSettingsTile>
    with WidgetsBindingObserver {
  NotificationSettingsInfo? _info;

  @override
  void initState() {
    super.initState();
    if (platformCapabilities.isIOS) {
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
    // Re-read after the user returns from the iOS Settings app.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final info = await notificationService.getSettings();
    if (!mounted) return;
    setState(() => _info = info);
  }

  String _subtitle(NotificationSettingsInfo info) {
    if (info.authStatus == NotificationAuthStatus.denied) {
      return 'Notifications are turned off for MonkeyCraft.';
    }
    if (info.authStatus == NotificationAuthStatus.notDetermined) {
      return 'Notification permission not requested yet.';
    }
    switch (info.alertStyle) {
      case NotificationAlertStyle.banner:
        return 'Temporary — banners disappear after a few seconds.';
      case NotificationAlertStyle.alert:
        return 'Persistent — banners stay until you act on them.';
      case NotificationAlertStyle.none:
        return 'Banners off — alerts only reach Notification Center.';
      case NotificationAlertStyle.unknown:
        return 'Unknown.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!platformCapabilities.isIOS) return const SizedBox.shrink();
    final info = _info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notification Banners'),
          subtitle: Text(info == null ? 'Checking…' : _subtitle(info)),
          trailing: TextButton(
            onPressed: () => notificationService.openSettings(),
            child: const Text('Change'),
          ),
        ),
        ListenableBuilder(
          listenable: appSettings,
          builder: (context, _) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me to use Persistent banners'),
            subtitle: const Text(
              'Prompt on launch when banners are set to Temporary.',
            ),
            value: !appSettings.keepTemporaryBanner,
            onChanged: (v) => appSettings.setKeepTemporaryBanner(!v),
          ),
        ),
      ],
    );
  }
}
