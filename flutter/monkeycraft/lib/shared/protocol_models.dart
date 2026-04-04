enum ClientMode { streaming, chat, map }

enum VideoState { active, hibernating }

class ServerStatus {
  final VideoState videoState;
  final String? message;

  final int? timedFireAtEpochMs;
  final String? timedTitle;
  final String? timedBody;
  final bool timedSound;
  final String? timedCountDownText;

  const ServerStatus({
    required this.videoState,
    this.message,
    this.timedFireAtEpochMs,
    this.timedTitle,
    this.timedBody,
    this.timedSound = true,
    this.timedCountDownText,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    final stateStr = json['videoState'] as String?;
    final videoState = stateStr == 'HIBERNATING'
        ? VideoState.hibernating
        : VideoState.active;

    return ServerStatus(
      videoState: videoState,
      message: json['message'] as String?,
      timedFireAtEpochMs: json['timedFireAtEpochMs'] as int?,
      timedTitle: json['timedTitle'] as String?,
      timedBody: json['timedBody'] as String?,
      timedSound: json['timedSound'] as bool? ?? true,
      timedCountDownText: json['timedCountDownText'] as String?,
    );
  }

  bool get hasTimedNotification => timedFireAtEpochMs != null;
}

class PlayerPose {
  final double yaw;
  final double pitch;

  const PlayerPose({required this.yaw, required this.pitch});
}

class CommandDeniedEvent {
  final String command;

  const CommandDeniedEvent({required this.command});
}

class ServerDisconnectEvent {
  final String reason;

  const ServerDisconnectEvent({required this.reason});
}

class MapEntity {
  final int type; // 0=vehicle, 1=player, 2=rideable mob
  final double x;
  final double z;
  final int entityId;
  final String name;

  const MapEntity({
    required this.type,
    required this.x,
    required this.z,
    required this.entityId,
    required this.name,
  });

  bool get isVehicle => type == 0;
  bool get isPlayer => type == 1;
  bool get isRideableMob => type == 2;
  bool get isRideable => type == 0 || type == 2;
}

class MapData {
  final double playerX;
  final double playerZ;
  final double playerYaw;
  final String playerUuid;
  final List<MapEntity> entities;

  const MapData({
    required this.playerX,
    required this.playerZ,
    required this.playerYaw,
    required this.playerUuid,
    required this.entities,
  });
}
