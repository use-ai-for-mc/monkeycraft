sealed class HibernationEvent {
  const HibernationEvent();
}

class HibernationStatus extends HibernationEvent {
  final bool active;
  final String? message;

  const HibernationStatus({required this.active, required this.message});
}

HibernationStatus? hibernationStatusFromJson(dynamic json) {
  if (json is! Map) return null;
  if (json['type'] != 'HIBERNATION_STATUS') return null;
  final active = json['active'];
  final message = json['message'];
  if (active is! bool) return null;
  return HibernationStatus(
    active: active,
    message: message is String ? message : null,
  );
}
