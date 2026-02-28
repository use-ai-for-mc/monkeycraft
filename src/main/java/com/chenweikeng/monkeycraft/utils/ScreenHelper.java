package com.chenweikeng.monkeycraft.utils;

import com.chenweikeng.monkeycraft.mixin.AbstractContainerScreenAccessor;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.minecraft.client.gui.screens.inventory.BookEditScreen;
import net.minecraft.client.gui.screens.inventory.BookSignScreen;
import net.minecraft.client.gui.screens.inventory.BookViewScreen;

public final class ScreenHelper {

  private ScreenHelper() {}

  private static final int BOOK_IMAGE_WIDTH = 192;
  private static final int BOOK_IMAGE_HEIGHT = 192;
  private static final int BOOK_TOP_OFFSET = 2;

  private static volatile long chatGracePeriodStart = 0;
  private static final long CHAT_GRACE_PERIOD_MS = 3000;

  public static void startChatGracePeriod() {
    chatGracePeriodStart = System.currentTimeMillis();
  }

  public static boolean isInChatGracePeriod() {
    if (chatGracePeriodStart == 0) return false;
    return System.currentTimeMillis() - chatGracePeriodStart < CHAT_GRACE_PERIOD_MS;
  }

  public static boolean shouldKeepScreen(Screen screen) {
    if (screen == null) return false;
    if (screen instanceof ChatScreen) {
      return isInChatGracePeriod();
    }
    return true;
  }

  public static boolean hasSpecialCropping(Screen screen) {
    return screen != null;
  }

  public static boolean needsLetterboxing(Screen screen) {
    return screen != null
        && !(screen instanceof AbstractContainerScreen<?>)
        && !isBookScreen(screen);
  }

  public static int[] getCropBoundsForFullScreenOverlay(
      Screen screen, int imageWidth, int imageHeight, double scaleFactor) {
    if (screen == null || !needsLetterboxing(screen)) {
      return null;
    }

    int cropWidth = (int) Math.ceil(screen.width * scaleFactor);
    int cropHeight = (int) Math.ceil(screen.height * scaleFactor);

    cropWidth = Math.min(cropWidth, imageWidth);
    cropHeight = Math.min(cropHeight, imageHeight);

    return new int[] {0, 0, cropWidth, cropHeight};
  }

  private static boolean isBookScreen(Screen screen) {
    return screen instanceof BookViewScreen
        || screen instanceof BookEditScreen
        || screen instanceof BookSignScreen;
  }

  public static int[] getCropBounds(
      Screen screen,
      int imageWidth,
      int imageHeight,
      int targetWidth,
      int targetHeight,
      double scaleFactor) {
    if (screen == null) {
      return null;
    }

    int padding;
    int guiCenterX, guiCenterY, guiWidth, guiHeight;

    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
      AbstractContainerScreenAccessor accessor = (AbstractContainerScreenAccessor) containerScreen;
      guiCenterX = accessor.monkeycraft$getLeftPos() + accessor.monkeycraft$getImageWidth() / 2;
      guiCenterY = accessor.monkeycraft$getTopPos() + accessor.monkeycraft$getImageHeight() / 2;
      guiWidth = accessor.monkeycraft$getImageWidth();
      guiHeight = accessor.monkeycraft$getImageHeight();
      padding = 16;
    } else if (isBookScreen(screen)) {
      guiWidth = BOOK_IMAGE_WIDTH;
      guiHeight = BOOK_IMAGE_HEIGHT;
      int guiX = (screen.width - BOOK_IMAGE_WIDTH) / 2;
      int guiY = BOOK_TOP_OFFSET;
      guiCenterX = guiX + guiWidth / 2;
      guiCenterY = guiY + guiHeight / 2;
      padding = 16;
    } else {
      guiCenterX = screen.width / 2;
      guiCenterY = screen.height / 2;
      guiWidth = screen.width;
      guiHeight = screen.height;
      padding = 8;
    }

    int paddedWidth = (guiWidth + padding * 2);
    int paddedHeight = (guiHeight + padding * 2);

    double scaleX = (double) paddedWidth / targetWidth;
    double scaleY = (double) paddedHeight / targetHeight;
    double scale = Math.max(scaleX, scaleY);

    int cropWidth = (int) Math.ceil(targetWidth * scale * scaleFactor);
    int cropHeight = (int) Math.ceil(targetHeight * scale * scaleFactor);

    int cropX = (int) ((guiCenterX - cropWidth / scaleFactor / 2) * scaleFactor);
    int cropY = (int) ((guiCenterY - cropHeight / scaleFactor / 2) * scaleFactor);

    cropX = Math.max(0, cropX);
    cropY = Math.max(0, cropY);
    if (cropX + cropWidth > imageWidth) {
      cropWidth = imageWidth - cropX;
    }
    if (cropY + cropHeight > imageHeight) {
      cropHeight = imageHeight - cropY;
    }

    return new int[] {cropX, cropY, cropWidth, cropHeight};
  }

  public static int[] getClickableBounds(Screen screen, int padding) {
    if (screen == null) {
      return null;
    }

    int x, y, width, height;

    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
      AbstractContainerScreenAccessor accessor = (AbstractContainerScreenAccessor) containerScreen;
      x = accessor.monkeycraft$getLeftPos();
      y = accessor.monkeycraft$getTopPos();
      width = accessor.monkeycraft$getImageWidth();
      height = accessor.monkeycraft$getImageHeight();
    } else if (isBookScreen(screen)) {
      width = BOOK_IMAGE_WIDTH;
      height = BOOK_IMAGE_HEIGHT;
      x = (screen.width - BOOK_IMAGE_WIDTH) / 2;
      y = BOOK_TOP_OFFSET;
    } else {
      x = 0;
      y = 0;
      width = screen.width;
      height = screen.height;
    }

    int cropX = Math.max(0, x - padding);
    int cropY = Math.max(0, y - padding);
    int cropWidth = Math.min(screen.width - cropX, width + 2 * padding);
    int cropHeight = Math.min(screen.height - cropY, height + 2 * padding);

    return new int[] {cropX, cropY, cropWidth, cropHeight};
  }

  public static int[] getCropBoundsScreenCoords(Screen screen, int targetWidth, int targetHeight) {
    if (screen == null) {
      return null;
    }

    int padding;
    int guiCenterX, guiCenterY, guiWidth, guiHeight;

    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
      AbstractContainerScreenAccessor accessor = (AbstractContainerScreenAccessor) containerScreen;
      guiCenterX = accessor.monkeycraft$getLeftPos() + accessor.monkeycraft$getImageWidth() / 2;
      guiCenterY = accessor.monkeycraft$getTopPos() + accessor.monkeycraft$getImageHeight() / 2;
      guiWidth = accessor.monkeycraft$getImageWidth();
      guiHeight = accessor.monkeycraft$getImageHeight();
      padding = 16;
    } else if (isBookScreen(screen)) {
      guiWidth = BOOK_IMAGE_WIDTH;
      guiHeight = BOOK_IMAGE_HEIGHT;
      int guiX = (screen.width - BOOK_IMAGE_WIDTH) / 2;
      int guiY = BOOK_TOP_OFFSET;
      guiCenterX = guiX + guiWidth / 2;
      guiCenterY = guiY + guiHeight / 2;
      padding = 16;
    } else {
      guiCenterX = screen.width / 2;
      guiCenterY = screen.height / 2;
      guiWidth = screen.width;
      guiHeight = screen.height;
      padding = 8;
    }

    int paddedWidth = guiWidth + padding * 2;
    int paddedHeight = guiHeight + padding * 2;

    double scaleX = (double) paddedWidth / targetWidth;
    double scaleY = (double) paddedHeight / targetHeight;
    double scale = Math.max(scaleX, scaleY);

    int cropWidth = (int) Math.ceil(targetWidth * scale);
    int cropHeight = (int) Math.ceil(targetHeight * scale);

    int cropX = guiCenterX - cropWidth / 2;
    int cropY = guiCenterY - cropHeight / 2;

    cropX = Math.max(0, cropX);
    cropY = Math.max(0, cropY);
    if (cropX + cropWidth > screen.width) {
      cropWidth = screen.width - cropX;
    }
    if (cropY + cropHeight > screen.height) {
      cropHeight = screen.height - cropY;
    }

    return new int[] {cropX, cropY, cropWidth, cropHeight};
  }
}
