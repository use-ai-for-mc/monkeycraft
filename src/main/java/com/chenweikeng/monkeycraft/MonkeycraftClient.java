package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.config.ConfigScreenFactory;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.mixin.MouseHandlerInvoker;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.ImageUtils;
import com.mojang.brigadier.CommandDispatcher;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandManager;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandRegistrationCallback;
import net.fabricmc.fabric.api.client.command.v2.FabricClientCommandSource;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.client.input.MouseButtonInfo;
import net.minecraft.network.chat.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MonkeycraftClient implements ClientModInitializer {
  public static final String MOD_ID = "monkeycraft";
  public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);
  public static volatile boolean wasConnectedToClient = false;
  public static volatile boolean isConnectedToClient = false;
  public static volatile boolean automaticallyReleasedCursor = false;
  public static volatile int pendingRightClickReleaseTicks = 0;
  private long lastCaptureTime = 0;

  @Override
  public void onInitializeClient() {
    LOGGER.info("Monkeycraft client initializing...");

    ClientCommandRegistrationCallback.EVENT.register(this::registerCommands);
    registerConnectionEvents();
    registerTickEvents();
  }

  private void registerTickEvents() {
    ClientTickEvents.END_CLIENT_TICK.register(
        client -> {
          if (pendingRightClickReleaseTicks > 0) {
            pendingRightClickReleaseTicks -= 1;
            if (pendingRightClickReleaseTicks == 0) {
              try {
                long windowHandle = client.getWindow().handle();
                MouseHandlerInvoker mouse = (MouseHandlerInvoker) (Object) client.mouseHandler;
                mouse.monkeycraft$onButton(windowHandle, new MouseButtonInfo(1, 0), 0);
              } catch (Exception e) {
                LOGGER.warn("Failed to release right click", e);
              }
            }
          }

          boolean connectedNow = WebSocketServerHandler.getInstance().isClientConnected();
          if (!wasConnectedToClient && connectedNow) {
            isConnectedToClient = true;
            if (client.mouseHandler.isMouseGrabbed()) {
              client.mouseHandler.releaseMouse();
              automaticallyReleasedCursor = true;
            }
          }
          if (!connectedNow) {
            isConnectedToClient = false;
            automaticallyReleasedCursor = false;
          }
          wasConnectedToClient = connectedNow;

          if (automaticallyReleasedCursor
              && client.mouseHandler.isRightPressed()
              && client.mouseHandler.isMouseGrabbed()) {
            client.mouseHandler.releaseMouse();
          }

          if (isConnectedToClient && client.screen != null) {
            client.setScreen(null);
          }

          if (WebSocketServerHandler.getInstance().isStreaming()) {
            // Apply rotation from input
            if (client.player != null) {
              WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
              float turnSpeed = 5.0f;
              if (handler.isTurningLeft()) client.player.turn(-turnSpeed, 0);
              if (handler.isTurningRight()) client.player.turn(turnSpeed, 0);
              if (handler.isLookingUp()) client.player.turn(0, -turnSpeed);
              if (handler.isLookingDown()) client.player.turn(0, turnSpeed);
            }

            // Get dynamic FPS config
            WebSocketServerHandler.StreamConfig streamConfig =
                WebSocketServerHandler.getInstance().getStreamConfig();
            long interval = 1000 / Math.max(1, streamConfig.fps);

            long now = System.currentTimeMillis();
            if (now - lastCaptureTime >= interval) {
              lastCaptureTime = now;
              long captureStart = System.nanoTime();
              try {
                Screenshot.takeScreenshot(
                    client.getMainRenderTarget(),
                    (image) -> {
                      long captureEnd = System.nanoTime();
                      long captureMs = (captureEnd - captureStart) / 1_000_000;
                      try {
                        WebSocketServerHandler.StreamConfig config =
                            WebSocketServerHandler.getInstance().getStreamConfig();

                        int targetWidth = config.width;
                        int targetHeight = config.height;

                        double targetAspect = (double) targetWidth / (double) targetHeight;
                        int cropWidth = image.getWidth();
                        int cropHeight = image.getHeight();

                        if (cropWidth > cropHeight * targetAspect) {
                          cropWidth = (int) (cropHeight * targetAspect);
                        } else {
                          cropHeight = (int) (cropWidth / targetAspect);
                        }

                        int startX = (image.getWidth() - cropWidth) / 2;
                        int startY = (image.getHeight() - cropHeight) / 2;

                        com.mojang.blaze3d.platform.NativeImage cropped =
                            ImageUtils.crop(image, startX, startY, cropWidth, cropHeight);
                        try {
                          com.mojang.blaze3d.platform.NativeImage resized =
                              ImageUtils.resize(cropped, targetWidth, targetHeight);

                          long processEnd = System.nanoTime();
                          long processMs = (processEnd - captureEnd) / 1_000_000;

                          if (System.currentTimeMillis() % 60000 < 100) {
                            LOGGER.info("Capture: {}ms, Resize/Crop: {}ms", captureMs, processMs);
                          }

                          WebSocketServerHandler.getInstance().broadcastFrame(resized);
                        } finally {
                          cropped.close();
                        }
                      } finally {
                        image.close();
                      }
                    });
              } catch (Exception e) {
                LOGGER.error("Error capturing stream frame", e);
              }
            }
          }
        });
  }

  private void registerConnectionEvents() {
    ClientPlayConnectionEvents.JOIN.register(
        (handler, sender, client) -> {
          ModConfig config = ModConfig.getInstance();
          if (config.isEnabled() && config.isAutoLaunch()) {
            LOGGER.info("Auto-launching Monkeycraft server...");
            startServer(config.getPort());
            sendSystemMessage(Component.translatable("monkeycraft.server.autolaunch"));
          }
        });

    ClientPlayConnectionEvents.DISCONNECT.register(
        (handler, client) -> {
          if (WebSocketServerHandler.getInstance().isRunning()) {
            LOGGER.info("Stopping Monkeycraft server due to disconnection...");
            stopServer();
          }
        });
  }

  private void registerCommands(
      CommandDispatcher<FabricClientCommandSource> dispatcher,
      net.minecraft.commands.CommandBuildContext registryAccess) {
    dispatcher.register(
        ClientCommandManager.literal("monkeycraft")
            .executes(
                context -> {
                  sendSystemMessage(Component.translatable("monkeycraft.command.help"));
                  return 1;
                })
            .then(
                ClientCommandManager.literal("config")
                    .executes(
                        context -> {
                          Minecraft.getInstance()
                              .execute(
                                  () -> {
                                    Minecraft.getInstance()
                                        .setScreen(
                                            ConfigScreenFactory.createConfigScreen(
                                                Minecraft.getInstance().screen));
                                  });
                          return 1;
                        }))
            .then(
                ClientCommandManager.literal("start")
                    .executes(
                        context -> {
                          ModConfig config = ModConfig.getInstance();
                          if (!config.isEnabled()) {
                            sendSystemMessage(
                                Component.translatable("monkeycraft.server.disabled"));
                            return 0;
                          }
                          startServer(config.getPort());
                          return 1;
                        }))
            .then(
                ClientCommandManager.literal("stop")
                    .executes(
                        context -> {
                          stopServer();
                          return 1;
                        })));
  }

  public static void startServer(int port) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    boolean success = handler.startServer(port);
    if (success) {
      sendSystemMessage(Component.translatable("monkeycraft.server.started", port));
    } else {
      sendSystemMessage(Component.translatable("monkeycraft.server.port_unavailable", port));
    }
  }

  public static void stopServer() {
    WebSocketServerHandler.getInstance().stopServer();
    sendSystemMessage(Component.translatable("monkeycraft.server.stopped"));
  }

  public static void sendSystemMessage(Component message) {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player != null) {
      mc.player.displayClientMessage(message, false);
    }
  }
}
