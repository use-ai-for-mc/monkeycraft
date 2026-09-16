package com.chenweikeng.monkeycraft.server.handler;

import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.PairingSession;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.CryptoUtils;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.java_websocket.WebSocket;

public class AuthenticationHandler {
  private static final Gson GSON = new Gson();
  private static final int PROTOCOL_VERSION = 2;
  private static final String[] CAPABILITIES = {"PLAYER_LIST", "DATA_SAVER", "PAIRING", "KEY_ID"};
  private final WebSocketServerHandler handler;

  public AuthenticationHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  private static void markPhonePaired() {
    ModConfig config = ModConfig.getInstance();
    if (!config.isPhonePairedOnce()) {
      config.setPhonePairedOnce(true);
      config.save();
    }
  }

  public void handleAuth(
      WebSocket conn, JsonObject json, WebSocket authenticatedSession, AuthCallback callback) {
    String serverSalt = conn.getAttachment();
    if (serverSalt == null) {
      conn.close();
      return;
    }

    if ("PAIR".equals(json.has("mode") ? json.get("mode").getAsString() : null)) {
      handler.beginPairing(conn, sanitizeDeviceName(json));
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

    if (CryptoUtils.constantTimeEquals(expectedSignature, clientSignature)) {
      completeAuth(conn, json, authenticatedSession, callback, password, clientSalt, serverSalt);
    } else {
      sendAuthResponse(conn, false, "Invalid signature");
      conn.close();
    }
  }

  public void completePairing(PairingSession session) {
    WebSocket conn = session.conn();
    if (conn == null || !conn.isOpen()) {
      return;
    }
    String password = ModConfig.getInstance().getPassword();
    markPhonePaired();
    JsonObject response = new JsonObject();
    response.addProperty("type", "PAIR_OK");
    response.addProperty("password", password);
    conn.send(GSON.toJson(response));
  }

  public void completeAuth(
      WebSocket conn,
      JsonObject json,
      WebSocket authenticatedSession,
      AuthCallback callback,
      String password,
      String clientSalt,
      String serverSalt) {
    if (authenticatedSession != null && authenticatedSession != conn) {
      if (authenticatedSession.isOpen()) {
        sendAuthResponse(authenticatedSession, false, "Logged in from another location");
        authenticatedSession.close();
      }
    }
    callback.onAuthenticated(conn);

    String deviceName = sanitizeDeviceName(json);
    ModConfig config = ModConfig.getInstance();
    config.setLastPhoneSeenAt(System.currentTimeMillis());
    if (!deviceName.isEmpty()) {
      config.setLastPhoneName(deviceName);
    }
    config.setPhonePairedOnce(true);
    config.setWizardDone(true);
    config.save();
    handler.setConnectedDeviceName(deviceName);

    int clientProtocolVersion =
        json.has("protocolVersion") ? json.get("protocolVersion").getAsInt() : 0;

    String serverSignature = CryptoUtils.computeHmac(password, clientSalt + serverSalt);
    JsonObject response = new JsonObject();
    response.addProperty("type", "AUTH_OK");
    response.addProperty("signature", serverSignature);
    response.addProperty("protocolVersion", PROTOCOL_VERSION);
    JsonArray capabilities = new JsonArray();
    for (String capability : CAPABILITIES) {
      capabilities.add(capability);
    }
    response.add("capabilities", capabilities);
    if (clientProtocolVersion != PROTOCOL_VERSION) {
      response.addProperty(
          "versionWarning",
          "Protocol version mismatch: client="
              + clientProtocolVersion
              + ", server="
              + PROTOCOL_VERSION);
    }
    conn.send(GSON.toJson(response));

    MonkeycraftApi.CONNECTION.invoker().onConnected(conn.getRemoteSocketAddress().toString());

    handler.sendPostAuthState(conn);
  }

  private void sendAuthResponse(WebSocket conn, boolean success, String message) {
    JsonObject response = new JsonObject();
    response.addProperty("type", "AUTH_RESPONSE");
    response.addProperty("success", success);
    response.addProperty("message", message);
    conn.send(GSON.toJson(response));
  }

  private static String sanitizeDeviceName(JsonObject json) {
    if (!json.has("deviceName") || json.get("deviceName").isJsonNull()) {
      return "";
    }
    String raw = json.get("deviceName").getAsString();
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < raw.length() && sb.length() < 48; i++) {
      char c = raw.charAt(i);
      if (c >= 0x20 && c != 0x7F) {
        sb.append(c);
      }
    }
    return sb.toString().trim();
  }

  public interface AuthCallback {
    void onAuthenticated(WebSocket conn);
  }
}
