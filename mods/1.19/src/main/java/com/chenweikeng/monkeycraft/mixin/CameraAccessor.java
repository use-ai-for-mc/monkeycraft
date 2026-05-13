package com.chenweikeng.monkeycraft.mixin;

import net.minecraft.client.Camera;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

@Mixin(Camera.class)
public interface CameraAccessor {
  @Invoker("setPosition")
  void invokeSetPosition(double x, double y, double z);

  @Invoker("setRotation")
  void invokeSetRotation(float yaw, float pitch);
}
