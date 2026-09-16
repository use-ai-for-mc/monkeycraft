package com.chenweikeng.monkeycraft.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

@Timeout(15)
class HttpAndWebSocketPortTest {
  private WebSocketServerHandler handler;

  @AfterEach
  void cleanUp() {
    if (handler != null) {
      handler.shutdown();
    }
  }

  @Test
  void samePortServesPlaceholderHttpAndWebSocketHello() throws Exception {
    handler = new WebSocketServerHandler(() -> false);
    int port = handler.startServerWithPortRange(9600, true, false);
    assertTrue(port > 0);

    HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    HttpResponse<String> response =
        http.send(
            HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/"))
                .timeout(Duration.ofSeconds(2))
                .GET()
                .build(),
            HttpResponse.BodyHandlers.ofString());
    assertEquals(200, response.statusCode());
    assertTrue(response.body().contains("MonkeyCraft"));

    HttpResponse<String> missing =
        http.send(
            HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/no-such-asset.js"))
                .timeout(Duration.ofSeconds(2))
                .GET()
                .build(),
            HttpResponse.BodyHandlers.ofString());
    assertEquals(404, missing.statusCode());

    CountDownLatch open = new CountDownLatch(1);
    WebSocketClient client =
        new WebSocketClient(URI.create("ws://127.0.0.1:" + port)) {
          @Override
          public void onOpen(ServerHandshake handshake) {
            open.countDown();
          }

          @Override
          public void onMessage(String data) {}

          @Override
          public void onClose(int code, String reason, boolean remote) {}

          @Override
          public void onError(Exception ex) {}
        };
    client.connect();
    assertTrue(open.await(3, TimeUnit.SECONDS));
    client.close();
  }
}
