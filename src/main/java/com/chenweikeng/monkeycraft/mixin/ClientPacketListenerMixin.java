package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.server.ChatHandler;
import java.util.UUID;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.client.multiplayer.PlayerInfo;
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
      var message = packet.unsignedContent();
      UUID senderUuid = packet.sender();
      String senderName = "Unknown";

      Minecraft minecraft = Minecraft.getInstance();

      if (minecraft.player != null) {
        if (minecraft.player.getUUID().equals(senderUuid)) {
          senderName = minecraft.player.getName().getString();
        } else if (minecraft.player.connection != null) {
          PlayerInfo playerInfo = minecraft.player.connection.getPlayerInfo(senderUuid);
          if (playerInfo != null) {
            senderName = playerInfo.getTabListDisplayName().getString();
          }
        }
      }

      String senderUuidStr = senderUuid.toString();

      ChatHandler.getInstance().handleIncomingChat(message, senderName, senderUuidStr);
    } catch (Exception e) {
    }
  }

  @Inject(method = "handleSystemChat", at = @At("RETURN"))
  private void onHandleSystemChat(ClientboundSystemChatPacket packet, CallbackInfo ci) {
    try {
      ChatHandler.getInstance().handleIncomingChat(packet.content(), null, null);
    } catch (Exception e) {
    }
  }
}
