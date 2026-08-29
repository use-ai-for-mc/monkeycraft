package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import net.minecraft.client.player.LocalPlayer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(LocalPlayer.class)
public class LocalPlayerMixin {

  @Inject(method = "isAutoJumpEnabled()Z", at = @At("RETURN"), cancellable = true)
  private void onIsAutoJumpEnabled(CallbackInfoReturnable<Boolean> cir) {
    if (ModConfig.getInstance().isAlwaysAutoJump() && MonkeycraftClient.isConnectedToClient) {
      cir.setReturnValue(true);
    }
  }
}
