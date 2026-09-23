package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.mojang.blaze3d.platform.Window;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Window.class)
public class WindowMixin {
  @Inject(method = "isIconified()Z", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$notIconifiedWhileStreaming(CallbackInfoReturnable<Boolean> cir) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (MonkeycraftClient.automaticallyReleasedCursor || handler.isStreaming()) {
      cir.setReturnValue(false);
    }
  }
}
