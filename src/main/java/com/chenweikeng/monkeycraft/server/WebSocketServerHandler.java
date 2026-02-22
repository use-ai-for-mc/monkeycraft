package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.utils.CryptoUtils;
import com.chenweikeng.monkeycraft_api.v1.CommandExecutionResult;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonSyntaxException;
import com.mojang.blaze3d.platform.NativeImage;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.util.concurrent.atomic.AtomicBoolean;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

public class WebSocketServerHandler {
  private static WebSocketServerHandler instance;
  private MonkeycraftWebSocketServer server;
  private int currentPort = -1;
  private final AtomicBoolean running = new AtomicBoolean(false);
  private final AtomicBoolean hasEverConnected = new AtomicBoolean(false);
  private static final Gson GSON = new Gson();
  private H264Streamer streamer;
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

  public boolean isChatSubscribed() {
    return isChatSubscribed;
  }

  public void subscribeChat(WebSocket conn) {
    isChatSubscribed = true;
    JsonArray cachedMessages = ChatHandler.getInstance().getCachedMessages();
    JsonObject response = new JsonObject();
    response.addProperty("type", "CACHED_CHAT_MESSAGES");
    response.add("messages", cachedMessages);
    conn.send(GSON.toJson(response));
  }

  public void unsubscribeChat() {
    isChatSubscribed = false;
  }

  public static class StreamConfig {
    public int width = 360;
    public int height = 640;
    public int colorMode = 0;
    public int fps = 10;
  }

  private WebSocketServerHandler() {}

  public static WebSocketServerHandler getInstance() {
    if (instance == null) {
      instance = new WebSocketServerHandler();
    }
    return instance;
  }

  public StreamConfig getStreamConfig() {
    return streamConfig;
  }

  public boolean startServer(int port) {
    if (running.get()) {
      if (currentPort == port) {
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

    if (server != null) {
      try {
        server.stop();
      } catch (Exception e) {
        MonkeycraftClient.LOGGER.error("Error stopping WebSocket server", e);
      } finally {
        server = null;
        currentPort = -1;
        running.set(false);
      }
    }
  }

  public boolean isRunning() {
    return running.get();
  }

  public boolean hasEverConnected() {
    return hasEverConnected.get();
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
    if (server != null && isStreaming && streamer != null) {
      WebSocket conn = server.authenticatedSession;
      if (conn != null && conn.isOpen()) {
        streamer.encodeAndSend(image, conn);
      } else {
        // Stop streaming if client disconnected
        isStreaming = false;
        image.close();
      }
    } else {
      image.close();
    }
  }

  public boolean isStreaming() {
    return isStreaming && server != null && server.authenticatedSession != null;
  }

  public void sendTimedNotification(
      Long fireAtEpochMs, String title, String body, boolean sound, String countDownText) {
    // Skip if fireAtEpochMs is in the past or now
    if (fireAtEpochMs != null && fireAtEpochMs <= System.currentTimeMillis()) {
      fireAtEpochMs = null;
      title = null;
      body = null;
      countDownText = null;
    }

    // Store state
    pendingTimedNotificationFireAt = fireAtEpochMs;
    pendingTimedNotificationTitle = title;
    pendingTimedNotificationBody = body;
    pendingTimedNotificationSound = sound;
    pendingTimedNotificationCountDownText = countDownText;

    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;

    JsonObject msg = new JsonObject();
    msg.addProperty("type", "TIMED_STATUS");
    if (fireAtEpochMs != null) {
      msg.addProperty("fireAtEpochMs", fireAtEpochMs);
    } else {
      msg.add("fireAtEpochMs", null);
    }
    if (title != null) msg.addProperty("title", title);
    if (body != null) msg.addProperty("body", body);
    msg.addProperty("sound", sound);
    if (countDownText != null) msg.addProperty("countDownText", countDownText);
    conn.send(GSON.toJson(msg));
  }

  public void cancelTimedNotification() {
    // Clear stored state
    pendingTimedNotificationFireAt = null;
    pendingTimedNotificationTitle = null;
    pendingTimedNotificationBody = null;
    pendingTimedNotificationSound = true;
    pendingTimedNotificationCountDownText = null;

    sendTimedNotification(null, null, null, false, null);
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

  private void sendHibernationStatus() {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "HIBERNATION_STATUS");
    msg.addProperty("active", isHibernating);
    if (isHibernating) {
      msg.addProperty("message", hibernationMessage);
    }
    conn.send(GSON.toJson(msg));
  }

  public void startHibernation(String message) {
    isHibernating = true;
    hibernationMessage = message == null ? "" : message;
    isStreaming = false;
    sendHibernationStatus();
  }

  public void endHibernation() {
    isHibernating = false;
    hibernationMessage = "";
    sendHibernationStatus();
  }

  public void setHibernationMessage(String message) {
    if (!isHibernating) return;
    hibernationMessage = message == null ? "" : message;
    sendHibernationStatus();
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
    if (server == null) return;
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

  private boolean isPortAvailable(int port) {
    try (ServerSocket socket = new ServerSocket(port)) {
      socket.setReuseAddress(true);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public int startServerWithPortRange(int preferredPort) {
    int startPort = Math.max(9600, Math.min(9700, preferredPort));
    for (int port = startPort; port <= 9700; port++) {
      if (startServer(port)) {
        return port;
      }
    }
    for (int port = 9600; port < startPort; port++) {
      if (startServer(port)) {
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
        MonkeycraftApi.DISCONNECTION.invoker().onDisconnected();
      }
    }

    @Override
    public void onMessage(WebSocket conn, String message) {
      try {
        JsonObject json = GSON.fromJson(message, JsonObject.class);
        if (!json.has("type")) return;

        String type = json.get("type").getAsString();

        if ("AUTH".equals(type)) {
          handleAuth(conn, json);
        } else {
          if (conn != authenticatedSession) {
            sendError(conn, "Unauthorized");
            conn.close();
          } else {
            if ("START_STREAM".equals(type)) {
              handleStartStream(conn, json);
            } else if ("STOP_STREAM".equals(type)) {
              handleStopStream(conn);
            } else if ("INPUT".equals(type)) {
              handleInput(json);
            } else if ("LOOK_DELTA".equals(type)) {
              handleLookDelta(conn, json);
            } else if ("GET_PLAYER_POSE".equals(type)) {
              handleGetPlayerPose(conn);
            } else if ("ACK".equals(type)) {
              if (streamer != null) streamer.ack();
            } else if ("RUN_COMMAND".equals(type)) {
              handleRunCommand(conn, json);
            } else if ("CLICK".equals(type)) {
              handleClick(json);
            } else if ("HOTBAR_SELECT".equals(type)) {
              handleHotbarSelect(json);
            } else if ("REQUEST_KEYFRAME".equals(type)) {
              handleRequestKeyframe();
            } else if ("SEND_CHAT".equals(type)) {
              handleSendChat(conn, json);
            } else if ("ENTER_CHAT".equals(type)) {
              handleEnterChat(conn);
            } else if ("EXIT_CHAT".equals(type)) {
              handleExitChat(conn);
            } else if ("SUBSCRIBE_CHAT".equals(type)) {
              handleSubscribeChat(conn);
            } else if ("UNSUBSCRIBE_CHAT".equals(type)) {
              handleUnsubscribeChat();
            } else if ("PING".equals(type)) {
              handlePing(conn);
            } else {
              MonkeycraftClient.LOGGER.debug("Received authenticated message: {}", message);
            }
          }
        }
      } catch (JsonSyntaxException e) {
        sendError(conn, "Invalid JSON");
      }
    }

    private void handleClick(JsonObject json) {
      int button = json.has("button") ? json.get("button").getAsInt() : 0;
      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            try {
              if (MonkeycraftClient.pendingMouseReleaseTicks > 0) {
                if (MonkeycraftClient.pendingMouseButton == 1) mc.options.keyUse.setDown(false);
                if (MonkeycraftClient.pendingMouseButton == 0) mc.options.keyAttack.setDown(false);
                MonkeycraftClient.pendingMouseReleaseTicks = 0;
              }

              if (button == 1) mc.options.keyUse.setDown(true);
              if (button == 0) mc.options.keyAttack.setDown(true);

              MonkeycraftClient.pendingMouseButton = button;
              MonkeycraftClient.pendingMouseReleaseTicks = 2;
            } catch (Exception e) {
              MonkeycraftClient.LOGGER.warn("Failed to synthesize click", e);
            }
          });
    }

    private void handleHotbarSelect(JsonObject json) {
      if (!json.has("slot")) return;
      int slot = json.get("slot").getAsInt();
      if (slot < 0) slot = 0;
      if (slot > 8) slot = 8;

      final int selectedSlot = slot;
      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            if (mc.player == null) return;
            try {
              mc.player.getInventory().setSelectedSlot(selectedSlot);
            } catch (Exception e) {
              MonkeycraftClient.LOGGER.warn("Failed to set hotbar slot", e);
            }
          });
    }

    private void handleRunCommand(WebSocket conn, JsonObject json) {
      if (!json.has("command")) return;
      String raw = json.get("command").getAsString();
      if (raw == null) return;
      raw = raw.trim();
      if (raw.isEmpty()) return;
      if (!raw.startsWith("/")) return;
      final String command = raw;
      final String cmd = raw.substring(1);

      ModConfig config = ModConfig.getInstance();

      CommandExecutionResult apiResult =
          MonkeycraftApi.COMMAND_EXECUTION.invoker().onCommandExecution(command);

      if (apiResult == CommandExecutionResult.DENY || config.isCommandDenied(command)) {
        sendCommandDenied(conn, command);
        return;
      }

      if (apiResult != CommandExecutionResult.ALLOW) {
        if (config.isCommandAllowed(command)) {
          // Allowed by allowlist
        } else if (config.isCommandPermittedByDefault()) {
          // Allowed by default behavior
        } else {
          sendCommandDenied(conn, command);
          return;
        }
      }

      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            try {
              if (mc.player != null && mc.player.connection != null) {
                mc.player.connection.sendCommand(cmd);
              } else if (mc.getConnection() != null) {
                mc.getConnection().sendCommand(cmd);
              }
            } catch (Exception e) {
              MonkeycraftClient.LOGGER.warn("Failed to run command {}", command, e);
            }
          });
    }

    private void sendCommandDenied(WebSocket conn, String command) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "COMMAND_DENIED");
      response.addProperty("command", command);
      conn.send(GSON.toJson(response));
    }

    private void handleRequestKeyframe() {
      if (streamer != null) {
        streamer.resetBackpressure();
      }
    }

    private void handleSendChat(WebSocket conn, JsonObject json) {
      if (!json.has("message")) return;
      String message = json.get("message").getAsString();
      if (message == null || message.trim().isEmpty()) return;
      if (message.startsWith("/")) {
        JsonObject response = new JsonObject();
        response.addProperty("type", "CHAT_DENIED");
        response.addProperty("reason", "Commands must use RUN_COMMAND");
        conn.send(GSON.toJson(response));
        return;
      }

      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            boolean success = ChatHandler.getInstance().handleOutgoingChat(message);
            if (!success) {
              JsonObject response = new JsonObject();
              response.addProperty("type", "CHAT_DENIED");
              response.addProperty("reason", "Failed to send message");
              conn.send(GSON.toJson(response));
            }
          });
    }

    private void handleEnterChat(WebSocket conn) {
      enterChatMode();
    }

    private void handleExitChat(WebSocket conn) {
      exitChatMode();
    }

    private void handleSubscribeChat(WebSocket conn) {
      subscribeChat(conn);
    }

    private void handleUnsubscribeChat() {
      unsubscribeChat();
    }

    private void handlePing(WebSocket conn) {
      sendHibernationStatus();

      JsonObject timedStatus = new JsonObject();
      timedStatus.addProperty("type", "TIMED_STATUS");
      if (pendingTimedNotificationFireAt != null) {
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
      } else {
        timedStatus.add("fireAtEpochMs", null);
      }
      conn.send(GSON.toJson(timedStatus));
    }

    private void handleInput(JsonObject json) {
      if (!json.has("key") || !json.has("pressed")) return;

      String key = json.get("key").getAsString();
      boolean pressed = json.get("pressed").getAsBoolean();

      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            KeyMapping binding = null;
            switch (key) {
              case "W":
                binding = mc.options.keyUp;
                break;
              case "A":
                binding = mc.options.keyLeft;
                break;
              case "S":
                binding = mc.options.keyDown;
                break;
              case "D":
                binding = mc.options.keyRight;
                break;
              case "SPACE":
                binding = mc.options.keyJump;
                break;
              case "SHIFT":
                binding = mc.options.keyShift;
                break;
              case "LEFT":
                turnLeft = pressed;
                break;
              case "RIGHT":
                turnRight = pressed;
                break;
              case "UP":
                lookUp = pressed;
                break;
              case "DOWN":
                lookDown = pressed;
                break;
            }

            if (binding != null) {
              binding.setDown(pressed);
            }
          });
    }

    private void handleLookDelta(WebSocket conn, JsonObject json) {
      if (!json.has("yaw") || !json.has("pitch")) return;

      float yawDelta = json.get("yaw").getAsFloat();
      float pitchDelta = json.get("pitch").getAsFloat();

      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            if (mc.player == null) return;
            float newYaw = mc.player.getYRot() + yawDelta;
            float newPitch = mc.player.getXRot() + pitchDelta;
            if (newPitch > 90.0f) newPitch = 90.0f;
            if (newPitch < -90.0f) newPitch = -90.0f;
            mc.player.setYRot(newYaw);
            mc.player.setXRot(newPitch);
            JsonObject response = new JsonObject();
            response.addProperty("type", "PLAYER_POSE");
            response.addProperty("yaw", mc.player.getYRot());
            response.addProperty("pitch", mc.player.getXRot());
            conn.send(GSON.toJson(response));
          });
    }

    private void handleGetPlayerPose(WebSocket conn) {
      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            if (mc.player == null) return;
            JsonObject response = new JsonObject();
            response.addProperty("type", "PLAYER_POSE");
            response.addProperty("yaw", mc.player.getYRot());
            response.addProperty("pitch", mc.player.getXRot());
            conn.send(GSON.toJson(response));
          });
    }

    private void handleStartStream(WebSocket conn, JsonObject json) {
      if (isHibernating) {
        sendError(conn, "Hibernating");
        return;
      }
      int colorMode = 0;
      int fps = 20;
      int requestedWidth;
      int requestedHeight;

      if (!json.has("width") || !json.has("height")) {
        sendError(conn, "Missing width/height");
        return;
      }
      requestedWidth = json.get("width").getAsInt();
      requestedHeight = json.get("height").getAsInt();
      if (json.has("colorMode")) {
        colorMode = json.get("colorMode").getAsInt();
      }
      if (json.has("fps")) {
        fps = json.get("fps").getAsInt();
        if (fps < 1) fps = 1;
        if (fps > 20) fps = 20;
      }

      int targetWidth = requestedWidth;
      int targetHeight = requestedHeight;
      int maxDim = 1920;
      if (targetWidth > maxDim) targetWidth = maxDim;
      if (targetHeight > maxDim) targetHeight = maxDim;
      if (targetWidth < 2) targetWidth = 2;
      if (targetHeight < 2) targetHeight = 2;

      // Ensure even dimensions
      targetWidth = (targetWidth / 2) * 2;
      targetHeight = (targetHeight / 2) * 2;

      // Recreate streamer if needed
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
      isStreaming = true;
      sendResponse(conn, "STREAM_STARTED", true, "Streaming started");
    }

    private void handleStopStream(WebSocket conn) {
      isStreaming = false;
      sendResponse(conn, "STREAM_STOPPED", true, "Streaming stopped");
    }

    private void handleAuth(WebSocket conn, JsonObject json) {
      String serverSalt = conn.getAttachment();
      if (serverSalt == null) {
        conn.close();
        return;
      }

      if (!json.has("salt") || !json.has("signature")) {
        sendAuthResponse(conn, false, "Missing salt or signature");
        conn.close();
        return;
      }

      String clientSalt = json.get("salt").getAsString();
      String clientSignature = json.get("signature").getAsString();
      String password = ModConfig.getInstance().getPassword();

      String expectedSignature = CryptoUtils.computeHmac(password, serverSalt + clientSalt);

      if (expectedSignature.equals(clientSignature)) {
        if (authenticatedSession != null && authenticatedSession != conn) {
          if (authenticatedSession.isOpen()) {
            sendAuthResponse(authenticatedSession, false, "Logged in from another location");
            authenticatedSession.close();
          }
        }
        authenticatedSession = conn;
        hasEverConnected.set(true);

        String serverSignature = CryptoUtils.computeHmac(password, clientSalt + serverSalt);
        JsonObject response = new JsonObject();
        response.addProperty("type", "AUTH_OK");
        response.addProperty("signature", serverSignature);
        conn.send(GSON.toJson(response));

        MonkeycraftApi.CONNECTION.invoker().onConnected(conn.getRemoteSocketAddress().toString());

        // Sync hibernation state using STATUS message
        if (isHibernating) {
          JsonObject hibernationStatus = new JsonObject();
          hibernationStatus.addProperty("type", "HIBERNATION_STATUS");
          hibernationStatus.addProperty("active", true);
          hibernationStatus.addProperty("message", hibernationMessage);
          conn.send(GSON.toJson(hibernationStatus));
        }

        // Sync timed notification state using STATUS message
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
      } else {
        sendAuthResponse(conn, false, "Invalid signature");
        conn.close();
      }
    }

    private void sendAuthResponse(WebSocket conn, boolean success, String message) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "AUTH_RESPONSE");
      response.addProperty("success", success);
      response.addProperty("message", message);
      conn.send(GSON.toJson(response));
    }

    private void sendResponse(WebSocket conn, String type, boolean success, String message) {
      if (conn == null || !conn.isOpen()) {
        return;
      }
      JsonObject response = new JsonObject();
      response.addProperty("type", type);
      response.addProperty("success", success);
      response.addProperty("message", message);
      conn.send(GSON.toJson(response));
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
