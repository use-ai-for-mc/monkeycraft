package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Minecraft.class)
public class MinecraftMixin {
  @Inject(method = "pauseIfInactive()V", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$skipRemoteInactivePause(CallbackInfo ci) {
    if (monkeycraft$isRemoteCursorReleased()) {
      ci.cancel();
    }
  }

  @Inject(method = "isWindowActive()Z", at = @At("HEAD"), cancellable = true)
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
