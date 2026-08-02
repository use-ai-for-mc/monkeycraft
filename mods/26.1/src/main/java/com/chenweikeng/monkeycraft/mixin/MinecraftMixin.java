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
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

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

  @Inject(method = "pauseIfInactive", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$skipRemoteInactivePause(CallbackInfo ci) {
    if (monkeycraft$isRemoteCursorReleased()) {
      ci.cancel();
    }
  }

  @Inject(method = "isWindowActive", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$keepRemoteWindowActive(CallbackInfoReturnable<Boolean> cir) {
    if (monkeycraft$isRemoteCursorReleased()) {
      cir.setReturnValue(true);
    }
  }

  @Unique
  private static boolean monkeycraft$isRemoteCursorReleased() {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    return MonkeycraftClient.automaticallyReleasedCursor || handler.isStreaming();
  }
}
