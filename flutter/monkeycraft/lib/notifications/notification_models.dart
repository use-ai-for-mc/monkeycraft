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
