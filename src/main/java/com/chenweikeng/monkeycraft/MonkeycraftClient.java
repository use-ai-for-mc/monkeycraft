package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.config.ConfigScreenFactory;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.mixin.GameRendererAccessor;
import com.chenweikeng.monkeycraft.mixin.GuiRendererAccessor;
import com.chenweikeng.monkeycraft.server.WebSocketApiProvider;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.ui.PasswordQrOverlay;
import com.chenweikeng.monkeycraft.utils.ImageUtils;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.chenweikeng.monkeycraft.utils.ScreenHelper;
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
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.Style;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec2;
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
  public static volatile long lastLocalKeyInputTime = 0;
  private static final long LOCAL_INPUT_GRACE_PERIOD_MS = 10000;

  public static boolean hasRecentLocalKeyInput() {
    if (lastLocalKeyInputTime == 0) return false;
    return System.currentTimeMillis() - lastLocalKeyInputTime < LOCAL_INPUT_GRACE_PERIOD_MS;
  }

  private int rightPressHoldTicks = 0;
  private static final int RELEASE_MOUSE_HOLD_TICKS = 8;
  private long lastCaptureTime = 0;
  private int lastFrameNumber = -1;

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
            rightPressHoldTicks++;
            if (rightPressHoldTicks >= RELEASE_MOUSE_HOLD_TICKS) {
              client.mouseHandler.releaseMouse();
              rightPressHoldTicks = 0;
            }
          } else {
            rightPressHoldTicks = 0;
          }

          WebSocketServerHandler.getInstance().updateScreenState(client.screen);

          if (WebSocketServerHandler.getInstance().isStreaming()
              && client.screen != null
              && !ScreenHelper.shouldKeepScreen(client.screen)
              && !hasRecentLocalKeyInput()) {
            client.gui.getChat().restoreChatScreen();
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

              // Auto-face movement direction
              if (handler.isAutoFaceMovement()
                  && !handler.isTurningLeft()
                  && !handler.isTurningRight()
                  && !handler.isLookingUp()
                  && !handler.isLookingDown()) {
                Vec2 moveVec = client.player.input.getMoveVector();
                if (moveVec.lengthSquared() > 0.01f) {
                  float targetYawOffset =
                      (float) (Math.atan2(-moveVec.x, moveVec.y) * (180.0 / Math.PI));
                  float targetYaw = client.player.getYRot() + targetYawOffset;
                  float yawDiff = Mth.wrapDegrees(targetYaw - client.player.getYRot());
                  float turnAmount = yawDiff * 0.15f;
                  client.player.turn(turnAmount, 0);
                }
              }
            }

            // Get dynamic FPS config
            WebSocketServerHandler.StreamConfig streamConfig =
                WebSocketServerHandler.getInstance().getStreamConfig();
            long interval = 1000 / Math.max(1, streamConfig.fps);

            long now = System.currentTimeMillis();
            if (now - lastCaptureTime >= interval) {
              GameRenderer gameRenderer = client.gameRenderer;
              if (gameRenderer == null) {
                return;
              }
              var guiRenderer = ((GameRendererAccessor) gameRenderer).monkeycraft$getGuiRenderer();
              if (guiRenderer == null) {
                return;
              }
              int currentFrameNumber =
                  ((GuiRendererAccessor) guiRenderer).monkeycraft$getFrameNumber();
              if (currentFrameNumber == lastFrameNumber) {
                return;
              }
              lastFrameNumber = currentFrameNumber;
              lastCaptureTime = now;
              try {
                Screenshot.takeScreenshot(
                    client.getMainRenderTarget(),
                    (image) -> {
                      try {
                        WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
                        WebSocketServerHandler.StreamConfig config = handler.getStreamConfig();

                        if (handler.isScreenOpen() && client.mouseHandler != null) {
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

                        if (handler.isScreenOpen()
                            && ScreenHelper.needsLetterboxing(client.screen)) {
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

                          if (handler.isScreenOpen() && cropBounds != null) {
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

                        com.mojang.blaze3d.platform.NativeImage cropped =
                            ImageUtils.crop(image, cropX, cropY, cropWidth, cropHeight);
                        try {
                          com.mojang.blaze3d.platform.NativeImage resized =
                              useLetterbox
                                  ? ImageUtils.resizeWithLetterbox(
                                      cropped, resizeWidth, resizeHeight)
                                  : ImageUtils.resize(cropped, resizeWidth, resizeHeight);
                          handler.broadcastFrame(resized);
                        } finally {
                          cropped.close();
                        }
                      } finally {
                        image.close();
                      }
                    });
              } catch (Exception e) {
                LOGGER.info("Error capturing stream frame", e);
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
                        })));
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
    sendMonkeyMessage(
        Component.literal("For remote connection, please refer to ")
            .append(
                Component.literal("this wiki")
                    .withStyle(
                        Style.EMPTY
                            .withColor(ChatFormatting.BLUE)
                            .withBold(true)
                            .withClickEvent(
                                new ClickEvent.OpenUrl(
                                    java.net.URI.create(
                                        "https://github.com/weikengchen/monkeycraft/wiki/Solutions-for-remote-connections"))))));
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
      mc.player.displayClientMessage(
          prefix
              .copy()
              .append(
                  message
                      .copy()
                      .withStyle(Style.EMPTY.withColor(ChatFormatting.WHITE).withBold(false))),
          false);
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
            .append(Component.literal(" - Start server").withStyle(ChatFormatting.WHITE)),
        false);
    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey stop"))
            .append(Component.literal(" - Stop server").withStyle(ChatFormatting.WHITE)),
        false);
    mc.player.displayClientMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey config"))
            .append(Component.literal(" - Open settings").withStyle(ChatFormatting.WHITE)),
        false);

    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (handler.isRunning()) {
      if (!handler.isClientConnected()) {
        handler.resetHasEverConnected();
      }
      mc.player.displayClientMessage(
          prefix
              .copy()
              .append(
                  Component.literal("Server running on port " + handler.getCurrentPort())
                      .withStyle(ChatFormatting.GREEN)),
          false);
      printLocalIps(handler.getCurrentPort());
    }
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
