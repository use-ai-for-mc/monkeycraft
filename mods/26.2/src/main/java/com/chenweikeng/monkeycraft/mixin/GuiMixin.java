package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Gui.class)
public class GuiMixin {
  @Inject(
      method = "setScreen(Lnet/minecraft/client/gui/screens/Screen;)V",
      at = @At("HEAD"),
      cancellable = true)
  private void monkeycraft$blockRemotePauseScreen(Screen screen, CallbackInfo ci) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (screen instanceof PauseScreen
        && (MonkeycraftClient.automaticallyReleasedCursor || handler.isStreaming())
        && !MonkeycraftClient.hasRecentLocalKeyInput()) {
      ci.cancel();
    }
  }
}
