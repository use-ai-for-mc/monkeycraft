package com.chenweikeng.monkeycraft.utils;

import com.mojang.blaze3d.platform.NativeImage;

public class ImageUtils {
  private static final int[][] CURSOR_SHAPE = {
    {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 1, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 1, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 2, 1, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 2, 2, 1, 0, 0},
    {1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 0},
    {1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1},
    {1, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1},
    {1, 2, 2, 2, 1, 2, 2, 1, 0, 0, 0},
    {1, 2, 2, 1, 0, 1, 2, 2, 1, 0, 0},
    {1, 2, 1, 0, 0, 1, 2, 2, 1, 0, 0},
    {1, 1, 0, 0, 0, 0, 1, 2, 2, 1, 0},
    {1, 0, 0, 0, 0, 0, 1, 2, 2, 1, 0},
    {0, 0, 0, 0, 0, 0, 0, 1, 2, 1, 0},
    {0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0},
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
  };

  private static final int CURSOR_WHITE = 0xFFFFFFFF;
  private static final int CURSOR_BLACK = 0xFF000000;

  public static NativeImage resize(NativeImage source, int targetWidth, int targetHeight) {
    NativeImage resized = new NativeImage(source.format(), targetWidth, targetHeight, false);
    source.resizeSubRectTo(0, 0, source.getWidth(), source.getHeight(), resized);
    return resized;
  }

  public static NativeImage crop(NativeImage source, int x, int y, int width, int height) {
    NativeImage cropped = new NativeImage(source.format(), width, height, false);
    for (int dy = 0; dy < height; dy++) {
      for (int dx = 0; dx < width; dx++) {
        cropped.setPixelRGBA(dx, dy, source.getPixelRGBA(x + dx, y + dy));
      }
    }
    return cropped;
  }

  public static NativeImage resizeWithLetterbox(
      NativeImage source, int targetWidth, int targetHeight) {
    NativeImage result = new NativeImage(source.format(), targetWidth, targetHeight, false);

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        result.setPixelRGBA(x, y, 0xFF000000);
      }
    }

    double scaleX = (double) targetWidth / source.getWidth();
    double scaleY = (double) targetHeight / source.getHeight();
    double scale = Math.min(scaleX, scaleY);

    int scaledWidth = (int) Math.round(source.getWidth() * scale);
    int scaledHeight = (int) Math.round(source.getHeight() * scale);

    int offsetX = (targetWidth - scaledWidth) / 2;
    int offsetY = (targetHeight - scaledHeight) / 2;

    NativeImage scaled = new NativeImage(source.format(), scaledWidth, scaledHeight, false);
    source.resizeSubRectTo(0, 0, source.getWidth(), source.getHeight(), scaled);

    for (int dy = 0; dy < scaledHeight; dy++) {
      for (int dx = 0; dx < scaledWidth; dx++) {
        result.setPixelRGBA(offsetX + dx, offsetY + dy, scaled.getPixelRGBA(dx, dy));
      }
    }
    scaled.close();

    return result;
  }

  public static void drawCursor(NativeImage image, int cursorX, int cursorY) {
    int imgWidth = image.getWidth();
    int imgHeight = image.getHeight();

    for (int row = 0; row < CURSOR_SHAPE.length; row++) {
      for (int col = 0; col < CURSOR_SHAPE[row].length; col++) {
        int pixel = CURSOR_SHAPE[row][col];
        if (pixel == 0) continue;

        int x = cursorX + col;
        int y = cursorY + row;

        if (x < 0 || x >= imgWidth || y < 0 || y >= imgHeight) continue;

        int color = (pixel == 1) ? CURSOR_BLACK : CURSOR_WHITE;
        image.setPixelRGBA(x, y, color);
      }
    }
  }
}
