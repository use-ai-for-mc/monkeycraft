package com.chenweikeng.monkeycraft.mixin;

import net.minecraft.client.MouseHandler;
import net.minecraft.client.input.MouseButtonInfo;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

@Mixin(MouseHandler.class)
public interface MouseHandlerInvoker {
  @Invoker("onButton")
  void monkeycraft$onButton(long window, MouseButtonInfo buttonInfo, int action);
}
