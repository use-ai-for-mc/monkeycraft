package com.chenweikeng.monkeycraft;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.animal.horse.AbstractHorse;
import net.minecraft.world.entity.vehicle.AbstractMinecart;
import net.minecraft.world.entity.vehicle.Boat;
import net.minecraft.world.phys.AABB;
import org.java_websocket.WebSocket;

public class MapDataHandler {
  private static final int MAP_RADIUS = 8;
  private static final int TICK_INTERVAL = 5; // ~4 FPS at 20 TPS
  // Magic bytes: 'M' 'M' for Map data
  private static final byte MAGIC_0 = 0x4D;
  private static final byte MAGIC_1 = 0x4D;

  private int tickCounter = 0;

  public void tick(WebSocket conn) {
    if (conn == null || !conn.isOpen()) return;

    tickCounter++;
    if (tickCounter < TICK_INTERVAL) return;
    tickCounter = 0;

    Minecraft mc = Minecraft.getInstance();
    if (mc.player == null || mc.level == null) return;

    LocalPlayer player = mc.player;
    ClientLevel level = mc.level;

    float yaw = player.getYRot();

    List<EntityInfo> entities =
        collectEntities(level, player, player.getBlockX(), player.getBlockZ());

    String playerUuid = player.getStringUUID();
    byte[] frame = buildFrame(player.getX(), player.getZ(), yaw, playerUuid, entities);
    conn.send(ByteBuffer.wrap(frame));
  }

  public void reset() {
    tickCounter = 0;
  }

  private List<EntityInfo> collectEntities(
      ClientLevel level, LocalPlayer player, int centerX, int centerZ) {
    List<EntityInfo> entities = new ArrayList<>();
    double searchRadius = MAP_RADIUS;

    // 1.19 ClientLevel doesn't have getMinY/getMaxY directly; use level.dimensionType() for height
    int minY = level.getMinBuildHeight();
    int maxY = level.getMaxBuildHeight();
    AABB searchBox =
        new AABB(
            centerX - searchRadius,
            minY,
            centerZ - searchRadius,
            centerX + searchRadius,
            maxY,
            centerZ + searchRadius);

    for (Entity entity : level.getEntities(player, searchBox)) {
      byte entityType = getEntityType(entity);
      if (entityType < 0) continue;

      entities.add(
          new EntityInfo(
              entityType, entity.getX(), entity.getZ(), entity.getId(), getEntityName(entity)));
    }
    return entities;
  }

  /**
   * Returns entity type code: 0 = rideable vehicle, 1 = other player, 2 = rideable mob, -1 = skip
   */
  private byte getEntityType(Entity entity) {
    if (entity instanceof Boat || entity instanceof AbstractMinecart) {
      return 0; // vehicle
    }
    if (entity instanceof net.minecraft.world.entity.player.Player) {
      return 1; // player
    }
    if (entity instanceof AbstractHorse horse) {
      if (horse.isSaddled()) {
        return 2; // rideable mob (horse, donkey, etc.)
      }
    }
    if (entity.isVehicle() || entity.getPassengers().size() > 0) {
      return 0;
    }
    return -1; // skip
  }

  private String getEntityName(Entity entity) {
    if (entity.hasCustomName()) {
      return entity.getCustomName().getString();
    }
    return entity.getType().getDescription().getString();
  }

  private byte[] buildFrame(
      double playerX,
      double playerZ,
      float playerYaw,
      String playerUuid,
      List<EntityInfo> entities) {
    byte[] uuidBytes = playerUuid.getBytes(java.nio.charset.StandardCharsets.UTF_8);

    int entityDataSize = 0;
    List<byte[]> entityNames = new ArrayList<>();
    for (EntityInfo e : entities) {
      byte[] nameBytes = e.name.getBytes(java.nio.charset.StandardCharsets.UTF_8);
      entityNames.add(nameBytes);
      entityDataSize += 1 + 8 + 8 + 4 + 2 + nameBytes.length;
    }

    int headerSize = 2 + 8 + 8 + 4 + 2 + uuidBytes.length + 2;
    int totalSize = headerSize + entityDataSize;

    ByteBuffer buf = ByteBuffer.allocate(totalSize);
    buf.put(MAGIC_0);
    buf.put(MAGIC_1);
    buf.putDouble(playerX);
    buf.putDouble(playerZ);
    buf.putFloat(playerYaw);
    buf.putShort((short) uuidBytes.length);
    buf.put(uuidBytes);
    buf.putShort((short) entities.size());

    for (int i = 0; i < entities.size(); i++) {
      EntityInfo e = entities.get(i);
      byte[] nameBytes = entityNames.get(i);
      buf.put(e.type);
      buf.putDouble(e.x);
      buf.putDouble(e.z);
      buf.putInt(e.entityId);
      buf.putShort((short) nameBytes.length);
      buf.put(nameBytes);
    }

    return buf.array();
  }

  private static class EntityInfo {
    final byte type;
    final double x;
    final double z;
    final int entityId;
    final String name;

    EntityInfo(byte type, double x, double z, int entityId, String name) {
      this.type = type;
      this.x = x;
      this.z = z;
      this.entityId = entityId;
      this.name = name;
    }
  }
}
