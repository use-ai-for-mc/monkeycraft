package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft_api.v1.ChatMessageContext;
import com.chenweikeng.monkeycraft_api.v1.ChatMessageResult;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;

public class ChatHandler {
  private static final ChatHandler INSTANCE = new ChatHandler();
  private static final Gson GSON = new Gson();

  private ChatHandler() {}

  public static ChatHandler getInstance() {
    return INSTANCE;
  }

  public void handleIncomingChat(String message, String senderName, String senderUuid) {
    ChatMessageContext context = new ChatMessageContext(message, senderUuid, senderName, false);

    ChatMessageResult result = MonkeycraftApi.INCOMING_CHAT.invoker().onChatMessage(context);

    if (result == ChatMessageResult.DENY) {
      return;
    }

    String finalMessage = context.getMessage();
    if (result == ChatMessageResult.MODIFY) {
      MonkeycraftClient.LOGGER.debug("Chat message modified: {} -> {}", message, finalMessage);
    }

    sendChatToClient(senderName, senderUuid, finalMessage);
  }

  public void handleSystemChat(String message) {
    sendChatToClient("System", null, message);
  }

  public boolean handleOutgoingChat(String message) {
    if (message == null || message.trim().isEmpty()) {
      return false;
    }

    if (message.startsWith("/")) {
      return false;
    }

    Minecraft mc = Minecraft.getInstance();
    String senderName = mc.player != null ? mc.player.getName().getString() : "Unknown";
    String senderUuid = mc.player != null ? mc.player.getUUID().toString() : null;

    ChatMessageContext context =
        new ChatMessageContext(message.trim(), senderUuid, senderName, true);

    ChatMessageResult result = MonkeycraftApi.OUTGOING_CHAT.invoker().onChatMessage(context);

    if (result == ChatMessageResult.DENY) {
      MonkeycraftClient.LOGGER.debug("Outgoing chat message denied: {}", message);
      return false;
    }

    String finalMessage = context.getMessage();

    if (mc.player != null) {
      mc.player.connection.sendChat(finalMessage);
      return true;
    }

    return false;
  }

  private void sendChatToClient(String senderName, String senderUuid, String message) {
    WebSocketServerHandler wsHandler = WebSocketServerHandler.getInstance();
    if (!wsHandler.isClientConnected()) {
      return;
    }

    JsonObject chatMsg = new JsonObject();
    chatMsg.addProperty("type", "CHAT_MESSAGE");
    chatMsg.addProperty("sender", senderName != null ? senderName : "Unknown");
    if (senderUuid != null) {
      chatMsg.addProperty("senderUuid", senderUuid);
    }
    chatMsg.addProperty("message", message);
    chatMsg.addProperty("timestamp", System.currentTimeMillis());

    wsHandler.sendChatMessage(GSON.toJson(chatMsg));
  }
}
