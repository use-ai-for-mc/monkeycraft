package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft_api.v1.ChatMessageResult;
import com.chenweikeng.monkeycraft_api.v1.IncomingChatContext;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.chenweikeng.monkeycraft_api.v1.OutgoingChatContext;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.LinkedList;
import java.util.List;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;

public class ChatHandler {
  private static final ChatHandler INSTANCE = new ChatHandler();
  private static final Gson GSON = new Gson();
  private static final int MAX_CACHE_SIZE = 100;
  private final LinkedList<JsonObject> messageCache = new LinkedList<>();

  private ChatHandler() {}

  public static ChatHandler getInstance() {
    return INSTANCE;
  }

  private synchronized void cacheMessage(JsonObject chatMsg) {
    messageCache.addLast(chatMsg);
    while (messageCache.size() > MAX_CACHE_SIZE) {
      messageCache.removeFirst();
    }
  }

  public synchronized JsonArray getCachedMessages() {
    JsonArray arr = new JsonArray();
    for (JsonObject msg : messageCache) {
      arr.add(msg);
    }
    return arr;
  }

  public void handleIncomingChat(Component message, String senderName, String senderUuid) {
    String resolvedSenderName = senderName != null ? senderName : "System";

    IncomingChatContext context = new IncomingChatContext(message, senderUuid, resolvedSenderName);

    ChatMessageResult result = MonkeycraftApi.INCOMING_CHAT.invoker().onIncomingChat(context);

    if (result == ChatMessageResult.DENY) {
      return;
    }

    Component finalMessage = context.getMessage();

    sendChatToClient(resolvedSenderName, senderUuid, finalMessage);
  }

  public void handleIncomingChat(String message) {
    handleIncomingChat(Component.literal(message), null, null);
  }

  public boolean handleOutgoingChat(String message) {
    if (message == null || message.trim().isEmpty()) {
      return false;
    }

    if (message.startsWith("/")) {
      return false;
    }

    Minecraft mc = Minecraft.getInstance();
    OutgoingChatContext context = new OutgoingChatContext(message.trim());

    ChatMessageResult result = MonkeycraftApi.OUTGOING_CHAT.invoker().onOutgoingChat(context);

    if (result == ChatMessageResult.DENY) {
      return false;
    }

    String finalMessage = context.getMessage();

    if (mc.player != null) {
      mc.player.chat(finalMessage);
      return true;
    }

    return false;
  }

  private void sendChatToClient(String senderName, String senderUuid, Component message) {
    JsonObject chatMsg = new JsonObject();
    chatMsg.addProperty("type", "CHAT_MESSAGE");
    chatMsg.addProperty("sender", senderName != null ? senderName : "Unknown");
    if (senderUuid != null) {
      chatMsg.addProperty("senderUuid", senderUuid);
    }

    List<JsonObject> segments = ChatSegment.fromComponent(message);
    chatMsg.add("segments", ChatSegment.toJsonArray(segments));
    chatMsg.addProperty("timestamp", System.currentTimeMillis());

    cacheMessage(chatMsg);

    WebSocketServerHandler wsHandler = WebSocketServerHandler.getInstance();
    if (wsHandler.isClientConnected() && wsHandler.isChatSubscribed()) {
      wsHandler.sendChatMessage(GSON.toJson(chatMsg));
    }
  }
}
