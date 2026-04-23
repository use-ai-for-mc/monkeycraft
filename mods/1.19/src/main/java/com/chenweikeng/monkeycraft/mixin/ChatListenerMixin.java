package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.ChatHandler;
import java.util.UUID;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.network.chat.ChatSender;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.PlayerChatMessage;
import net.minecraft.network.protocol.game.ClientboundPlayerChatPacket;
import net.minecraft.network.protocol.game.ClientboundSystemChatPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = ClientPacketListener.class, priority = 100)
public class ChatListenerMixin {

  @Inject(
      method =
          "handlePlayerChat(Lnet/minecraft/network/protocol/game/ClientboundPlayerChatPacket;)V",
      at = @At("RETURN"))
  private void monkeycraft$onHandlePlayerChat(ClientboundPlayerChatPacket packet, CallbackInfo ci) {
    try {
      PlayerChatMessage chatMessage = packet.getMessage();
      Component message = chatMessage.serverContent();
      ChatSender sender = packet.sender();
      String senderName =
          sender != null && sender.name() != null ? sender.name().getString() : null;
      UUID senderUuid = sender != null ? sender.uuid() : null;

      ChatHandler.getInstance()
          .handleIncomingChat(
              message, senderName, senderUuid != null ? senderUuid.toString() : null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling chat message", e);
    }
  }

  @Inject(
      method =
          "handleSystemChat(Lnet/minecraft/network/protocol/game/ClientboundSystemChatPacket;)V",
      at = @At("RETURN"))
  private void monkeycraft$onHandleSystemChat(ClientboundSystemChatPacket packet, CallbackInfo ci) {
    // typeId 2 is the GAME_INFO overlay (action bar) — skip those.
    if (packet.typeId() == 2) {
      return;
    }
    try {
      ChatHandler.getInstance().handleIncomingChat(packet.content(), null, null);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Error handling chat message", e);
    }
  }
}
