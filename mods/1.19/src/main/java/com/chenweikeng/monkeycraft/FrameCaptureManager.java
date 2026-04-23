package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.ImageUtils;
import com.chenweikeng.monkeycraft.utils.ScreenHelper;
import com.mojang.blaze3d.platform.NativeImage;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;

public class FrameCaptureManager {
  private long lastCaptureTime = 0;

  public void tick(Minecraft client) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isStreaming()) return;

    WebSocketServerHandler.StreamConfig streamConfig = handler.getStreamConfig();
    long interval = 1000 / Math.max(1, streamConfig.fps);

    long now = System.currentTimeMillis();
    if (now - lastCaptureTime < interval) return;

    if (client.gameRenderer == null) return;

    lastCaptureTime = now;

    NativeImage image;
    try {
      image = Screenshot.takeScreenshot(client.getMainRenderTarget());
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.info("Error capturing stream frame", e);
      return;
    }
    if (image == null) return;

    try {
      WebSocketServerHandler h = WebSocketServerHandler.getInstance();
      WebSocketServerHandler.StreamConfig config = h.getStreamConfig();

      if (h.isScreenOpen() && client.mouseHandler != null) {
        double mouseX = client.mouseHandler.xpos();
        double mouseY = client.mouseHandler.ypos();
        int framebufferWidth = image.getWidth();
        int framebufferHeight = image.getHeight();
        int screenWidth = client.getWindow().getScreenWidth();
        int screenHeight = client.getWindow().getScreenHeight();

        int cursorX = (int) (mouseX * framebufferWidth / screenWidth);
        int cursorY = (int) (mouseY * framebufferHeight / screenHeight);

        ImageUtils.drawCursor(image, cursorX, cursorY);
      }

      int targetWidth = config.width;
      int targetHeight = config.height;

      int cropX, cropY, cropWidth, cropHeight;
      int resizeWidth = targetWidth;
      int resizeHeight = targetHeight;
      boolean useLetterbox = false;

      double scaleFactor = client.getWindow().getGuiScale();

      if (h.isScreenOpen() && ScreenHelper.needsLetterboxing(client.screen)) {
        int[] overlayBounds =
            ScreenHelper.getCropBoundsForFullScreenOverlay(
                client.screen, image.getWidth(), image.getHeight(), scaleFactor);
        if (overlayBounds != null) {
          cropX = overlayBounds[0];
          cropY = overlayBounds[1];
          cropWidth = overlayBounds[2];
          cropHeight = overlayBounds[3];
          useLetterbox = true;
        } else {
          cropX = 0;
          cropY = 0;
          cropWidth = image.getWidth();
          cropHeight = image.getHeight();
          useLetterbox = true;
        }
      } else {
        int[] cropBounds =
            ScreenHelper.getCropBounds(
                client.screen,
                image.getWidth(),
                image.getHeight(),
                targetWidth,
                targetHeight,
                scaleFactor);

        if (h.isScreenOpen() && cropBounds != null) {
          cropX = cropBounds[0];
          cropY = cropBounds[1];
          cropWidth = cropBounds[2];
          cropHeight = cropBounds[3];
        } else {
          double targetAspect = (double) targetWidth / (double) targetHeight;
          cropWidth = image.getWidth();
          cropHeight = image.getHeight();

          if (cropWidth > cropHeight * targetAspect) {
            cropWidth = (int) (cropHeight * targetAspect);
          } else {
            cropHeight = (int) (cropWidth / targetAspect);
          }

          cropX = (image.getWidth() - cropWidth) / 2;
          cropY = image.getHeight() - cropHeight;
        }
      }

      NativeImage cropped = ImageUtils.crop(image, cropX, cropY, cropWidth, cropHeight);
      try {
        NativeImage resized =
            useLetterbox
                ? ImageUtils.resizeWithLetterbox(cropped, resizeWidth, resizeHeight)
                : ImageUtils.resize(cropped, resizeWidth, resizeHeight);
        h.broadcastFrame(resized);
      } finally {
        cropped.close();
      }
    } finally {
      image.close();
    }
  }
}
