package com.chenweikeng.monkeycraft.server;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.jupiter.api.Test;

class WebAssetServerTest {
  @Test
  void missingIndexFallsBackToPlaceholder() {
    WebAssetServer server = new WebAssetServer(path -> null);
    WebAssetServer.Response response = server.get("/");
    assertEquals(200, response.status());
    assertEquals("text/html; charset=utf-8", response.contentType());
    assertArrayEquals(WebAssetServer.PLACEHOLDER_HTML, response.body());
  }

  @Test
  void servesExactAssetAnd404() {
    byte[] js = "console.log(1)".getBytes(StandardCharsets.UTF_8);
    WebAssetServer server =
        new WebAssetServer(
            path -> {
              if ("flutter.js".equals(path)) {
                return js;
              }
              return null;
            });
    WebAssetServer.Response hit = server.get("/flutter.js");
    assertEquals(200, hit.status());
    assertEquals("text/javascript; charset=utf-8", hit.contentType());
    assertArrayEquals(js, hit.body());
    assertEquals(404, server.get("/nope.js").status());
  }

  @Test
  void rejectsPathTraversal() {
    assertNull(WebAssetServer.normalize("/../secret"));
    assertNull(WebAssetServer.normalize("/foo/../../etc/passwd"));
    assertEquals(400, new WebAssetServer(path -> new byte[0]).get("/../x").status());
  }

  @Test
  void stripsQueryAndLeadingSlash() {
    assertEquals("assets/foo.png", WebAssetServer.normalize("/assets/foo.png?cache=1"));
    assertEquals("index.html", WebAssetServer.normalize("/"));
    assertEquals("index.html", WebAssetServer.normalize(""));
  }

  @Test
  void requestPathParsesStartLine() {
    assertEquals("/", HttpOrWebSocketChannel.requestPath("GET / HTTP/1.1"));
    assertEquals("/flutter.js", HttpOrWebSocketChannel.requestPath("GET /flutter.js HTTP/1.1"));
    assertEquals("/a%20b", HttpOrWebSocketChannel.requestPath("HEAD /a%20b HTTP/1.1"));
  }

  @Test
  void prefersPackedIndexOverPlaceholder() {
    byte[] html = "<title>MonkeyCraft</title>".getBytes(StandardCharsets.UTF_8);
    WebAssetServer server = new WebAssetServer(Map.of("index.html", html)::get);
    WebAssetServer.Response response = server.get("/");
    assertEquals(200, response.status());
    assertArrayEquals(html, response.body());
  }
}
