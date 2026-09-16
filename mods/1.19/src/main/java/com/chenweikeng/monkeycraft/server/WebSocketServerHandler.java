package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.config.NetworkScope;
import com.chenweikeng.monkeycraft.config.TailscaleAccess;
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
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
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
  private static final int WEBSOCKET_START_TIMEOUT_MS = 2000;
  private static final int WEBSOCKET_STOP_TIMEOUT_MS = 2000;
  private static final int WEBSOCKET_TERMINATION_GRACE_MS = 250;
  private static final String SHUTDOWN_REASON = "Monkeycraft shutting down";

  private enum LifecycleState {
    STOPPED,
    STARTING,
    RUNNING,
    STOPPING,
    SHUTTING_DOWN,
    SHUTDOWN
  }

  private static final class InstanceHolder {
    static final WebSocketServerHandler INSTANCE = new WebSocketServerHandler();
  }

  private final Object lifecycleLock = new Object();
  private final BooleanSupplier showQrCodeWhenAutoLaunch;
  private volatile MonkeycraftWebSocketServer server;
  private volatile int currentPort = -1;
  private final AtomicBoolean running = new AtomicBoolean(false);
  private final AtomicBoolean cleanupInProgress = new AtomicBoolean(false);
  private final AtomicBoolean shutdownRequested = new AtomicBoolean(false);
  private volatile LifecycleState lifecycleState = LifecycleState.STOPPED;
  private volatile boolean persistent = false;
  private final AtomicBoolean hasEverConnected = new AtomicBoolean(false);
  private volatile long qrDisplayStartTime = 0;
  private final AtomicReference<PairingSession> pairingSession = new AtomicReference<>();
  private volatile long lastTailscaleHintAt = 0;
  private static final Gson GSON = new Gson();
  private volatile H264Streamer streamer;
  private final com.chenweikeng.monkeycraft.MapDataHandler mapDataHandler =
      new com.chenweikeng.monkeycraft.MapDataHandler();
  private volatile boolean isStreaming = false;
  private StreamConfig streamConfig = new StreamConfig();
  private boolean isHibernating = false;
  private String hibernationMessage = "";
  private Long pendingTimedNotificationFireAt = null;
  private String pendingTimedNotificationTitle = null;
  private String pendingTimedNotificationBody = null;
  private boolean pendingTimedNotificationSound = true;
  private String pendingTimedNotificationCountDownText = null;

  private boolean turnLeft, turnRight, lookUp, lookDown;
  private volatile boolean isChatSubscribed = false;
  private boolean autoFaceMovement = false;

  private volatile ClientMode clientMode = ClientMode.STREAMING;
  private volatile boolean hasReceivedClientStatus = false;

  private volatile boolean isScreenOpen = false;

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
    public boolean dataSaver = false;
  }

  private WebSocketServerHandler() {
    this(() -> ModConfig.getInstance().isShowQrCodeWhenAutoLaunch());
  }

  WebSocketServerHandler(BooleanSupplier showQrCodeWhenAutoLaunch) {
    this.showQrCodeWhenAutoLaunch = showQrCodeWhenAutoLaunch;
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
    boolean restart;
    synchronized (lifecycleLock) {
      if (shutdownRequested.get()) {
        MonkeycraftClient.LOGGER.warn(
            "Ignoring WebSocket server start on port {} because Monkeycraft is shutting down",
            port);
        return false;
      }
      restart = lifecycleState == LifecycleState.RUNNING && currentPort != port;
      if (lifecycleState == LifecycleState.RUNNING && !restart) {
        if (persistent) {
          this.persistent = true;
        }
        return true;
      }
      if (!restart && lifecycleState != LifecycleState.STOPPED) {
        MonkeycraftClient.LOGGER.warn(
            "Ignoring WebSocket server start on port {} while lifecycle state is {}",
            port,
            lifecycleState);
        return false;
      }
    }

    if (restart) {
      stopServer();
      return startServer(port, isAutoLaunch, persistent);
    }

    MonkeycraftWebSocketServer newServer;
    synchronized (lifecycleLock) {
      if (shutdownRequested.get() || lifecycleState != LifecycleState.STOPPED) return false;
      if (!isPortAvailable(port)) {
        MonkeycraftClient.LOGGER.warn("Port {} is not available", port);
        return false;
      }
      lifecycleState = LifecycleState.STARTING;
      newServer = new MonkeycraftWebSocketServer(port);
      newServer.setReuseAddr(true);
      newServer.setDaemon(true);
      server = newServer;
    }

    try {
      newServer.start();
      if (!newServer.awaitStartup(WEBSOCKET_START_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
        throw new IllegalStateException(
            "WebSocket server did not start within " + WEBSOCKET_START_TIMEOUT_MS + " ms");
      }
      Exception startupFailure = newServer.startupFailure();
      if (!newServer.isStartupComplete() || startupFailure != null) {
        throw new IllegalStateException("WebSocket server failed during startup", startupFailure);
      }
      synchronized (lifecycleLock) {
        if (shutdownRequested.get()) return false;
        currentPort = port;
        running.set(true);
        this.persistent = persistent;
        lifecycleState = LifecycleState.RUNNING;
      }

      if (isAutoLaunch && !showQrCodeWhenAutoLaunch.getAsBoolean()) {
        hasEverConnected.set(true);
        qrDisplayStartTime = 0;
      } else {
        qrDisplayStartTime = System.currentTimeMillis();
      }

      return true;
    } catch (Exception e) {
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      MonkeycraftClient.LOGGER.error("Failed to start WebSocket server on port {}", port, e);
      synchronized (lifecycleLock) {
        if (server == newServer) server = null;
        resetServerState();
        lifecycleState =
            shutdownRequested.get() ? LifecycleState.SHUTTING_DOWN : LifecycleState.STOPPING;
      }
      ShutdownSequence.run(
          MonkeycraftClient.LOGGER,
          new ShutdownSequence.Step(
              "failed WebSocket server", () -> stopWebSocketServer(newServer)));
      synchronized (lifecycleLock) {
        lifecycleState = shutdownRequested.get() ? LifecycleState.SHUTDOWN : LifecycleState.STOPPED;
      }
      return false;
    }
  }

  public void stopServer() {
    stopOwnedResources(false);
  }

  public void shutdown() {
    shutdownRequested.set(true);
    stopOwnedResources(true);
  }

  private void stopOwnedResources(boolean terminal) {
    if (!cleanupInProgress.compareAndSet(false, true)) return;
    MonkeycraftWebSocketServer serverToStop;
    H264Streamer streamerToStop;
    try {
      synchronized (lifecycleLock) {
        lifecycleState =
            terminal || shutdownRequested.get()
                ? LifecycleState.SHUTTING_DOWN
                : LifecycleState.STOPPING;
        running.set(false);
        serverToStop = server;
        server = null;
        streamerToStop = streamer;
        streamer = null;
        pairingSession.set(null);
        resetServerState();
      }
      ShutdownSequence.run(
          MonkeycraftClient.LOGGER,
          new ShutdownSequence.Step("WebSocket server", () -> stopWebSocketServer(serverToStop)),
          new ShutdownSequence.Step(
              "H264 streamer",
              () -> {
                if (streamerToStop != null) streamerToStop.close();
              }),
          new ShutdownSequence.Step(
              "input state",
              () -> {
                turnLeft = false;
                turnRight = false;
                lookUp = false;
                lookDown = false;
              }),
          new ShutdownSequence.Step("map capture state", mapDataHandler::reset));
    } finally {
      synchronized (lifecycleLock) {
        lifecycleState = shutdownRequested.get() ? LifecycleState.SHUTDOWN : LifecycleState.STOPPED;
      }
      cleanupInProgress.set(false);
    }
  }

  private void stopWebSocketServer(MonkeycraftWebSocketServer serverToStop) throws Exception {
    if (serverToStop == null) return;
    for (WebSocket connection : serverToStop.getConnections()) {
      try {
        connection.close(1001, SHUTDOWN_REASON);
      } catch (Exception e) {
        MonkeycraftClient.LOGGER.warn("Failed to close a Monkeycraft client connection", e);
      }
    }
    try {
      serverToStop.stop(WEBSOCKET_STOP_TIMEOUT_MS, SHUTDOWN_REASON);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw e;
    }
    if (!serverToStop.awaitTermination(WEBSOCKET_TERMINATION_GRACE_MS, TimeUnit.MILLISECONDS)) {
      MonkeycraftClient.LOGGER.warn(
          "WebSocket server did not terminate within {} ms; selector, workers, or connection-lost checker may still be winding down. All WebSocket threads are daemon threads and will not block JVM shutdown.",
          WEBSOCKET_STOP_TIMEOUT_MS + WEBSOCKET_TERMINATION_GRACE_MS);
    }
  }

  private void resetServerState() {
    currentPort = -1;
    running.set(false);
    persistent = false;
    isStreaming = false;
    isChatSubscribed = false;
    hasReceivedClientStatus = false;
    clientMode = ClientMode.STREAMING;
    hasEverConnected.set(false);
    qrDisplayStartTime = 0;
    lastWorldPhase = null;
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

  public void beginPairing(WebSocket conn) {
    PairingSession previous = pairingSession.getAndSet(null);
    if (previous != null && previous.conn() != conn && previous.conn().isOpen()) {
      JsonObject busy = new JsonObject();
      busy.addProperty("type", "PAIR_FAILED");
      busy.addProperty("message", "Replaced by another pairing attempt");
      previous.conn().send(GSON.toJson(busy));
      previous.conn().close();
    }
    PairingSession session = new PairingSession(conn);
    pairingSession.set(session);
    JsonObject waiting = new JsonObject();
    waiting.addProperty("type", "PAIR_WAITING");
    waiting.addProperty("code", session.code());
    waiting.addProperty("ttlMs", PairingSession.TTL_MS);
    conn.send(GSON.toJson(waiting));
    Minecraft mc = Minecraft.getInstance();
    if (mc != null) {
      mc.execute(
          () ->
              MonkeycraftClient.sendMonkeyMessage(
                  Component.literal(
                      "Phone pairing code "
                          + PairingSession.displayCode(session.code())
                          + ". Run /monkey accept "
                          + session.code())));
    }
  }

  public boolean acceptPairing(String typedCode) {
    PairingSession session = pairingSession.get();
    if (session == null || session.isExpired() || !session.conn().isOpen()) {
      pairingSession.compareAndSet(session, null);
      return false;
    }
    if (!session.matches(typedCode)) {
      return false;
    }
    if (!pairingSession.compareAndSet(session, null)) {
      return false;
    }
    authHandler.completePairing(session);
    return true;
  }

  public PairingSession currentPairing() {
    PairingSession session = pairingSession.get();
    if (session != null && (session.isExpired() || !session.conn().isOpen())) {
      pairingSession.compareAndSet(session, null);
      return null;
    }
    return session;
  }

  private void clearPairingIf(WebSocket conn) {
    PairingSession session = pairingSession.get();
    if (session != null && session.conn() == conn) {
      pairingSession.compareAndSet(session, null);
    }
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
    return com.chenweikeng.monkeycraft.utils.NetworkUtils.isConnectionAllowed(
        ModConfig.getInstance().getNetworkScope(),
        ModConfig.getInstance().getTailscaleAccess(),
        com.chenweikeng.monkeycraft.utils.NetworkUtils.isTailscaleRunning(),
        addr);
  }

  // True for IPv4 in 100.64.0.0/10 (RFC 6598 CGNAT; the range Tailscale uses).
  private static boolean isTailscaleRange(InetAddress addr) {
    byte[] bytes = addr.getAddress();
    return bytes.length == 4
        && (bytes[0] & 0xFF) == 100
        && (bytes[1] & 0xFF) >= 64
        && (bytes[1] & 0xFF) <= 127;
  }

  private void maybeNotifyPossiblyTailscaleRejected(java.net.InetAddress clientAddr) {
    if (clientAddr == null || !isTailscaleRange(clientAddr)) return;

    // Only worth a hint when the user could fix it: Tailscale access is on the
    // auto-detect default but no daemon was found. (ALWAYS wouldn't reject;
    // NEVER and ANYONE are deliberate choices.)
    if (ModConfig.getInstance().getTailscaleAccess() != TailscaleAccess.IF_DETECTED) return;
    if (ModConfig.getInstance().getNetworkScope() == NetworkScope.ANYONE) return;
    if (com.chenweikeng.monkeycraft.utils.NetworkUtils.isTailscaleRunning()) return;

    long now = System.currentTimeMillis();
    if (now - lastTailscaleHintAt < 60_000L) return;
    lastTailscaleHintAt = now;

    String ipStr = clientAddr.getHostAddress();
    net.minecraft.client.Minecraft.getInstance()
        .execute(
            () ->
                MonkeycraftClient.sendMonkeyMessage(
                    net.minecraft.network.chat.Component.translatable(
                        "monkeycraft.connection.rejected_possibly_tailscale", ipStr)));
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
    H264Streamer localStreamer = streamer;
    if (server == null || localStreamer == null || !hasReceivedClientStatus) {
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
      localStreamer.encodeAndSend(image, conn);
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
    inputHandler.releaseAll();
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
    private volatile WebSocket authenticatedSession;
    private final CountDownLatch startupLatch = new CountDownLatch(1);
    private final CountDownLatch terminationLatch = new CountDownLatch(1);
    private final AtomicReference<Exception> startupFailure = new AtomicReference<>();
    private final AtomicBoolean startupComplete = new AtomicBoolean(false);

    public MonkeycraftWebSocketServer(int port) {
      super(new InetSocketAddress(port));
    }

    @Override
    public void run() {
      try {
        super.run();
      } finally {
        startupLatch.countDown();
        terminationLatch.countDown();
      }
    }

    private boolean awaitStartup(long timeout, TimeUnit unit) throws InterruptedException {
      return startupLatch.await(timeout, unit);
    }

    private boolean awaitTermination(long timeout, TimeUnit unit) throws InterruptedException {
      return terminationLatch.await(timeout, unit);
    }

    private Exception startupFailure() {
      return startupFailure.get();
    }

    private boolean isStartupComplete() {
      return startupComplete.get();
    }

    @Override
    public void onOpen(WebSocket conn, ClientHandshake handshake) {
      if (!isAcceptingMessages()) {
        conn.close(1001, SHUTDOWN_REASON);
        return;
      }
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
          maybeNotifyPossiblyTailscaleRejected(clientAddr);
          return;
        }
      }

      String serverSalt = CryptoUtils.generateSalt();
      conn.setAttachment(serverSalt);
      JsonObject hello = new JsonObject();
      hello.addProperty("type", "HELLO");
      hello.addProperty("salt", serverSalt);
      hello.addProperty("pairing", true);
      conn.send(GSON.toJson(hello));
    }

    @Override
    public void onClose(WebSocket conn, int code, String reason, boolean remote) {
      clearPairingIf(conn);
      if (conn == authenticatedSession) {
        authenticatedSession = null;
        isStreaming = false;
        isChatSubscribed = false;
        clientMode = ClientMode.STREAMING;
        hasReceivedClientStatus = false;
        mapDataHandler.reset();
        inputHandler.releaseAll();
        com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi.DISCONNECTION.invoker().onDisconnected();
      }
    }

    @Override
    public void onMessage(WebSocket conn, String message) {
      if (!isAcceptingMessages()) {
        conn.close(1001, SHUTDOWN_REASON);
        return;
      }
      try {
        JsonObject json = GSON.fromJson(message, JsonObject.class);
        if (!json.has("type")) return;

        String type = json.get("type").getAsString();

        if ("AUTH".equals(type)) {
          synchronized (this) {
            authHandler.handleAuth(
                conn,
                json,
                authenticatedSession,
                authenticated -> {
                  authenticatedSession = authenticated;
                  hasEverConnected.set(true);
                });
          }
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
              case "GET_PLAYER_LIST" -> worldJoinHandler.handleGetPlayerList(conn);
              case "GET_PLAYER_COUNT" -> worldJoinHandler.handleGetPlayerCount(conn);
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
      if (!isAcceptingMessages()) return;
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

        boolean dataSaver = json.has("dataSaver") && json.get("dataSaver").getAsBoolean();

        if (!configureStreamer(targetWidth, targetHeight, colorMode, fps, dataSaver)) return;

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

          boolean dataSaver = json.has("dataSaver") && json.get("dataSaver").getAsBoolean();
          if (!configureStreamer(targetWidth, targetHeight, colorMode, fps, dataSaver)) return;
        }
        if (!isAcceptingMessages()) return;
        isStreaming = true;
        mapDataHandler.reset();
      } else if (clientMode == ClientMode.CHAT) {
        isStreaming = false;
      }

      sendServerStatus(conn);
    }

    private boolean isAcceptingMessages() {
      return !shutdownRequested.get() && lifecycleState == LifecycleState.RUNNING && server == this;
    }

    private boolean configureStreamer(
        int width, int height, int colorMode, int fps, boolean dataSaver) {
      H264Streamer previous = null;
      H264Streamer configured;
      synchronized (lifecycleLock) {
        if (!isAcceptingMessages()) return false;
        if (streamer == null
            || streamConfig.width != width
            || streamConfig.height != height
            || streamConfig.colorMode != colorMode
            || streamConfig.fps != fps
            || streamConfig.dataSaver != dataSaver) {
          previous = streamer;
          streamConfig.width = width;
          streamConfig.height = height;
          streamConfig.colorMode = colorMode;
          streamConfig.fps = fps;
          streamConfig.dataSaver = dataSaver;
          streamer = new H264Streamer(width, height, colorMode, fps, dataSaver);
        }
        configured = streamer;
      }
      if (previous != null) previous.close();
      if (configured != null) configured.resetBackpressure();
      return true;
    }

    private void sendError(WebSocket conn, String message) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "ERROR");
      response.addProperty("message", message);
      conn.send(GSON.toJson(response));
    }

    @Override
    public void onError(WebSocket conn, Exception ex) {
      if (!startupComplete.get()) {
        startupFailure.compareAndSet(null, ex);
        startupLatch.countDown();
      }
      MonkeycraftClient.LOGGER.error("WebSocket error", ex);
    }

    @Override
    public void onStart() {
      startupComplete.set(true);
      startupLatch.countDown();
    }
  }
}
