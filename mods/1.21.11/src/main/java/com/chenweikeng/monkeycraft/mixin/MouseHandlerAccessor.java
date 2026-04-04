package com.chenweikeng.monkeycraft.mixin;

import net.minecraft.client.MouseHandler;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(MouseHandler.class)
public interface MouseHandlerAccessor {
  @Accessor("xpos")
  void monkeycraft$setXpos(double xpos);

  @Accessor("ypos")
  void monkeycraft$setYpos(double ypos);
}
