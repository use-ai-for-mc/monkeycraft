package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.ChatHandler;
import java.util.UUID;
import net.minecraft.network.chat.ChatSender;
import net.minecraft.network.chat.ChatType;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.PlayerChatMessage;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = net.minecraft.client.multiplayer.chat.ChatListener.class, priority = 100)
public class ChatListenerMixin {

  @Inject(method = "handleChatMessage", at = @At("RETURN"))
  private void monkeycraft$onHandleChatMessage(
      PlayerChatMessage playerChatMessage,
      ChatSender chatSender,
      ChatType.Bound bound,
      CallbackInfo ci) {
    try {
      Component message = playerChatMessage.serverContent();
      String senderName =
          chatSender != null && chatSender.displayName() != null
              ? chatSender.displayName().getString()
              : null;
      UUID senderUuid = chatSender != null ? chatSender.profileId() : null;

      ChatHandler.getInstance()
          .handleIncomingChat(
              message, senderName, senderUuid != null ? senderUuid.toString() : null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling chat message", e);
    }
  }

  @Inject(method = "handleSystemMessage", at = @At("RETURN"))
  private void monkeycraft$onHandleSystemMessage(
      Component component, boolean overlay, CallbackInfo ci) {
    if (overlay) {
      return;
    }
    try {
      ChatHandler.getInstance().handleIncomingChat(component, null, null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling chat message", e);
    }
  }
}
