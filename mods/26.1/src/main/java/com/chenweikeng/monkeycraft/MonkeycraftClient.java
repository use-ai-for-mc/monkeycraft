package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.config.NetworkScope;
import com.chenweikeng.monkeycraft.config.ConfigScreenFactory;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketApiProvider;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.ui.PasswordQrOverlay;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.chenweikeng.monkeycraft.utils.ScreenHelper;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApiRegistration;
import com.mojang.brigadier.CommandDispatcher;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandRegistrationCallback;
import net.fabricmc.fabric.api.client.command.v2.ClientCommands;
import net.fabricmc.fabric.api.client.command.v2.FabricClientCommandSource;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.ChatFormatting;
import net.minecraft.client.Minecraft;
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
  public static volatile long lastLocalKeyInputTime = 0;
  private static final long LOCAL_INPUT_GRACE_PERIOD_MS = 10000;

  public static boolean hasRecentLocalKeyInput() {
    if (lastLocalKeyInputTime == 0) return false;
    return System.currentTimeMillis() - lastLocalKeyInputTime < LOCAL_INPUT_GRACE_PERIOD_MS;
  }

  private int rightPressHoldTicks = 0;
  private static final int RELEASE_MOUSE_HOLD_TICKS = 8;
  private final FrameCaptureManager frameCaptureManager = new FrameCaptureManager();
  private final CameraController cameraController = new CameraController();

  @Override
  public void onInitializeClient() {
    LOGGER.info("Monkeycraft client initializing...");

    MonkeycraftApiRegistration.register(new WebSocketApiProvider());

    ClientCommandRegistrationCallback.EVENT.register(this::registerCommands);
    registerLifecycleEvents();
    registerConnectionEvents();
    registerTickEvents();
    PasswordQrOverlay.register();
  }

  private void registerTickEvents() {
    ClientTickEvents.END_CLIENT_TICK.register(
        client -> {
          boolean connectedNow = WebSocketServerHandler.getInstance().isClientConnected();
          WebSocketServerHandler.getInstance().updateWorldState();

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
            if (client.screen instanceof net.minecraft.client.gui.screens.ChatScreen) {
              client.gui.getChat().restoreChatScreen();
            }
            client.setScreen(null);
          }

          if (WebSocketServerHandler.getInstance().isStreaming()) {
            cameraController.tick(client);
            frameCaptureManager.tick(client);
          }

          if (WebSocketServerHandler.getInstance().isMapMode()) {
            // Lock player facing north so WASD maps to cardinal directions
            if (client.player != null) {
              client.player.setYRot(180.0f); // 180 = facing north
              client.player.setXRot(0.0f); // level pitch
            }
            frameCaptureManager.tick(client);
            WebSocketServerHandler.getInstance().tickMapData();
          }
        });
  }

  private void registerLifecycleEvents() {
    ClientLifecycleEvents.CLIENT_STARTED.register(
        client -> {
          ModConfig config = ModConfig.getInstance();
          if (config.isEnabled() && config.isStartServerAtLaunch()) {
            LOGGER.info("Starting Monkeycraft server at launch...");
            int actualPort =
                WebSocketServerHandler.getInstance()
                    .startServerWithPortRange(config.getPort(), true, true);
            if (actualPort > 0) {
              LOGGER.info("Monkeycraft server started at launch on port {}", actualPort);
            } else {
              LOGGER.warn("Failed to start server at launch (no available port 9600-9700)");
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
            int actualPort = startServerWithPortRange(config.getPort(), true);
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
          WebSocketServerHandler ws = WebSocketServerHandler.getInstance();
          if (ws.isRunning() && !ws.isPersistent()) {
            LOGGER.info("Stopping Monkeycraft server due to disconnection...");
            stopServer();
          }
        });
  }

  private void registerCommands(
      CommandDispatcher<FabricClientCommandSource> dispatcher,
      net.minecraft.commands.CommandBuildContext registryAccess) {
    dispatcher.register(
        ClientCommands.literal("monkey")
            .executes(
                context -> {
                  WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
                  if (handler.isRunning()) {
                    handler.resetQrTimer();
                  }
                  sendHelpMessage();
                  return 1;
                })
            .then(
                ClientCommands.literal("config")
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
                ClientCommands.literal("start")
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
                            WebSocketServerHandler.getInstance().resetQrTimer();
                            printLocalIps(actualPort);
                          } else {
                            sendMonkeyMessage(Component.translatable("monkeycraft.server.failed"));
                          }
                          return 1;
                        }))
            .then(
                ClientCommands.literal("stop")
                    .executes(
                        context -> {
                          stopServer();
                          return 1;
                        })));
  }

  public static int startServerWithPortRange(int preferredPort) {
    return startServerWithPortRange(preferredPort, false);
  }

  public static int startServerWithPortRange(int preferredPort, boolean isAutoLaunch) {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    return handler.startServerWithPortRange(preferredPort, isAutoLaunch);
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
                                        "https://github.com/use-ai-for-mc/monkeycraft/wiki/Solutions-for-remote-connections"))))));
    if (ModConfig.getInstance().getNetworkScope() == NetworkScope.ANYONE) {
      sendSystemMessage(
          Component.literal("MONKEY: ")
              .withStyle(ChatFormatting.RED, ChatFormatting.BOLD)
              .append(
                  Component.translatable("monkeycraft.server.allow_anywhere_warning")
                      .withStyle(Style.EMPTY.withColor(ChatFormatting.RED).withBold(false))));
    }
  }

  public static void stopServer() {
    WebSocketServerHandler.getInstance().stopServer();
    sendMonkeyMessage(Component.translatable("monkeycraft.server.stopped"));
  }

  public static void sendSystemMessage(Component message) {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player != null) {
      mc.player.sendSystemMessage(message);
    }
  }

  public static void sendMonkeyMessage(Component message) {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player != null) {
      Component prefix =
          Component.literal("MONKEY: ").withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD);
      mc.player.sendSystemMessage(
          prefix
              .copy()
              .append(
                  message
                      .copy()
                      .withStyle(Style.EMPTY.withColor(ChatFormatting.WHITE).withBold(false))));
    }
  }

  public static void sendHelpMessage() {
    Minecraft mc = Minecraft.getInstance();
    if (mc.player == null) return;

    Component prefix =
        Component.literal("MONKEY: ").withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD);

    mc.player.sendSystemMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey start"))
            .append(Component.literal(" - Start server").withStyle(ChatFormatting.WHITE)));
    mc.player.sendSystemMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey stop"))
            .append(Component.literal(" - Stop server").withStyle(ChatFormatting.WHITE)));
    mc.player.sendSystemMessage(
        prefix
            .copy()
            .append(clickableCommand("/monkey config"))
            .append(Component.literal(" - Open settings").withStyle(ChatFormatting.WHITE)));

    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (handler.isRunning()) {
      if (!handler.isClientConnected()) {
        handler.resetHasEverConnected();
      }
      mc.player.sendSystemMessage(
          prefix
              .copy()
              .append(
                  Component.literal("Server running on port " + handler.getCurrentPort())
                      .withStyle(ChatFormatting.GREEN)));
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
