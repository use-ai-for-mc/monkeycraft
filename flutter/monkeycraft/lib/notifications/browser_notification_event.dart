enum BrowserNotificationKind { immediate, timed }

class BrowserNotificationEvent {
  const BrowserNotificationEvent({
    required this.kind,
    required this.title,
    required this.body,
    required this.sound,
    required this.systemNotification,
  });

  final BrowserNotificationKind kind;
  final String title;
  final String body;
  final bool sound;
  final bool systemNotification;
}
