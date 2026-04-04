package com.chenweikeng.monkeycraft.server.handler;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.mixin.KeyMappingAccessor;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.platform.InputConstants;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import org.java_websocket.WebSocket;

public class InputHandler {
  private static final Gson GSON = new Gson();
  private final WebSocketServerHandler handler;

  public InputHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  public void handleInput(JsonObject json) {
    if (!json.has("key") || !json.has("pressed")) return;

    String key = json.get("key").getAsString();
    boolean pressed = json.get("pressed").getAsBoolean();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (pressed && shouldCloseChatForInput(key)) {
            closeChatScreenIfOpen(mc);
          }

          KeyMapping binding = null;

          switch (key) {
            case "W":
              binding = mc.options.keyUp;
              break;
            case "A":
              binding = mc.options.keyLeft;
              break;
            case "S":
              binding = mc.options.keyDown;
              break;
            case "D":
              binding = mc.options.keyRight;
              break;
            case "SPACE":
              binding = mc.options.keyJump;
              break;
            case "SHIFT":
              binding = mc.options.keyShift;
              break;
            case "Q":
              binding = mc.options.keyDrop;
              break;
            case "E":
              binding = mc.options.keyInventory;
              break;
            case "F":
              binding = mc.options.keySwapOffhand;
              break;
            case "LEFT":
              handler.setTurnLeft(pressed);
              break;
            case "RIGHT":
              handler.setTurnRight(pressed);
              break;
            case "UP":
              handler.setLookUp(pressed);
              break;
            case "DOWN":
              handler.setLookDown(pressed);
              break;
          }

          if (binding != null) {
            InputConstants.Key boundKey = ((KeyMappingAccessor) binding).monkeycraft$getKey();
            if (pressed) {
              KeyMapping.set(boundKey, true);
              KeyMapping.click(boundKey);
            } else {
              KeyMapping.set(boundKey, false);
            }
          }
        });
  }

  public void handleClick(JsonObject json) {
    int button = json.has("button") ? json.get("button").getAsInt() : 0;
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          try {
            if (MonkeycraftClient.pendingMouseReleaseTicks > 0) {
              if (MonkeycraftClient.pendingMouseButton == 1) mc.options.keyUse.setDown(false);
              if (MonkeycraftClient.pendingMouseButton == 0) mc.options.keyAttack.setDown(false);
              MonkeycraftClient.pendingMouseReleaseTicks = 0;
            }

            if (button == 1) mc.options.keyUse.setDown(true);
            if (button == 0) mc.options.keyAttack.setDown(true);

            MonkeycraftClient.pendingMouseButton = button;
            MonkeycraftClient.pendingMouseReleaseTicks = 2;
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to synthesize click", e);
          }
        });
  }

  public void handleHotbarSelect(JsonObject json) {
    if (!json.has("slot")) return;
    int slot = json.get("slot").getAsInt();
    if (slot < 0) slot = 0;
    if (slot > 8) slot = 8;

    final int selectedSlot = slot;
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.player == null) return;
          try {
            mc.player.getInventory().setSelectedSlot(selectedSlot);
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to set hotbar slot", e);
          }
        });
  }

  public void handleLookDelta(WebSocket conn, JsonObject json) {
    if (!json.has("yaw") || !json.has("pitch")) return;

    float yawDelta = json.get("yaw").getAsFloat();
    float pitchDelta = json.get("pitch").getAsFloat();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.player == null) return;
          closeChatScreenIfOpen(mc);
          float newYaw = mc.player.getYRot() + yawDelta;
          float newPitch = mc.player.getXRot() + pitchDelta;
          if (newPitch > 90.0f) newPitch = 90.0f;
          if (newPitch < -90.0f) newPitch = -90.0f;
          mc.player.setYRot(newYaw);
          mc.player.setXRot(newPitch);
          JsonObject response = new JsonObject();
          response.addProperty("type", "PLAYER_POSE");
          response.addProperty("yaw", mc.player.getYRot());
          response.addProperty("pitch", mc.player.getXRot());
          conn.send(GSON.toJson(response));
        });
  }

  public void handleGetPlayerPose(WebSocket conn) {
    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.player == null) return;
          JsonObject response = new JsonObject();
          response.addProperty("type", "PLAYER_POSE");
          response.addProperty("yaw", mc.player.getYRot());
          response.addProperty("pitch", mc.player.getXRot());
          conn.send(GSON.toJson(response));
        });
  }

  private boolean shouldCloseChatForInput(String key) {
    return switch (key) {
      case "W", "A", "S", "D", "SPACE", "SHIFT", "Q", "E", "F", "LEFT", "RIGHT", "UP", "DOWN" ->
          true;
      default -> false;
    };
  }

  private void closeChatScreenIfOpen(Minecraft mc) {
    if (mc.screen instanceof net.minecraft.client.gui.screens.ChatScreen) {
      mc.gui.getChat().restoreChatScreen();
      mc.setScreen(null);
    }
  }
}
