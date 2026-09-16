package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.config.ModConfig;
import java.security.SecureRandom;
import java.util.Locale;
import org.java_websocket.WebSocket;

public final class PairingSession {
  public static final long TTL_MS = 3 * 60 * 1000L;
  public static final int CODE_LENGTH = 8;
  private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  private static final SecureRandom RANDOM = new SecureRandom();

  private final WebSocket conn;
  private final String code;
  private final String deviceName;
  private final long createdAt = System.currentTimeMillis();

  public PairingSession(WebSocket conn) {
    this(conn, "");
  }

  public PairingSession(WebSocket conn, String deviceName) {
    this.conn = conn;
    this.code = generateCode();
    this.deviceName = deviceName == null ? "" : deviceName;
  }

  public WebSocket conn() {
    return conn;
  }

  public String code() {
    return code;
  }

  public String deviceName() {
    return deviceName;
  }

  public boolean isExpired() {
    return System.currentTimeMillis() - createdAt > TTL_MS;
  }

  public boolean matches(String typed) {
    if (typed == null) {
      return false;
    }
    String normalized = typed.trim().toUpperCase(Locale.ROOT).replace("-", "");
    return code.equals(normalized);
  }

  public static String generateCode() {
    StringBuilder sb = new StringBuilder(CODE_LENGTH);
    for (int i = 0; i < CODE_LENGTH; i++) {
      sb.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
    }
    return sb.toString();
  }

  public static String displayCode(String code) {
    if (code == null || code.length() != CODE_LENGTH) {
      return code;
    }
    return code.substring(0, 4) + "-" + code.substring(4);
  }

  public static String longTermPassword() {
    return ModConfig.generateRandomPassword();
  }
}
