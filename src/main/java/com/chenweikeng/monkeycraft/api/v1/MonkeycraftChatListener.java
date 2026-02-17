package com.chenweikeng.monkeycraft.api.v1;

@FunctionalInterface
public interface MonkeycraftChatListener {
  ChatMessageResult onChatMessage(ChatMessageContext context);
}
