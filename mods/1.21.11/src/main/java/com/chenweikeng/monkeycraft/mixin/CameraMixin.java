package com.chenweikeng.monkeycraft.mixin;

import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.minecraft.client.Camera;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Camera.class)
public class CameraMixin {

  private static final float TOP_DOWN_HEIGHT = 4.0f;

  @Inject(method = "update", at = @At("RETURN"))
  private void onCameraUpdateReturn(DeltaTracker deltaTracker, CallbackInfo ci) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isMapMode()) return;

    Minecraft mc = Minecraft.getInstance();
    if (mc.player == null) return;

    float partialTick = deltaTracker.getGameTimeDeltaPartialTick(false);
    double playerX = mc.player.xo + (mc.player.getX() - mc.player.xo) * partialTick;
    double playerY = mc.player.yo + (mc.player.getY() - mc.player.yo) * partialTick;
    double playerZ = mc.player.zo + (mc.player.getZ() - mc.player.zo) * partialTick;

    CameraAccessor accessor = (CameraAccessor) this;
    accessor.invokeSetPosition(playerX, playerY + TOP_DOWN_HEIGHT, playerZ);
    // pitch = 90 = looking straight down, yaw = 180 = north-up
    accessor.invokeSetRotation(180.0f, 90.0f);
  }
}
