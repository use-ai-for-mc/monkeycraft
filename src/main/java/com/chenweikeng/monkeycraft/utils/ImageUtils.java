package com.chenweikeng.monkeycraft.utils;

import com.mojang.blaze3d.platform.NativeImage;

public class ImageUtils {
  public static NativeImage resize(NativeImage source, int targetWidth, int targetHeight) {
    NativeImage resized = new NativeImage(source.format(), targetWidth, targetHeight, false);
    source.resizeSubRectTo(0, 0, source.getWidth(), source.getHeight(), resized);
    return resized;
  }

  public static NativeImage crop(NativeImage source, int x, int y, int width, int height) {
    NativeImage cropped = new NativeImage(source.format(), width, height, false);
    source.copyRect(cropped, x, y, 0, 0, width, height, false, false);
    return cropped;
  }
}
