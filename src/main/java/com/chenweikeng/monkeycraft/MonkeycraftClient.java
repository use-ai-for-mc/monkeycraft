package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.config.ConfigScreenFactory;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketApiProvider;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.ui.PasswordQrOverlay;
import com.chenweikeng.monkeycraft.utils.ImageUtils;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApiRegistration;
import com.mojang.brigadier.CommandDispatcher;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandManager;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandRegistrationCallback;
import net.fabricmc.fabric.api.client.command.v2.FabricClientCommandSource;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.ChatFormatting;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.Style;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MonkeycraftClient implements ClientModInitializer {
  public static final String MOD_ID = "monkeycraft";
  public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);
  public static volatile boolean wasConnectedToClient = false;
  public static volatile boolean isConnectedToClient = false;
  public static volatile boolean automaticallyReleasedCursor = false;
  public static volatile int pendingMouseReleaseTicks = 0;
  public static volatile int pendingMouseButton = 0;
  private long lastCaptureTime = 0;

  @Override
  public void onInitializeClient() {
    LOGGER.info("Monkeycraft client initializing...");

    MonkeycraftApiRegistration.register(new WebSocketApiProvider());

    ClientCommandRegistrationCallback.EVENT.register(this::registerCommands);
    registerConnectionEvents();
    registerTickEvents();
    PasswordQrOverlay.register();
  }

  private void registerTickEvents() {
    ClientTickEvents.END_CLIENT_TICK.register(
        client -> {
          boolean connectedNow = WebSocketServerHandler.getInstance().isClientConnected();
          if (connectedNow && client.options.keyDrop.isDown()) {
            WebSocketServerHandler.getInstance().disconnectClient();
          }

          if (pendingMouseReleaseTicks > 0) {
            pendingMouseReleaseTicks -= 1;
            if (pendingMouseReleaseTicks == 0) {
              try {
                if (pendingMouseButton == 1) client.options.keyUse.setDown(false);
                if (pendingMouseButton == 0) client.options.keyAttack.setDown(false);
              } catch (Exception e) {
                LOGGER.warn("Failed to release mouse button", e);
              }
            }
          }

          if (!wasConnectedToClient && connectedNow) {
            isConnectedToClient = true;
            if (client.mouseHandler.isMouseGrabbed()) {
              client.mouseHandler.releaseMouse();
            }
            automaticallyReleasedCursor = true;
          }
          if (!connectedNow) {
            isConnectedToClient = false;
            automaticallyReleasedCursor = false;
          }
          wasConnectedToClient = connectedNow;

          if (connectedNow
              && client.mouseHandler.isRightPressed()
              && client.mouseHandler.isMouseGrabbed()) {
            client.mouseHandler.releaseMouse();
          }

          if (WebSocketServerHandler.getInstance().isStreaming() && client.screen != null) {
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
            int actualPort = startServerWithPortRange(config.getPort());
            if (actualPort > 0) {
              sendMonkeyMessage(Component.translatable("monkeycraft.server.autolaunch"));
              printLocalIps(actualPort);
            } else {
              sendMonkeyMessage(
                  Component.literal("Failed to start server (no available port 9600-9700)"));
            }
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
        ClientCommandManager.literal("monkey")
            .executes(
                context -> {
                  sendHelpMessage();
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
                            sendMonkeyMessage(
                                Component.translatable("monkeycraft.server.disabled"));
                            return 0;
                          }
                          int actualPort = startServerWithPortRange(config.getPort());
                          if (actualPort > 0) {
                            printLocalIps(actualPort);
                          } else {
                            sendMonkeyMessage(Component.translatable("monkeycraft.server.failed"));
                          }
                          return 1;
                        }))
            .then(
                ClientCommandManager.literal("stop")
                    .executes(
                        context -> {
                          stopServer();
                          return 1;
                        }))
            .then(
                ClientCommandManager.literal("ip")
                    .executes(
                        context -> {
                          WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
                          if (!handler.isRunning()) {
                            sendMonkeyMessage(
                                Component.literal("Server is not running. Use ")
                                    .append(clickableCommand("/monkey start"))
                                    .append(Component.literal(" first.")));
                            return 0;
                          }
                          printLocalIps(handler.getCurrentPort());
                          return 1;
                        })));
  }

  public static void startServer(int port) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    boolean success = handler.startServer(port);
    if (success) {
      sendMonkeyMessage(Component.translatable("monkeycraft.server.started", port));
    } else {
      sendMonkeyMessage(Component.translatable("monkeycraft.server.port_unavailable", port));
    }
  }

  public static int startServerWithPortRange(int preferredPort) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    return handler.startServerWithPortRange(preferredPort);
  }

  public static void printLocalIps(int port) {
    java.util.List<String> ips = NetworkUtils.getLocalIpAddressesWithPort(port);
    if (ips.isEmpty()) {
      sendMonkeyMessage(Component.literal("No local IP addresses found"));
    } else {
      sendMonkeyMessage(Component.literal("Local IP addresses:"));
      for (String ip : ips) {
        sendMonkeyMessage(Component.literal("  " + ip));
      }
    }
  }

  public static void stopServer() {
    WebSocketServerHandler.getInstance().stopServer();
    sendMonkeyMessage(Component.translatable("monkeycraft.server.stopped"));
  }

  public static void sendSystemMessage(Component message) {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player != null) {
      mc.player.displayClientMessage(message, false);
    }
  }

  public static void sendMonkeyMessage(Component message) {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player != null) {
      Component prefix =
          Component.literal("MONKEY: ").withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD);
      mc.player.displayClientMessage(prefix.copy().append(message), false);
    }
  }

  public static void sendHelpMessage() {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player == null) return;

    Component prefix =
        Component.literal("MONKEY: ").withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD);

    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey start"))
            .append(Component.literal(" - Start server\n").withStyle(ChatFormatting.WHITE)),
        false);
    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey stop"))
            .append(Component.literal(" - Stop server\n").withStyle(ChatFormatting.WHITE)),
        false);
    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey config"))
            .append(Component.literal(" - Open settings\n").withStyle(ChatFormatting.WHITE)),
        false);
    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey ip"))
            .append(Component.literal(" - Show local IPs").withStyle(ChatFormatting.WHITE)),
        false);
  }

  public static Component clickableCommand(String command) {
    return Component.literal(command)
        .withStyle(
            Style.EMPTY
                .withColor(ChatFormatting.YELLOW)
                .withUnderlined(true)
                .withClickEvent(new ClickEvent.SuggestCommand(command))
                .withHoverEvent(
                    new HoverEvent.ShowText(Component.literal("Click to use command"))));
  }
}
