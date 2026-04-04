package com.chenweikeng.monkeycraft.mixin;

import com.mojang.blaze3d.platform.NativeImage;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

@Mixin(NativeImage.class)
public interface NativeImageAccessor {
  @Invoker("getPixelABGR")
  int monkeycraft$getPixelABGR(int x, int y);
}
