package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Minecraft.class)
public class MinecraftMixin {
  @Inject(method = "setScreen", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$blockRemotePauseScreen(Screen screen, CallbackInfo ci) {
    if (screen instanceof PauseScreen
        && monkeycraft$isRemoteCursorReleased()
        && !MonkeycraftClient.hasRecentLocalKeyInput()) {
      ci.cancel();
    }
  }

  @Inject(method = "setWindowActive", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$keepRemoteWindowActive(boolean active, CallbackInfo ci) {
    if (!active && monkeycraft$isRemoteCursorReleased()) {
      ci.cancel();
    }
  }

  @Unique
  private static boolean monkeycraft$isRemoteCursorReleased() {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    return MonkeycraftClient.automaticallyReleasedCursor || handler.isStreaming();
  }
}
