class TimedNotification {
  final int? fireAtEpochMs;
  final String? title;
  final String? body;
  final bool sound;
  final String? countDownText;

  const TimedNotification({
    required this.fireAtEpochMs,
    required this.title,
    required this.body,
    required this.sound,
    this.countDownText,
  });
}

class ImmediateNotification {
  final String? body;

  const ImmediateNotification({required this.body});
}

class NudgeNotification {
  final String? title;
  final String? body;
  final bool sound;

  const NudgeNotification({
    required this.title,
    required this.body,
    required this.sound,
  });
}

TimedNotification? timedFromJson(dynamic json) {
  if (json is! Map) return null;
  final type = json['type'];
  if (type != 'TIMED' && type != 'TIMED_STATUS') return null;
  final fireAt = json['fireAtEpochMs'];
  final title = json['title'];
  final body = json['body'];
  final sound = json['sound'];
  final countDownText = json['countDownText'];
  return TimedNotification(
    fireAtEpochMs: fireAt is num ? fireAt.toInt() : null,
    title: title is String ? title : null,
    body: body is String ? body : null,
    sound: sound is bool ? sound : true,
    countDownText: countDownText is String ? countDownText : null,
  );
}

TimedNotification? timedStatusFromJson(dynamic json) {
  if (json is! Map) return null;
  final type = json['type'];
  if (type != 'TIMED_STATUS') return null;
  final fireAt = json['fireAtEpochMs'];
  final title = json['title'];
  final body = json['body'];
  final sound = json['sound'];
  return TimedNotification(
    fireAtEpochMs: fireAt is num ? fireAt.toInt() : null,
    title: title is String ? title : null,
    body: body is String ? body : null,
    sound: sound is bool ? sound : true,
  );
}

ImmediateNotification? immediateFromJson(dynamic json) {
  if (json is! Map) return null;
  final type = json['type'];
  if (type != 'IMMEDIATE') return null;
  final body = json['body'];
  return ImmediateNotification(body: body is String ? body : null);
}

NudgeNotification? nudgeFromJson(dynamic json) {
  if (json is! Map) return null;
  final type = json['type'];
  if (type != 'NUDGE') return null;
  final title = json['title'];
  final body = json['body'];
  final sound = json['sound'];
  return NudgeNotification(
    title: title is String ? title : null,
    body: body is String ? body : null,
    sound: sound is bool ? sound : true,
  );
}

/// Mirror of `UNAuthorizationStatus`.
enum NotificationAuthStatus {
  authorized,
  denied,
  notDetermined,
  provisional,
  ephemeral,
  unknown,
}

/// Mirror of `UNAlertStyle`. In iOS Settings these surface as the Banner Style:
/// [banner] == "Temporary" (auto-dismiss), [alert] == "Persistent" (stays).
enum NotificationAlertStyle { none, banner, alert, unknown }

extension NotificationAlertStyleDisplay on NotificationAlertStyle {
  String get displayName {
    switch (this) {
      case NotificationAlertStyle.banner:
        return 'Temporary';
      case NotificationAlertStyle.alert:
        return 'Persistent';
      case NotificationAlertStyle.none:
        return 'Off';
      case NotificationAlertStyle.unknown:
        return 'Unknown';
    }
  }
}

/// Live snapshot of the OS notification settings, read via the platform channel.
class NotificationSettingsInfo {
  final NotificationAuthStatus authStatus;
  final NotificationAlertStyle alertStyle;

  const NotificationSettingsInfo({
    required this.authStatus,
    required this.alertStyle,
  });

  static const unknown = NotificationSettingsInfo(
    authStatus: NotificationAuthStatus.unknown,
    alertStyle: NotificationAlertStyle.unknown,
  );

  static NotificationSettingsInfo fromMap(Map<String, dynamic>? map) {
    if (map == null) return unknown;
    return NotificationSettingsInfo(
      authStatus: _authFromString(map['authorizationStatus'] as String?),
      alertStyle: _styleFromString(map['alertStyle'] as String?),
    );
  }

  static NotificationAuthStatus _authFromString(String? value) {
    switch (value) {
      case 'authorized':
        return NotificationAuthStatus.authorized;
      case 'denied':
        return NotificationAuthStatus.denied;
      case 'notDetermined':
        return NotificationAuthStatus.notDetermined;
      case 'provisional':
        return NotificationAuthStatus.provisional;
      case 'ephemeral':
        return NotificationAuthStatus.ephemeral;
      default:
        return NotificationAuthStatus.unknown;
    }
  }

  static NotificationAlertStyle _styleFromString(String? value) {
    switch (value) {
      case 'none':
        return NotificationAlertStyle.none;
      case 'banner':
        return NotificationAlertStyle.banner;
      case 'alert':
        return NotificationAlertStyle.alert;
      default:
        return NotificationAlertStyle.unknown;
    }
  }
}
