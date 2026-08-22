package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.utils.ScreenHelper;
import com.mojang.blaze3d.platform.Window;
import net.minecraft.client.KeyboardHandler;
import net.minecraft.client.Minecraft;
import net.minecraft.client.input.KeyEvent;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = KeyboardHandler.class, priority = 100)
public class KeyboardMixin {
  @Shadow private Minecraft minecraft;

  @Inject(method = "keyPress(JILnet/minecraft/client/input/KeyEvent;)V", at = @At("HEAD"))
  private void monkeycraft$onKeyPress(long window, int action, KeyEvent keyEvent, CallbackInfo ci) {
    Window curWindow = this.minecraft.getWindow();
    if (window == curWindow.handle()) {
      if (action == GLFW.GLFW_PRESS) {
        MonkeycraftClient.lastLocalKeyInputTime = System.currentTimeMillis();

        if (minecraft.options.keyCommand.matches(keyEvent)) {
          ScreenHelper.startChatGracePeriod();
        }
      }
    }
  }
}
