package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Minecraft.class)
public class MinecraftMixin {
  @Inject(method = "setScreen", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$blockPauseScreen(Screen screen, CallbackInfo ci) {
    if (!MonkeycraftClient.automaticallyReleasedCursor) return;
    if (screen instanceof PauseScreen || screen instanceof AbstractContainerScreen) {
      ci.cancel();
    }
  }

  @Inject(method = "setWindowActive", at = @At("HEAD"), cancellable = true)
  private void monkeycraft$onSetWindowActive(boolean bl, CallbackInfo ci) {
    if (!bl && MonkeycraftClient.automaticallyReleasedCursor) {
      ci.cancel();
    }
  }
}
