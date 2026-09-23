package com.chenweikeng.monkeycraft.utils;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.TimeUnit;

public final class TailnetHttps {
  private static final long CACHE_MS = 5000L;
  private static volatile long cachedAt;
  private static volatile String cached = "";
  private static volatile int cachedPort;

  private TailnetHttps() {}

  public static String probeUrl() {
    return probeUrl(9600);
  }

  public static synchronized String probeUrl(int targetPort) {
    if (targetPort < 1 || targetPort > 65535) {
      return "";
    }
    long now = System.currentTimeMillis();
    if (now - cachedAt < CACHE_MS && cachedPort == targetPort) {
      return cached;
    }
    String url = discover(targetPort);
    cached = url;
    cachedPort = targetPort;
    cachedAt = now;
    return url;
  }

  private static String discover(int targetPort) {
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
      int httpsPort =
          parseServeHttpsPort(exec("tailscale", "serve", "status", "--json"), dns, targetPort);
      if (httpsPort == 0) {
        return "";
      }
      if (httpsPort > 0 && httpsPort != 443) {
        return "https://" + dns + ":" + httpsPort;
      }
      return "https://" + dns;
    } catch (Exception e) {
      return "";
    }
  }

  static int parseServeHttpsPort(String serveJson, String dns, int targetPort) {
    if (serveJson.isEmpty()) {
      return 0;
    }
    try {
      JsonElement rootEl = JsonParser.parseString(serveJson);
      if (!rootEl.isJsonObject()) {
        return 0;
      }
      JsonObject root = rootEl.getAsJsonObject();
      JsonObject web = root.getAsJsonObject("Web");
      JsonObject tcp = root.getAsJsonObject("TCP");
      if (web == null || tcp == null) {
        return 0;
      }
      for (Map.Entry<String, JsonElement> e : web.entrySet()) {
        String host = e.getKey();
        if (host != null && host.startsWith(dns + ":")) {
          int colon = host.lastIndexOf(':');
          if (colon > 0) {
            int port = Integer.parseInt(host.substring(colon + 1));
            JsonObject listener = tcp.getAsJsonObject(Integer.toString(port));
            if (port < 1
                || port > 65535
                || listener == null
                || !listener.has("HTTPS")
                || !listener.get("HTTPS").getAsBoolean()) {
              continue;
            }
            JsonObject handlers = e.getValue().getAsJsonObject().getAsJsonObject("Handlers");
            if (handlers == null || !handlers.has("/")) {
              continue;
            }
            JsonObject route = handlers.getAsJsonObject("/");
            if (route == null || !route.has("Proxy")) {
              continue;
            }
            URI proxy = URI.create(route.get("Proxy").getAsString());
            String target = proxy.getHost();
            String path = proxy.getPath();
            if ("http".equals(proxy.getScheme())
                && proxy.getPort() == targetPort
                && ("127.0.0.1".equals(target)
                    || "localhost".equals(target)
                    || "[::1]".equals(target))
                && (path == null || path.isEmpty() || "/".equals(path))
                && proxy.getRawUserInfo() == null
                && proxy.getRawQuery() == null
                && proxy.getRawFragment() == null) {
              return port;
            }
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
