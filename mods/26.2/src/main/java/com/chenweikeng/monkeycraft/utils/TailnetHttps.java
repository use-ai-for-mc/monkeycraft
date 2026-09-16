package com.chenweikeng.monkeycraft.utils;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.TimeUnit;

public final class TailnetHttps {
  private static final long CACHE_MS = 5000L;
  private static volatile long cachedAt;
  private static volatile String cached = "";

  private TailnetHttps() {}

  public static String probeUrl() {
    long now = System.currentTimeMillis();
    if (now - cachedAt < CACHE_MS) {
      return cached;
    }
    String url = discover();
    cached = url;
    cachedAt = now;
    return url;
  }

  private static String discover() {
    String json = exec("tailscale", "status", "--json");
    if (json.isEmpty()) {
      return "";
    }
    try {
      JsonObject root = JsonParser.parseString(json).getAsJsonObject();
      JsonObject self = root.getAsJsonObject("Self");
      if (self == null || !self.has("DNSName")) {
        return "";
      }
      String dns = self.get("DNSName").getAsString();
      dns = dns == null ? "" : dns.replaceAll("\\.$", "").trim();
      if (dns.isEmpty() || !dns.contains(".ts.net")) {
        return "";
      }
      int httpsPort = parseServeHttpsPort(exec("tailscale", "serve", "status", "--json"), dns);
      if (httpsPort > 0 && httpsPort != 443) {
        return "https://" + dns + ":" + httpsPort;
      }
      return "https://" + dns;
    } catch (Exception e) {
      return "";
    }
  }

  private static int parseServeHttpsPort(String serveJson, String dns) {
    if (serveJson.isEmpty()) {
      return 0;
    }
    try {
      JsonElement rootEl = JsonParser.parseString(serveJson);
      if (!rootEl.isJsonObject()) {
        return 0;
      }
      JsonObject web = rootEl.getAsJsonObject().getAsJsonObject("Web");
      if (web == null) {
        return 0;
      }
      for (Map.Entry<String, JsonElement> e : web.entrySet()) {
        String host = e.getKey();
        if (host != null && host.startsWith(dns)) {
          int colon = host.lastIndexOf(':');
          if (colon > 0) {
            return Integer.parseInt(host.substring(colon + 1));
          }
        }
      }
    } catch (Exception ignored) {
    }
    return 0;
  }

  private static String exec(String... command) {
    try {
      Process process = new ProcessBuilder(command).redirectErrorStream(true).start();
      boolean done = process.waitFor(400, TimeUnit.MILLISECONDS);
      if (!done) {
        process.destroyForcibly();
        return "";
      }
      if (process.exitValue() != 0) {
        return "";
      }
      try (InputStream in = process.getInputStream()) {
        return new String(in.readAllBytes(), StandardCharsets.UTF_8);
      }
    } catch (Exception e) {
      return "";
    }
  }
}
