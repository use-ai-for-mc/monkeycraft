package com.chenweikeng.monkeycraft.server.handler;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.ChatHandler;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft_api.v1.CommandExecutionResult;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import org.java_websocket.WebSocket;

public class ChatCommandHandler {
  private static final Gson GSON = new Gson();
  private final WebSocketServerHandler handler;

  public ChatCommandHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  public void handleRunCommand(WebSocket conn, JsonObject json) {
    if (!json.has("command")) return;
    String raw = json.get("command").getAsString();
    if (raw == null) return;
    raw = raw.trim();
    if (raw.isEmpty()) return;
    if (!raw.startsWith("/")) return;
    final String command = raw;
    final String cmd = raw.substring(1);

    ModConfig config = ModConfig.getInstance();

    CommandExecutionResult apiResult =
        MonkeycraftApi.COMMAND_EXECUTION.invoker().onCommandExecution(command);

    if (apiResult == CommandExecutionResult.DENY || config.isCommandDenied(command)) {
      sendCommandDenied(conn, command);
      return;
    }

    if (apiResult != CommandExecutionResult.ALLOW) {
      if (config.isCommandAllowed(command)) {
        // Allowed by allowlist
      } else if (config.isCommandPermittedByDefault()) {
        // Allowed by default behavior
      } else {
        sendCommandDenied(conn, command);
        return;
      }
    }

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          try {
            if (mc.player != null) {
              mc.player.command(cmd);
            }
          } catch (Exception e) {
            MonkeycraftClient.LOGGER.warn("Failed to run command {}", command, e);
          }
        });
  }

  private void sendCommandDenied(WebSocket conn, String command) {
    JsonObject response = new JsonObject();
    response.addProperty("type", "COMMAND_DENIED");
    response.addProperty("command", command);
    conn.send(GSON.toJson(response));
  }

  public void handleSendChat(WebSocket conn, JsonObject json) {
    if (!json.has("message")) return;
    String message = json.get("message").getAsString();
    if (message == null || message.trim().isEmpty()) return;
    if (message.startsWith("/")) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "CHAT_DENIED");
      response.addProperty("reason", "Commands must use RUN_COMMAND");
      conn.send(GSON.toJson(response));
      return;
    }

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          boolean success = ChatHandler.getInstance().handleOutgoingChat(message);
          if (!success) {
            JsonObject response = new JsonObject();
            response.addProperty("type", "CHAT_DENIED");
            response.addProperty("reason", "Failed to send message");
            conn.send(GSON.toJson(response));
          }
        });
  }

  public void handleEnterChat(WebSocket conn) {
    handler.enterChatMode();
  }

  public void handleExitChat(WebSocket conn) {
    handler.exitChatMode();
  }

  public void handleSubscribeChat(WebSocket conn) {
    handler.subscribeChat(conn);
  }

  public void handleUnsubscribeChat() {
    handler.unsubscribeChat();
  }
}
