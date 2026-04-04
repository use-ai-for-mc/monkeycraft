package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.ChatHandler;
import com.mojang.authlib.GameProfile;
import java.util.UUID;
import net.minecraft.network.chat.ChatType;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.PlayerChatMessage;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = net.minecraft.client.multiplayer.chat.ChatListener.class, priority = 100)
public class ChatListenerMixin {

  @Inject(method = "handlePlayerChatMessage", at = @At("RETURN"))
  private void onHandlePlayerChatMessage(
      PlayerChatMessage playerChatMessage,
      GameProfile gameProfile,
      ChatType.Bound bound,
      CallbackInfo ci) {
    try {
      Component message = playerChatMessage.decoratedContent();
      String senderName = gameProfile.name();
      UUID senderUuid = gameProfile.id();

      ChatHandler.getInstance()
          .handleIncomingChat(
              message, senderName, senderUuid != null ? senderUuid.toString() : null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling chat message", e);
    }
  }

  @Inject(method = "handleSystemMessage", at = @At("RETURN"))
  private void onHandleSystemMessage(Component component, boolean remote, CallbackInfo ci) {
    try {
      ChatHandler.getInstance().handleIncomingChat(component, null, null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling system message", e);
    }
  }

  @Inject(method = "handleOverlay", at = @At("RETURN"))
  private void onHandleOverlay(Component component, CallbackInfo ci) {
    // Overlay/action bar messages — intentionally not forwarded to chat
  }
}
