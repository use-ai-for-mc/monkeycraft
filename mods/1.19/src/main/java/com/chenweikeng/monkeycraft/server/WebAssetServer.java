package com.chenweikeng.monkeycraft.server;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

final class WebAssetServer {
  static final byte[] PLACEHOLDER_HTML =
      ("<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
              + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
              + "<title>MonkeyCraft</title></head><body>"
              + "<p>MonkeyCraft web placeholder. The game WebSocket is on this same port.</p>"
              + "</body></html>")
          .getBytes(StandardCharsets.UTF_8);

  private static final WebAssetServer CLASSPATH =
      new WebAssetServer(WebAssetServer::classpathResource);

  private final ResourceLoader loader;

  WebAssetServer(ResourceLoader loader) {
    this.loader = loader;
  }

  static WebAssetServer classpath() {
    return CLASSPATH;
  }

  record Response(int status, String contentType, byte[] body) {}

  Response get(String requestPath) {
    String path = normalize(requestPath);
    if (path == null) {
      return new Response(400, "text/plain; charset=utf-8", bytes("Bad Request"));
    }
    byte[] body = loader.load(path);
    if (body == null && path.equals("index.html")) {
      return new Response(200, "text/html; charset=utf-8", PLACEHOLDER_HTML);
    }
    if (body == null) {
      return new Response(404, "text/plain; charset=utf-8", bytes("Not Found"));
    }
    return new Response(200, contentType(path), body);
  }

  static String normalize(String requestPath) {
    if (requestPath == null || requestPath.isEmpty()) {
      return "index.html";
    }
    String path = requestPath;
    int query = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    try {
      path = URLDecoder.decode(path, StandardCharsets.UTF_8);
    } catch (IllegalArgumentException e) {
      return null;
    }
    if (path.isEmpty() || "/".equals(path)) {
      return "index.html";
    }
    while (path.startsWith("/")) {
      path = path.substring(1);
    }
    if (path.isEmpty()) {
      return "index.html";
    }
    if (path.contains("\\") || path.contains("\0") || path.contains("..")) {
      return null;
    }
    return path;
  }

  static String contentType(String path) {
    String lower = path.toLowerCase(Locale.ROOT);
    int dot = lower.lastIndexOf('.');
    String ext = dot >= 0 ? lower.substring(dot) : "";
    return switch (ext) {
      case ".html" -> "text/html; charset=utf-8";
      case ".js" -> "text/javascript; charset=utf-8";
      case ".mjs" -> "text/javascript; charset=utf-8";
      case ".css" -> "text/css; charset=utf-8";
      case ".json" -> "application/json";
      case ".webmanifest" -> "application/manifest+json";
      case ".wasm" -> "application/wasm";
      case ".png" -> "image/png";
      case ".jpg", ".jpeg" -> "image/jpeg";
      case ".gif" -> "image/gif";
      case ".svg" -> "image/svg+xml";
      case ".ico" -> "image/x-icon";
      case ".woff" -> "font/woff";
      case ".woff2" -> "font/woff2";
      case ".ttf" -> "font/ttf";
      case ".otf" -> "font/otf";
      case ".map" -> "application/json";
      case ".bin" -> "application/octet-stream";
      default -> "application/octet-stream";
    };
  }

  private static byte[] classpathResource(String path) {
    try (InputStream in = WebAssetServer.class.getResourceAsStream("/web/" + path)) {
      if (in == null) {
        return null;
      }
      return readAll(in);
    } catch (IOException e) {
      return null;
    }
  }

  private static byte[] readAll(InputStream in) throws IOException {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    in.transferTo(out);
    return out.toByteArray();
  }

  private static byte[] bytes(String text) {
    return text.getBytes(StandardCharsets.US_ASCII);
  }

  interface ResourceLoader {
    byte[] load(String path);
  }
}
