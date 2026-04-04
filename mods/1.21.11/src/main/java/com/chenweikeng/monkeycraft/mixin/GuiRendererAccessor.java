package com.chenweikeng.monkeycraft.mixin;

import net.minecraft.client.gui.render.GuiRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(GuiRenderer.class)
public interface GuiRendererAccessor {
  @Accessor("frameNumber")
  int monkeycraft$getFrameNumber();
}
