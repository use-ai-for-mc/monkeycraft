package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.api.v1.MonkeycraftApi;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.mixin.MouseHandlerInvoker;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonSyntaxException;
import com.mojang.blaze3d.platform.NativeImage;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.util.concurrent.atomic.AtomicBoolean;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.input.MouseButtonInfo;
import net.minecraft.network.chat.Component;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import org.lwjgl.glfw.GLFW;

public class WebSocketServerHandler {
  private static WebSocketServerHandler instance;
  private MonkeycraftWebSocketServer server;
  private int currentPort = -1;
  private final AtomicBoolean running = new AtomicBoolean(false);
  private static final Gson GSON = new Gson();
  private H264Streamer streamer;
  private boolean isStreaming = false;
  private StreamConfig streamConfig = new StreamConfig();
  private boolean isHibernating = false;
  private String hibernationMessage = "";

  private boolean turnLeft, turnRight, lookUp, lookDown;

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

  public static class StreamConfig {
    public int width = 360;
    public int height = 640;
    public int colorMode = 0;
    public int fps = 20;
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
      MonkeycraftClient.LOGGER.info("WebSocket server started on port {}", port);
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

    if (server != null) {
      try {
        server.stop();
        MonkeycraftClient.LOGGER.info("WebSocket server stopped");
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

  public void sendTimedNotification(Long fireAtEpochMs, String title, String body, boolean sound) {
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;

    JsonObject msg = new JsonObject();
    msg.addProperty("type", "TIMED");
    if (fireAtEpochMs != null) {
      msg.addProperty("fireAtEpochMs", fireAtEpochMs);
    } else {
      msg.add("fireAtEpochMs", null);
    }
    if (title != null) msg.addProperty("title", title);
    if (body != null) msg.addProperty("body", body);
    msg.addProperty("sound", sound);
    conn.send(GSON.toJson(msg));
  }

  public void cancelTimedNotification() {
    sendTimedNotification(null, null, null, false);
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

  public void startHibernation(String message) {
    isHibernating = true;
    hibernationMessage = message == null ? "" : message;
    isStreaming = false;
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "HIBERNATION_START");
    msg.addProperty("message", hibernationMessage);
    conn.send(GSON.toJson(msg));
  }

  public void endHibernation() {
    isHibernating = false;
    hibernationMessage = "";
    if (server == null) return;
    WebSocket conn = server.authenticatedSession;
    if (conn == null || !conn.isOpen()) return;
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "HIBERNATION_END");
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

  private class MonkeycraftWebSocketServer extends WebSocketServer {
    private WebSocket authenticatedSession;

    public MonkeycraftWebSocketServer(int port) {
      super(new InetSocketAddress(port));
    }

    @Override
    public void onOpen(WebSocket conn, ClientHandshake handshake) {
      MonkeycraftClient.LOGGER.info(
          "New WebSocket connection from {}", conn.getRemoteSocketAddress());
    }

    @Override
    public void onClose(WebSocket conn, int code, String reason, boolean remote) {
      if (conn == authenticatedSession) {
        authenticatedSession = null;
        isStreaming = false;
        MonkeycraftApi.DISCONNECTION.invoker().onDisconnected();
        MonkeycraftClient.LOGGER.info("Authenticated session closed");
      }
      MonkeycraftClient.LOGGER.info("WebSocket connection closed: {} - {}", code, reason);
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
            } else if ("HIBERNATION_PING".equals(type)) {
              handleHibernationPing(conn);
            } else if ("RUN_COMMAND".equals(type)) {
              handleRunCommand(json);
            } else if ("CLICK".equals(type)) {
              handleClick(json);
            } else if ("HOTBAR_SELECT".equals(type)) {
              handleHotbarSelect(json);
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
      Minecraft mc = Minecraft.getInstance();
      mc.execute(
          () -> {
            try {
              MouseHandlerInvoker mouse = (MouseHandlerInvoker) (Object) mc.mouseHandler;
              long windowHandle = mc.getWindow().handle();
              if (MonkeycraftClient.pendingRightClickReleaseTicks > 0) {
                mouse.monkeycraft$onButton(
                    windowHandle, new MouseButtonInfo(1, 0), GLFW.GLFW_RELEASE);
                MonkeycraftClient.pendingRightClickReleaseTicks = 0;
              }

              mouse.monkeycraft$onButton(windowHandle, new MouseButtonInfo(1, 0), GLFW.GLFW_PRESS);
              MonkeycraftClient.pendingRightClickReleaseTicks = 1;
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

    private void handleRunCommand(JsonObject json) {
      if (!json.has("command")) return;
      String raw = json.get("command").getAsString();
      if (raw == null) return;
      raw = raw.trim();
      if (raw.isEmpty()) return;
      if (!raw.startsWith("/")) return;
      final String command = raw;
      final String cmd = raw.substring(1);

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

    private void handleHibernationPing(WebSocket conn) {
      JsonObject response = new JsonObject();
      response.addProperty("type", "HIBERNATION_STATUS");
      response.addProperty("active", isHibernating);
      if (isHibernating) {
        response.addProperty("message", hibernationMessage);
      }
      conn.send(GSON.toJson(response));
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
              // Reset pitch to 0 (look straight) on press, as requested
              if (pressed
                  && mc.player != null
                  && ("W".equals(key)
                      || "A".equals(key)
                      || "S".equals(key)
                      || "D".equals(key)
                      || "SPACE".equals(key))) {
                mc.player.setXRot(0);
              }
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
      if (!json.has("password")) {
        sendAuthResponse(conn, false, "Missing password");
        return;
      }

      String password = json.get("password").getAsString();
      if (password.equals(ModConfig.getInstance().getPassword())) {
        if (authenticatedSession != null && authenticatedSession != conn) {
          if (authenticatedSession.isOpen()) {
            sendAuthResponse(authenticatedSession, false, "Logged in from another location");
            authenticatedSession.close();
          }
        }
        authenticatedSession = conn;
        sendAuthResponse(conn, true, "Authenticated");
        MonkeycraftApi.CONNECTION.invoker().onConnected(conn.getRemoteSocketAddress().toString());
        if (isHibernating) {
          JsonObject msg = new JsonObject();
          msg.addProperty("type", "HIBERNATION_START");
          msg.addProperty("message", hibernationMessage);
          conn.send(GSON.toJson(msg));
        }
        MonkeycraftClient.sendSystemMessage(
            Component.literal(
                "Monkeycraft: New client authenticated from " + conn.getRemoteSocketAddress()));
      } else {
        sendAuthResponse(conn, false, "Invalid password");
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
    public void onStart() {
      MonkeycraftClient.LOGGER.info("WebSocket server started successfully");
    }
  }
}
