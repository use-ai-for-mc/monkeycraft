package com.chenweikeng.monkeycraft.mixin;

import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(AbstractContainerScreen.class)
public interface AbstractContainerScreenAccessor {
  @Accessor("leftPos")
  int monkeycraft$getLeftPos();

  @Accessor("topPos")
  int monkeycraft$getTopPos();

  @Accessor("imageWidth")
  int monkeycraft$getImageWidth();

  @Accessor("imageHeight")
  int monkeycraft$getImageHeight();
}
