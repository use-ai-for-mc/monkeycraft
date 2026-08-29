class McParksActiveTrack {
  final String name;
  final String? url;
  final bool looping;
  final int serverVolume;
  final DateTime? startedAt;
  final DateTime? firstTriggerAt;
  final DateTime? lastTriggerAt;
  final int triggerCount;
  final String lastServerMessage;
  final bool active;
  final bool fadingOut;
  final int positionMs;

  const McParksActiveTrack({
    required this.name,
    this.url,
    required this.looping,
    required this.serverVolume,
    this.startedAt,
    this.firstTriggerAt,
    this.lastTriggerAt,
    required this.triggerCount,
    required this.lastServerMessage,
    required this.active,
    required this.fadingOut,
    required this.positionMs,
  });

  factory McParksActiveTrack.fromJson(Map json) {
    DateTime? dt(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return McParksActiveTrack(
      name: (json['name'] as String?) ?? '<unknown>',
      url: json['url'] as String?,
      looping: json['looping'] == true,
      serverVolume: (json['serverVolume'] as num?)?.toInt() ?? 0,
      startedAt: dt(json['startedAtMs']),
      firstTriggerAt: dt(json['firstTriggerMs']),
      lastTriggerAt: dt(json['lastTriggerMs']),
      triggerCount: (json['triggerCount'] as num?)?.toInt() ?? 1,
      lastServerMessage: (json['lastMessage'] as String?) ?? '',
      active: json['active'] == true,
      fadingOut: json['fadingOut'] == true,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    );
  }

  String? diagnose(DateTime now) {
    if (!active) {
      return 'finished playing; stale entry, safe to stop';
    }
    if (fadingOut) {
      return 'fading out';
    }
    if (looping && triggerCount == 1) {
      return 'server sent one loop command; will play until server says stop';
    }
    if (looping && triggerCount > 1) {
      return 'server re-triggered ${triggerCount}x; possible server-side duplicate';
    }
    if (!looping && startedAt != null) {
      final age = now.difference(startedAt!);
      if (age.inSeconds > 30) {
        return 'one-shot still running after 30s+; long audio or stuck';
      }
    }
    return null;
  }
}
