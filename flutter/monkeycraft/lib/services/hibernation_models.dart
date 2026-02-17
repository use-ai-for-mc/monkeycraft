sealed class HibernationEvent {
  const HibernationEvent();
}

class HibernationStart extends HibernationEvent {
  final String message;

  const HibernationStart({required this.message});
}

class HibernationEnd extends HibernationEvent {
  const HibernationEnd();
}

class HibernationStatus extends HibernationEvent {
  final bool active;
  final String? message;

  const HibernationStatus({required this.active, required this.message});
}

class HibernationMessage extends HibernationEvent {
  final String message;

  const HibernationMessage({required this.message});
}

HibernationStart? hibernationStartFromJson(dynamic json) {
  if (json is! Map) return null;
  if (json['type'] != 'HIBERNATION_START') return null;
  final message = json['message'];
  return HibernationStart(message: message is String ? message : '');
}

HibernationEnd? hibernationEndFromJson(dynamic json) {
  if (json is! Map) return null;
  if (json['type'] != 'HIBERNATION_END') return null;
  return const HibernationEnd();
}

HibernationStatus? hibernationStatusFromJson(dynamic json) {
  if (json is! Map) return null;
  if (json['type'] != 'HIBERNATION_STATUS') return null;
  final active = json['active'];
  final message = json['message'];
  if (active is! bool) return null;
  return HibernationStatus(active: active, message: message is String ? message : null);
}

HibernationMessage? hibernationMessageFromJson(dynamic json) {
  if (json is! Map) return null;
  if (json['type'] != 'HIBERNATION_MESSAGE') return null;
  final message = json['message'];
  return HibernationMessage(message: message is String ? message : '');
}
