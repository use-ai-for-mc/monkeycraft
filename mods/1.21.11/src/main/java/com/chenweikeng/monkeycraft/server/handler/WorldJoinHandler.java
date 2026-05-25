package com.chenweikeng.monkeycraft.server.handler;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.ConnectScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.client.multiplayer.PlayerInfo;
import net.minecraft.client.multiplayer.ServerData;
import net.minecraft.client.multiplayer.ServerList;
import net.minecraft.client.multiplayer.resolver.ServerAddress;
import org.java_websocket.WebSocket;

/**
 * Handles app-driven multiplayer server discovery and joining, so a connected client can pick and
 * join a server while Minecraft is still at the title screen.
 */
public class WorldJoinHandler {
  private static final Gson GSON = new Gson();
  private final WebSocketServerHandler handler;

  public WorldJoinHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  /** Replies with the player's saved multiplayer server list (servers.dat). */
  public void handleListServers(WebSocket conn) {
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          JsonArray servers = new JsonArray();
          try {
            ServerList list = new ServerList(mc);
            list.load();
            for (int i = 0; i < list.size(); i++) {
              ServerData data = list.get(i);
              if (data == null) continue;
              JsonObject entry = new JsonObject();
              entry.addProperty("index", i);
              entry.addProperty("name", data.name == null ? "" : data.name);
              entry.addProperty("address", data.ip == null ? "" : data.ip);
              servers.add(entry);
            }
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to read saved server list", e);
          }
          if (!conn.isOpen()) return;
          JsonObject msg = new JsonObject();
          msg.addProperty("type", "SERVER_LIST");
          msg.add("servers", servers);
          conn.send(GSON.toJson(msg));
        });
  }

  /** Replies with the account names of players currently shown in the tab list. */
  public void handleGetPlayerList(WebSocket conn) {
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (!conn.isOpen()) return;
          JsonArray players = new JsonArray();
          ClientPacketListener connection = mc.getConnection();
          if (connection != null) {
            // Mirror the vanilla tab-list order so server-pinned players (e.g. staff with a
            // higher tabListOrder) stay on top instead of being re-sorted alphabetically.
            java.util.List<PlayerInfo> infos =
                new java.util.ArrayList<>(connection.getListedOnlinePlayers());
            infos.sort(
                java.util.Comparator.<PlayerInfo>comparingInt(p -> -p.getTabListOrder())
                    .thenComparingInt(
                        p ->
                            p.getGameMode() == net.minecraft.world.level.GameType.SPECTATOR ? 1 : 0)
                    .thenComparing(p -> p.getProfile().name(), String.CASE_INSENSITIVE_ORDER));
            for (PlayerInfo info : infos) {
              String name = info.getProfile().name();
              if (name != null && !name.isEmpty()) players.add(name);
            }
          }
          JsonObject msg = new JsonObject();
          msg.addProperty("type", "PLAYER_LIST");
          msg.addProperty("count", players.size());
          msg.add("players", players);
          conn.send(GSON.toJson(msg));
        });
  }

  /** Replies with just the number of players shown in the tab list. */
  public void handleGetPlayerCount(WebSocket conn) {
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (!conn.isOpen()) return;
          ClientPacketListener connection = mc.getConnection();
          int count = connection == null ? 0 : connection.getListedOnlinePlayers().size();
          JsonObject msg = new JsonObject();
          msg.addProperty("type", "PLAYER_COUNT");
          msg.addProperty("count", count);
          conn.send(GSON.toJson(msg));
        });
  }

  /** Connects the Minecraft client to the multiplayer server at the requested address. */
  public void handleJoinServer(WebSocket conn, JsonObject json) {
    if (!ModConfig.getInstance().isAllowRemoteServerJoin()) {
      sendJoinResult(conn, false, "Remote server join is disabled in the mod config");
      return;
    }
    if (!json.has("address")) {
      sendJoinResult(conn, false, "Missing server address");
      return;
    }
    String rawAddress = json.get("address").getAsString();
    if (rawAddress == null || rawAddress.trim().isEmpty()) {
      sendJoinResult(conn, false, "Missing server address");
      return;
    }
    final String address = rawAddress.trim();

    String nameTmp = address;
    if (json.has("name") && json.get("name").isJsonPrimitive()) {
      String n = json.get("name").getAsString();
      if (n != null && !n.isBlank()) {
        nameTmp = n;
      }
    }
    final String name = nameTmp;

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.level != null || mc.getConnection() != null) {
            sendJoinResult(conn, false, "Already connected to a world");
            return;
          }
          if (mc.screen instanceof ConnectScreen) {
            sendJoinResult(conn, false, "Already connecting to a server");
            return;
          }
          if (!ServerAddress.isValidAddress(address)) {
            sendJoinResult(conn, false, "Invalid server address: " + address);
            return;
          }
          try {
            ServerAddress parsed = ServerAddress.parseString(address);
            ServerData data = new ServerData(name, address, ServerData.Type.OTHER);
            Screen parent = mc.screen != null ? mc.screen : new TitleScreen();
            ConnectScreen.startConnecting(parent, mc, parsed, data, false, null);
            sendJoinResult(conn, true, null);
            handler.updateWorldState();
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to join server {}", address, e);
            sendJoinResult(conn, false, "Failed to start connection");
          }
        });
  }

  /** Disconnects from the current world/server back to the title screen. */
  public void handleLeaveWorld(WebSocket conn) {
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.level == null && mc.getConnection() == null) {
            return;
          }
          try {
            mc.disconnectFromWorld(ClientLevel.DEFAULT_QUIT_MESSAGE);
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to leave world", e);
          }
          handler.updateWorldState();
        });
  }

  private void sendJoinResult(WebSocket conn, boolean ok, String error) {
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "JOIN_RESULT");
    msg.addProperty("ok", ok);
    if (error != null) {
      msg.addProperty("error", error);
    }
    conn.send(GSON.toJson(msg));
  }
}
