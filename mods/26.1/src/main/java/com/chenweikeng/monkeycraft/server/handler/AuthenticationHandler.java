package com.chenweikeng.monkeycraft.server.handler;

import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.CryptoUtils;
import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApi;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.java_websocket.WebSocket;

public class AuthenticationHandler {
  private static final Gson GSON = new Gson();
  private static final int PROTOCOL_VERSION = 3;
  private static final String[] CAPABILITIES = {"PLAYER_LIST", "DATA_SAVER", "TLS"};
  private final WebSocketServerHandler handler;

  public AuthenticationHandler(WebSocketServerHandler handler) {
    this.handler = handler;
  }

  public void handleAuth(
      WebSocket conn, JsonObject json, WebSocket authenticatedSession, AuthCallback callback) {
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

    if (CryptoUtils.constantTimeEquals(expectedSignature, clientSignature)) {
      if (authenticatedSession != null && authenticatedSession != conn) {
        if (authenticatedSession.isOpen()) {
          sendAuthResponse(authenticatedSession, false, "Logged in from another location");
          authenticatedSession.close();
        }
      }
      callback.onAuthenticated(conn);

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

  public interface AuthCallback {
    void onAuthenticated(WebSocket conn);
  }
}
