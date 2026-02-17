package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.server.ChatHandler;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.network.protocol.game.ClientboundPlayerChatPacket;
import net.minecraft.network.protocol.game.ClientboundSystemChatPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientPacketListener.class)
public class ClientPacketListenerMixin {

  @Inject(method = "handlePlayerChat", at = @At("RETURN"))
  private void onHandlePlayerChat(ClientboundPlayerChatPacket packet, CallbackInfo ci) {
    try {
      String message = packet.body().content();
      String senderName = "Player";
      String senderUuid = null;
      ChatHandler.getInstance().handleIncomingChat(message, senderName, senderUuid);
    } catch (Exception e) {
    }
  }

  @Inject(method = "handleSystemChat", at = @At("RETURN"))
  private void onHandleSystemChat(ClientboundSystemChatPacket packet, CallbackInfo ci) {
    try {
      String message = packet.content().getString();
      ChatHandler.getInstance().handleSystemChat(message);
    } catch (Exception e) {
    }
  }
}
