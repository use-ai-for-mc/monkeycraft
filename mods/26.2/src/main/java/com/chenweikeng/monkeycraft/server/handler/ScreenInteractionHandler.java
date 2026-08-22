package com.chenweikeng.monkeycraft.server.handler;

import static org.lwjgl.glfw.GLFW.*;

import com.chenweikeng.monkeycraft.mixin.MouseHandlerAccessor;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.ScreenHelper;
import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.minecraft.client.input.KeyEvent;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.input.MouseButtonInfo;

public class ScreenInteractionHandler {
  private final WebSocketServerHandler handler;
  private boolean screenShiftActive = false;

  public ScreenInteractionHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  public void handleScreenTap(JsonObject json) {
    if (!json.has("normalizedX") || !json.has("normalizedY")) return;
    double normX = json.get("normalizedX").getAsDouble();
    double normY = json.get("normalizedY").getAsDouble();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          net.minecraft.client.gui.screens.Screen screen = mc.gui.screen();
          if (screen == null) return;

          int screenX = (int) (normX * screen.width);
          int screenY = (int) (normY * screen.height);
        });
  }

  public void handleScreenKey(JsonObject json) {
    if (!json.has("key") || !json.has("pressed")) return;
    String key = json.get("key").getAsString();
    boolean pressed = json.get("pressed").getAsBoolean();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          net.minecraft.client.gui.screens.Screen screen = mc.gui.screen();
          if (screen == null) return;

          int keyCode =
              switch (key) {
                case "ESCAPE" -> GLFW_KEY_ESCAPE;
                default -> -1;
              };

          if (keyCode >= 0) {
            int modifiers = screenShiftActive ? GLFW_MOD_SHIFT : 0;
            KeyEvent keyEvent = new KeyEvent(keyCode, 0, modifiers);
            if (pressed) {
              screen.keyPressed(keyEvent);
            } else {
              screen.keyReleased(keyEvent);
            }
          }
        });
  }

  public void handleScreenClick(JsonObject json) {
    if (!json.has("button") || !json.has("normalizedX") || !json.has("normalizedY")) return;

    int button = json.get("button").getAsInt();
    double normX = json.get("normalizedX").getAsDouble();
    double normY = json.get("normalizedY").getAsDouble();

    WebSocketServerHandler.StreamConfig streamConfig = handler.getStreamConfig();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          net.minecraft.client.gui.screens.Screen screen = mc.gui.screen();
          if (screen == null) return;

          int targetWidth = streamConfig.width;
          int targetHeight = streamConfig.height;
          if (targetWidth <= 0 || targetHeight <= 0) return;

          int[] bounds = ScreenHelper.getCropBoundsScreenCoords(screen, targetWidth, targetHeight);
          if (bounds == null) return;

          int cropX = bounds[0];
          int cropY = bounds[1];
          int cropWidth = bounds[2];
          int cropHeight = bounds[3];

          double screenX = cropX + normX * cropWidth;
          double screenY = cropY + normY * cropHeight;

          double guiScale = mc.getWindow().getGuiScale();
          double framebufferX = screenX * guiScale;
          double framebufferY = screenY * guiScale;

          long windowHandle = mc.getWindow().handle();
          glfwSetCursorPos(windowHandle, framebufferX, framebufferY);

          if (mc.mouseHandler != null) {
            MouseHandlerAccessor accessor = (MouseHandlerAccessor) mc.mouseHandler;
            accessor.monkeycraft$setXpos(framebufferX);
            accessor.monkeycraft$setYpos(framebufferY);
          }

          int modifiers = screenShiftActive ? GLFW_MOD_SHIFT : 0;
          MouseButtonEvent mouseEvent =
              new MouseButtonEvent(screenX, screenY, new MouseButtonInfo(button, modifiers));

          if (screen instanceof AbstractContainerScreen<?> containerScreen
              && !containerScreen.getMenu().getCarried().isEmpty()) {
            screen.mouseReleased(mouseEvent);
          } else {
            screen.mouseClicked(mouseEvent, false);
          }
        });
  }

  public void handleScreenHover(JsonObject json) {
    if (!json.has("normalizedX") || !json.has("normalizedY")) return;

    double normX = json.get("normalizedX").getAsDouble();
    double normY = json.get("normalizedY").getAsDouble();

    WebSocketServerHandler.StreamConfig streamConfig = handler.getStreamConfig();

    Minecraft mc = Minecraft.getInstance();
    mc.execute(
        () -> {
          net.minecraft.client.gui.screens.Screen screen = mc.gui.screen();
          if (screen == null) return;

          int targetWidth = streamConfig.width;
          int targetHeight = streamConfig.height;
          if (targetWidth <= 0 || targetHeight <= 0) return;

          int[] bounds = ScreenHelper.getCropBoundsScreenCoords(screen, targetWidth, targetHeight);
          if (bounds == null) return;

          int cropX = bounds[0];
          int cropY = bounds[1];
          int cropWidth = bounds[2];
          int cropHeight = bounds[3];

          double screenX = cropX + normX * cropWidth;
          double screenY = cropY + normY * cropHeight;

          double guiScale = mc.getWindow().getGuiScale();
          double framebufferX = screenX * guiScale;
          double framebufferY = screenY * guiScale;

          long windowHandle = mc.getWindow().handle();
          glfwSetCursorPos(windowHandle, framebufferX, framebufferY);

          if (mc.mouseHandler != null) {
            MouseHandlerAccessor accessor = (MouseHandlerAccessor) mc.mouseHandler;
            accessor.monkeycraft$setXpos(framebufferX);
            accessor.monkeycraft$setYpos(framebufferY);
          }
        });
  }

  public void handleScreenModifier(JsonObject json) {
    if (!json.has("modifier") || !json.has("active")) return;
    String modifier = json.get("modifier").getAsString();
    boolean active = json.get("active").getAsBoolean();

    if ("SHIFT".equals(modifier)) {
      screenShiftActive = active;
    }
  }
}
