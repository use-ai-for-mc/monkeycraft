package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.AllowConnectionsFrom;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.handler.AuthenticationHandler;
import com.chenweikeng.monkeycraft.server.handler.ChatCommandHandler;
import com.chenweikeng.monkeycraft.server.handler.InputHandler;
import com.chenweikeng.monkeycraft.server.handler.ScreenInteractionHandler;
import com.chenweikeng.monkeycraft.server.handler.WorldJoinHandler;
import com.chenweikeng.monkeycraft.utils.CryptoUtils;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonSyntaxException;
import com.mojang.blaze3d.platform.NativeImage;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.util.concurrent.atomic.AtomicBoolean;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

public class WebSocketServerHandler {
  public enum ClientMode {
    STREAMING,
    CHAT,
    MAP
  }

  private static final long QR_TIMEOUT_MS = 2 * 60 * 1000;

  private static final class InstanceHolder {
    static final WebSocketServerHandler INSTANCE = new WebSocketServerHandler();
  }

  private MonkeycraftWebSocketServer server;
  private int currentPort = -1;
  private final AtomicBoolean running = new AtomicBoolean(false);
  private volatile boolean persistent = false;
  private final AtomicBoolean hasEverConnected = new AtomicBoolean(false);
  private volatile long qrDisplayStartTime = 0;
  private static final Gson GSON = new Gson();
  private H264Streamer streamer;
  private final com.chenweikeng.monkeycraft.MapDataHandler mapDataHandler =
      new com.chenweikeng.monkeycraft.MapDataHandler();
  private boolean isStreaming = false;
  private StreamConfig streamConfig = new StreamConfig();
  private boolean isHibernating = false;
  private String hibernationMessage = "";
  private Long pendingTimedNotificationFireAt = null;
  private String pendingTimedNotificationTitle = null;
  private String pendingTimedNotificationBody = null;
  private boolean pendingTimedNotificationSound = true;
  private String pendingTimedNotificationCountDownText = null;

  private boolean turnLeft, turnRight, lookUp, lookDown;
  private boolean isChatSubscribed = false;
  private boolean autoFaceMovement = false;

  private ClientMode clientMode = ClientMode.STREAMING;
  private boolean hasReceivedClientStatus = false;

  private boolean isScreenOpen = false;

  private final InputHandler inputHandler;
  private final ScreenInteractionHandler screenHandler;
  private final ChatCommandHandler chatCommandHandler;
  private final AuthenticationHandler authHandler;
  private final WorldJoinHandler worldJoinHandler;

  private String lastWorldPhase = null;

  public boolean isTurningLeft() {
    return turnLeft;
  }

  public boolean isTurningRight() {
    return turnRight;
  }

  public boolean isLookingUp() {
    return lookUp;
  }

  public boolean isLookingDown() {
    return lookDown;
  }

  public boolean isAutoFaceMovement() {
    return autoFaceMovement;
  }

  public void setTurnLeft(boolean value) {
    turnLeft = value;
  }

  public void setTurnRight(boolean value) {
    turnRight = value;
  }

  public void setLookUp(boolean value) {
    lookUp = value;
  }

  public void setLookDown(boolean value) {
    lookDown = value;
  }

  public boolean isChatSubscribed() {
    return isChatSubscribed;
  }

  public void subscribeChat(WebSocket conn) {
    isChatSubscribed = true;
    com.google.gson.JsonArray cachedMessages = ChatHandler.getInstance().getCachedMessages();
    JsonObject response = new JsonObject();
    response.addProperty("type", "CACHED_CHAT_MESSAGES");
    response.add("messages", cachedMessages);
    conn.send(GSON.toJson(response));
  }

  public void unsubscribeChat() {
    isChatSubscribed = false;
  }

  public boolean isScreenOpen() {
    return isScreenOpen;
  }

  public void updateScreenState(net.minecraft.client.gui.screens.Screen screen) {
    boolean wasOpen = isScreenOpen;

    if (com.chenweikeng.monkeycraft.utils.ScreenHelper.hasSpecialCropping(screen)) {
      isScreenOpen = true;
    } else {
      isScreenOpen = false;
    }

    if (wasOpen != isScreenOpen) {
      sendScreenState();
      if (streamer != null) {
        streamer.resetBackpressure();
      }
    }
  }

  private void sendScreenState() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;

    JsonObject msg = new JsonObject();
    msg.addProperty("type", "SCREEN_STATE");
    msg.addProperty("isOpen", isScreenOpen);
    conn.send(GSON.toJson(msg));
  }

  /** Returns the current session phase: MENU, CONNECTING, or IN_WORLD. */
  private String currentWorldPhase() {
    net.minecraft.client.Minecraft mc = net.minecraft.client.Minecraft.getInstance();
    if (mc.level != null) {
      return "IN_WORLD";
    }
    if (mc.screen instanceof net.minecraft.client.gui.screens.ConnectScreen) {
      return "CONNECTING";
    }
    return "MENU";
  }

  private JsonObject buildWorldState(String phase) {
    net.minecraft.client.Minecraft mc = net.minecraft.client.Minecraft.getInstance();
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "WORLD_STATE");
    msg.addProperty("phase", phase);
    net.minecraft.client.multiplayer.ServerData current = mc.getCurrentServer();
    if (current != null) {
      msg.addProperty("serverName", current.name);
      msg.addProperty("serverAddress", current.ip);
    }
    msg.addProperty("singleplayer", mc.hasSingleplayerServer());
    return msg;
  }

  /**
   * Derives the current session phase and pushes a WORLD_STATE message to the connected app
   * whenever it changes. Must be called on the client thread (e.g. from the client tick).
   */
  public void updateWorldState() {
    String phase = currentWorldPhase();
    if (phase.equals(lastWorldPhase)) {
      return;
    }
    lastWorldPhase = phase;
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    conn.send(GSON.toJson(buildWorldState(phase)));
  }

  public static class StreamConfig {
    public int width = 360;
    public int height = 640;
    public int colorMode = 0;
    public int fps = 10;
  }

  private WebSocketServerHandler() {
    inputHandler = new InputHandler(this);
    screenHandler = new ScreenInteractionHandler(this);
    chatCommandHandler = new ChatCommandHandler(this);
    authHandler = new AuthenticationHandler(this);
    worldJoinHandler = new WorldJoinHandler(this);
  }

  public static WebSocketServerHandler getInstance() {
    return InstanceHolder.INSTANCE;
  }

  public StreamConfig getStreamConfig() {
    return streamConfig;
  }

  public boolean startServer(int port, boolean isAutoLaunch) {
    return startServer(port, isAutoLaunch, false);
  }

  public boolean startServer(int port, boolean isAutoLaunch, boolean persistent) {
    if (running.get()) {
      if (currentPort == port) {
        if (persistent) {
          this.persistent = true;
        }
        return true;
      }
      stopServer();
    }

    if (!isPortAvailable(port)) {
      MonkeycraftClient.LOGGER.warn("Port {} is not available", port);
      return false;
    }

    try {
      server = new MonkeycraftWebSocketServer(port);
      server.setReuseAddr(true);
      server.start();
      currentPort = port;
      running.set(true);
      this.persistent = persistent;

      if (isAutoLaunch && !ModConfig.getInstance().isShowQrCodeWhenAutoLaunch()) {
        hasEverConnected.set(true);
        qrDisplayStartTime = 0;
      } else {
        qrDisplayStartTime = System.currentTimeMillis();
      }

      return true;
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.error("Failed to start WebSocket server on port {}", port, e);
      return false;
    }
  }

  public void stopServer() {
    if (streamer != null) {
      streamer.close();
      streamer = null;
    }
    isStreaming = false;
    hasEverConnected.set(false);
    qrDisplayStartTime = 0;

    if (server != null) {
      try {
        server.stop();
      } catch (Exception e) {
        MonkeycraftClient.LOGGER.error("Error stopping WebSocket server", e);
      } finally {
        server = null;
        currentPort = -1;
        running.set(false);
        persistent = false;
      }
    }
  }

  public boolean isRunning() {
    return running.get();
  }

  public boolean isPersistent() {
    return persistent;
  }

  public boolean hasEverConnected() {
    return hasEverConnected.get();
  }

  public void resetHasEverConnected() {
    hasEverConnected.set(false);
  }

  public void resetQrTimer() {
    qrDisplayStartTime = System.currentTimeMillis();
    hasEverConnected.set(false);
  }

  public boolean isQrVisible() {
    if (!running.get()) return false;
    if (isClientConnected()) return false;
    if (hasEverConnected.get()) return false;
    if (qrDisplayStartTime == 0) return false;
    return System.currentTimeMillis() - qrDisplayStartTime < QR_TIMEOUT_MS;
  }

  private boolean isIpAddressAllowed(InetAddress addr) {
    AllowConnectionsFrom setting = ModConfig.getInstance().getAllowConnectionsFrom();

    if (setting == AllowConnectionsFrom.ANYWHERE) {
      return true;
    }

    byte[] bytes = addr.getAddress();

    if (addr.isLoopbackAddress()) {
      return true;
    }

    if (setting == AllowConnectionsFrom.ONLY_LOCALHOST) {
      return false;
    }

    if (addr.isLinkLocalAddress() || addr.isSiteLocalAddress()) {
      return true;
    }

    if (bytes.length == 4) {
      if (bytes[0] == 10) {
        return true;
      }
      if ((bytes[0] & 0xFF) == 172 && (bytes[1] & 0xFF) >= 16 && (bytes[1] & 0xFF) <= 31) {
        return true;
      }
      if ((bytes[0] & 0xFF) == 192 && (bytes[1] & 0xFF) == 168) {
        return true;
      }
    }

    return false;
  }

  public int getCurrentPort() {
    return currentPort;
  }

  public boolean isClientConnected() {
    if (server == null) return false;
    WebSocket conn = server.authenticatedSession;
    return conn != null && conn.isOpen();
  }

  public boolean isHibernating() {
    return isHibernating;
  }

  public void broadcastFrame(NativeImage image) {
    if (server == null || streamer == null || !hasReceivedClientStatus) {
      image.close();
      return;
    }

    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) {
      isStreaming = false;
      image.close();
      return;
    }

    if ((clientMode == ClientMode.STREAMING || clientMode == ClientMode.MAP)
        && !isHibernating
        && isStreaming) {
      streamer.encodeAndSend(image, conn);
    } else {
      image.close();
    }
  }

  public boolean isStreaming() {
    return isStreaming && server != null && server.authenticatedSession != null;
  }

  public boolean isMapMode() {
    return clientMode == ClientMode.MAP
        && server != null
        && server.authenticatedSession != null
        && hasReceivedClientStatus;
  }

  public void tickMapData() {
    if (!isMapMode()) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    mapDataHandler.tick(conn);
  }

  public void sendTimedNotification(
      Long fireAtEpochMs, String title, String body, boolean sound, String countDownText) {
    if (fireAtEpochMs != null && fireAtEpochMs <= System.currentTimeMillis()) {
      fireAtEpochMs = null;
      title = null;
      body = null;
      countDownText = null;
    }

    pendingTimedNotificationFireAt = fireAtEpochMs;
    pendingTimedNotificationTitle = title;
    pendingTimedNotificationBody = body;
    pendingTimedNotificationSound = sound;
    pendingTimedNotificationCountDownText = countDownText;

    sendServerStatus();
  }

  public void cancelTimedNotification() {
    pendingTimedNotificationFireAt = null;
    pendingTimedNotificationTitle = null;
    pendingTimedNotificationBody = null;
    pendingTimedNotificationSound = true;
    pendingTimedNotificationCountDownText = null;

    sendServerStatus();
  }

  public void sendNudge(String title, String body, boolean sound) {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;

    JsonObject msg = new JsonObject();
    msg.addProperty("type", "NUDGE");
    if (title != null) msg.addProperty("title", title);
    if (body != null) msg.addProperty("body", body);
    msg.addProperty("sound", sound);
    conn.send(GSON.toJson(msg));
  }

  private void sendServerStatus() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    sendServerStatus(conn);
  }

  private void sendServerStatus(WebSocket conn) {
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "SERVER_STATUS");
    msg.addProperty("videoState", isHibernating ? "HIBERNATING" : "ACTIVE");
    if (isHibernating && hibernationMessage != null && !hibernationMessage.isEmpty()) {
      msg.addProperty("message", hibernationMessage);
    }
    if (pendingTimedNotificationFireAt != null) {
      msg.addProperty("timedFireAtEpochMs", pendingTimedNotificationFireAt);
      if (pendingTimedNotificationTitle != null) {
        msg.addProperty("timedTitle", pendingTimedNotificationTitle);
      }
      if (pendingTimedNotificationBody != null) {
        msg.addProperty("timedBody", pendingTimedNotificationBody);
      }
      msg.addProperty("timedSound", pendingTimedNotificationSound);
      if (pendingTimedNotificationCountDownText != null) {
        msg.addProperty("timedCountDownText", pendingTimedNotificationCountDownText);
      }
    } else {
      msg.add("timedFireAtEpochMs", null);
    }
    conn.send(GSON.toJson(msg));
  }

  public void startHibernation(String message) {
    setHibernationMessage(message);
  }

  public void endHibernation() {
    isHibernating = false;
    hibernationMessage = "";
    isStreaming = true;
    sendServerStatus();
  }

  public void setHibernationMessage(String message) {
    isHibernating = true;
    hibernationMessage = message == null ? "" : message;
    isStreaming = false;
    sendServerStatus();
  }

  public void disconnectClient() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "DISCONNECT");
    msg.addProperty("reason", "server_disconnect");
    conn.send(GSON.toJson(msg));
    conn.close();
  }

  public void sendChatMessage(String jsonMessage) {
    if (server == null || !isChatSubscribed) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    conn.send(jsonMessage);
  }

  public void enterChatMode() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    isStreaming = false;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "CHAT_MODE_STARTED");
    conn.send(GSON.toJson(msg));
  }

  public void exitChatMode() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "CHAT_MODE_ENDED");
    conn.send(GSON.toJson(msg));
  }

  public void sendPostAuthState(WebSocket conn) {
    if (isHibernating) {
      JsonObject hibernationStatus = new JsonObject();
      hibernationStatus.addProperty("type", "HIBERNATION_STATUS");
      hibernationStatus.addProperty("active", true);
      hibernationStatus.addProperty("message", hibernationMessage);
      conn.send(GSON.toJson(hibernationStatus));
    }

    if (pendingTimedNotificationFireAt != null) {
      JsonObject timedStatus = new JsonObject();
      timedStatus.addProperty("type", "TIMED_STATUS");
      timedStatus.addProperty("fireAtEpochMs", pendingTimedNotificationFireAt);
      if (pendingTimedNotificationTitle != null) {
        timedStatus.addProperty("title", pendingTimedNotificationTitle);
      }
      if (pendingTimedNotificationBody != null) {
        timedStatus.addProperty("body", pendingTimedNotificationBody);
      }
      timedStatus.addProperty("sound", pendingTimedNotificationSound);
      if (pendingTimedNotificationCountDownText != null) {
        timedStatus.addProperty("countDownText", pendingTimedNotificationCountDownText);
      }
      conn.send(GSON.toJson(timedStatus));
    }

    JsonObject screenStatus = new JsonObject();
    screenStatus.addProperty("type", "SCREEN_STATE");
    screenStatus.addProperty("isOpen", isScreenOpen);
    conn.send(GSON.toJson(screenStatus));

    net.minecraft.client.Minecraft.getInstance()
        .execute(
            () -> {
              if (conn.isOpen()) {
                conn.send(GSON.toJson(buildWorldState(currentWorldPhase())));
              }
            });
  }

  private void handleMapInteract(JsonObject json) {
    if (!json.has("entityId")) return;
    int entityId = json.get("entityId").getAsInt();

    net.minecraft.client.Minecraft mc = net.minecraft.client.Minecraft.getInstance();
    mc.execute(
        () -> {
          if (mc.player == null || mc.level == null) return;
          net.minecraft.world.entity.Entity target = mc.level.getEntity(entityId);
          if (target == null) return;

          target.interact(mc.player, net.minecraft.world.InteractionHand.MAIN_HAND);
        });
  }

  private boolean isPortAvailable(int port) {
    try (ServerSocket socket = new ServerSocket(port)) {
      socket.setReuseAddress(true);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public int startServerWithPortRange(int preferredPort, boolean isAutoLaunch) {
    return startServerWithPortRange(preferredPort, isAutoLaunch, false);
  }

  public int startServerWithPortRange(int preferredPort, boolean isAutoLaunch, boolean persistent) {
    int startPort = Math.max(9600, Math.min(9700, preferredPort));
    for (int port = startPort; port <= 9700; port++) {
      if (startServer(port, isAutoLaunch, persistent)) {
        return port;
      }
    }
    for (int port = 9600; port < startPort; port++) {
      if (startServer(port, isAutoLaunch, persistent)) {
        return port;
      }
    }
    return -1;
  }

  private class MonkeycraftWebSocketServer extends WebSocketServer {
    private WebSocket authenticatedSession;

    public MonkeycraftWebSocketServer(int port) {
      super(new InetSocketAddress(port));
    }

    @Override
    public void onOpen(WebSocket conn, ClientHandshake handshake) {
      InetSocketAddress remoteAddr = conn.getRemoteSocketAddress();
      if (remoteAddr != null) {
        InetAddress clientAddr = remoteAddr.getAddress();
        if (!isIpAddressAllowed(clientAddr)) {
          MonkeycraftClient.LOGGER.warn(
              "Connection rejected from {} (not allowed by allowConnectionsFrom setting)",
              clientAddr);
          JsonObject error = new JsonObject();
          error.addProperty("type", "ERROR");
          error.addProperty("message", "Connection not allowed from this address");
          conn.send(GSON.toJson(error));
          conn.close();
          return;
        }
      }

      String serverSalt = CryptoUtils.generateSalt();
      conn.setAttachment(serverSalt);
      JsonObject hello = new JsonObject();
      hello.addProperty("type", "HELLO");
      hello.addProperty("salt", serverSalt);
      conn.send(GSON.toJson(hello));
    }

    @Override
    public void onClose(WebSocket conn, int code, String reason, boolean remote) {
      if (conn == authenticatedSession) {
        authenticatedSession = null;
        isStreaming = false;
        isChatSubscribed = false;
        clientMode = ClientMode.STREAMING;
        hasReceivedClientStatus = false;
        mapDataHandler.reset();
        com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi.DISCONNECTION.invoker().onDisconnected();
      }
    }

    @Override
    public void onMessage(WebSocket conn, String message) {
      try {
        JsonObject json = GSON.fromJson(message, JsonObject.class);
        if (!json.has("type")) return;

        String type = json.get("type").getAsString();

        if ("AUTH".equals(type)) {
          authHandler.handleAuth(
              conn,
              json,
              authenticatedSession,
              authenticated -> {
                authenticatedSession = authenticated;
                hasEverConnected.set(true);
              });
        } else {
          if (conn != authenticatedSession) {
            sendError(conn, "Unauthorized");
            conn.close();
          } else {
            switch (type) {
              case "CLIENT_STATUS" -> handleClientStatus(conn, json);
              case "INPUT" -> inputHandler.handleInput(json);
              case "LOOK_DELTA" -> inputHandler.handleLookDelta(conn, json);
              case "GET_PLAYER_POSE" -> inputHandler.handleGetPlayerPose(conn);
              case "ACK" -> {
                if (streamer != null) streamer.ack();
              }
              case "RUN_COMMAND" -> chatCommandHandler.handleRunCommand(conn, json);
              case "CLICK" -> inputHandler.handleClick(json);
              case "HOTBAR_SELECT" -> inputHandler.handleHotbarSelect(json);
              case "REQUEST_KEYFRAME" -> {
                if (streamer != null) streamer.resetBackpressure();
              }
              case "SEND_CHAT" -> chatCommandHandler.handleSendChat(conn, json);
              case "ENTER_CHAT" -> chatCommandHandler.handleEnterChat(conn);
              case "EXIT_CHAT" -> chatCommandHandler.handleExitChat(conn);
              case "SUBSCRIBE_CHAT" -> chatCommandHandler.handleSubscribeChat(conn);
              case "UNSUBSCRIBE_CHAT" -> chatCommandHandler.handleUnsubscribeChat();
              case "PING" -> sendServerStatus(conn);
              case "HEARTBEAT" -> {
                JsonObject ack = new JsonObject();
                ack.addProperty("type", "HEARTBEAT_ACK");
                conn.send(GSON.toJson(ack));
              }
              case "SCREEN_TAP" -> screenHandler.handleScreenTap(json);
              case "SCREEN_KEY" -> screenHandler.handleScreenKey(json);
              case "SCREEN_CLICK" -> screenHandler.handleScreenClick(json);
              case "SCREEN_HOVER" -> screenHandler.handleScreenHover(json);
              case "SCREEN_MODIFIER" -> screenHandler.handleScreenModifier(json);
              case "MAP_INTERACT" -> handleMapInteract(json);
              case "LIST_SERVERS" -> worldJoinHandler.handleListServers(conn);
              case "JOIN_SERVER" -> worldJoinHandler.handleJoinServer(conn, json);
              case "LEAVE_WORLD" -> worldJoinHandler.handleLeaveWorld(conn);
              case "INFO" -> {}
              default ->
                  MonkeycraftClient.LOGGER.debug("Received authenticated message: {}", message);
            }
          }
        }
      } catch (JsonSyntaxException e) {
        sendError(conn, "Invalid JSON");
      }
    }

    private void handleClientStatus(WebSocket conn, JsonObject json) {
      String modeStr = json.has("mode") ? json.get("mode").getAsString() : "STREAMING";
      if ("CHAT".equals(modeStr)) {
        clientMode = ClientMode.CHAT;
      } else if ("MAP".equals(modeStr)) {
        clientMode = ClientMode.MAP;
      } else {
        clientMode = ClientMode.STREAMING;
      }
      hasReceivedClientStatus = true;

      if (json.has("autoFaceMovement")) {
        autoFaceMovement = json.get("autoFaceMovement").getAsBoolean();
      }

      if (clientMode == ClientMode.STREAMING && json.has("width") && json.has("height")) {
        int requestedWidth = json.get("width").getAsInt();
        int requestedHeight = json.get("height").getAsInt();
        int colorMode = json.has("colorMode") ? json.get("colorMode").getAsInt() : 0;
        int fps = json.has("fps") ? json.get("fps").getAsInt() : 10;

        if (fps < 1) fps = 1;
        if (fps > 20) fps = 20;

        int targetWidth = requestedWidth;
        int targetHeight = requestedHeight;
        int maxDim = 1920;
        if (targetWidth > maxDim) targetWidth = maxDim;
        if (targetHeight > maxDim) targetHeight = maxDim;
        if (targetWidth < 2) targetWidth = 2;
        if (targetHeight < 2) targetHeight = 2;

        targetWidth = (targetWidth / 2) * 2;
        targetHeight = (targetHeight / 2) * 2;

        if (streamer == null
            || streamConfig.width != targetWidth
            || streamConfig.height != targetHeight
            || streamConfig.colorMode != colorMode
            || streamConfig.fps != fps) {

          if (streamer != null) streamer.close();

          streamConfig.width = targetWidth;
          streamConfig.height = targetHeight;
          streamConfig.colorMode = colorMode;
          streamConfig.fps = fps;

          streamer = new H264Streamer(targetWidth, targetHeight, colorMode, fps);
        }

        if (streamer != null) {
          streamer.resetBackpressure();
        }

        isStreaming = !isHibernating;
      } else if (clientMode == ClientMode.MAP) {
        // MAP mode uses the video streaming pipeline with top-down camera
        if (json.has("width") && json.has("height")) {
          int requestedWidth = json.get("width").getAsInt();
          int requestedHeight = json.get("height").getAsInt();
          int colorMode = json.has("colorMode") ? json.get("colorMode").getAsInt() : 0;
          int fps = json.has("fps") ? json.get("fps").getAsInt() : 10;

          if (fps < 1) fps = 1;
          if (fps > 20) fps = 20;

          int targetWidth = Math.max(2, Math.min(1920, requestedWidth));
          int targetHeight = Math.max(2, Math.min(1920, requestedHeight));
          targetWidth = (targetWidth / 2) * 2;
          targetHeight = (targetHeight / 2) * 2;

          if (streamer == null
              || streamConfig.width != targetWidth
              || streamConfig.height != targetHeight
              || streamConfig.colorMode != colorMode
              || streamConfig.fps != fps) {
            if (streamer != null) streamer.close();
            streamConfig.width = targetWidth;
            streamConfig.height = targetHeight;
            streamConfig.colorMode = colorMode;
            streamConfig.fps = fps;
            streamer = new H264Streamer(targetWidth, targetHeight, colorMode, fps);
          }
          if (streamer != null) streamer.resetBackpressure();
        }
        isStreaming = true;
        mapDataHandler.reset();
      } else if (clientMode == ClientMode.CHAT) {
        isStreaming = false;
      }

      sendServerStatus(conn);
    }

    private void sendError(WebSocket conn, String message) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "ERROR");
      response.addProperty("message", message);
      conn.send(GSON.toJson(response));
    }

    @Override
    public void onError(WebSocket conn, Exception ex) {
      MonkeycraftClient.LOGGER.error("WebSocket error", ex);
    }

    @Override
    public void onStart() {}
  }
}
