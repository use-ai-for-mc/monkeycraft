package com.chenweikeng.monkeycraft.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.Socket;
import java.net.StandardProtocolFamily;
import java.net.StandardSocketOptions;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.channels.ServerSocketChannel;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.java_websocket.WebSocket;
import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.handshake.ServerHandshake;
import org.java_websocket.server.WebSocketServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assumptions;
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
  void rejectsPortAlreadyOwnedByAnIpv4Listener() throws Exception {
    handler = new WebSocketServerHandler(() -> false);
    try (ServerSocketChannel occupied = ServerSocketChannel.open(StandardProtocolFamily.INET)) {
      occupied.setOption(StandardSocketOptions.SO_REUSEADDR, true);
      occupied.bind(new InetSocketAddress("127.0.0.1", 0));
      int port = ((InetSocketAddress) occupied.getLocalAddress()).getPort();
      assertFalse(handler.startServer(port, true, false));
    }
  }

  @Test
  void rejectsPortAlreadyOwnedByAnIpv4WildcardListener() throws Exception {
    handler = new WebSocketServerHandler(() -> false);
    try (ServerSocketChannel occupied = ServerSocketChannel.open(StandardProtocolFamily.INET)) {
      occupied.setOption(StandardSocketOptions.SO_REUSEADDR, true);
      occupied.bind(new InetSocketAddress("0.0.0.0", 0));
      int port = ((InetSocketAddress) occupied.getLocalAddress()).getPort();
      assertFalse(handler.startServer(port, true, false));
    }
  }

  @Test
  void rejectsPortAlreadyOwnedByAnIpv6Listener() throws Exception {
    InetAddress loopback = InetAddress.getByName("::1");
    Assumptions.assumeTrue(NetworkInterface.getByInetAddress(loopback) != null);
    handler = new WebSocketServerHandler(() -> false);
    try (ServerSocketChannel occupied = ServerSocketChannel.open(StandardProtocolFamily.INET6)) {
      occupied.setOption(StandardSocketOptions.SO_REUSEADDR, true);
      occupied.bind(new InetSocketAddress(loopback, 0));
      int port = ((InetSocketAddress) occupied.getLocalAddress()).getPort();
      assertFalse(handler.startServer(port, true, false));
    }
  }

  @Test
  void canReusePortAfterAListenerClosesAnAcceptedConnection() throws Exception {
    int port;
    try (ServerSocketChannel previous = ServerSocketChannel.open(StandardProtocolFamily.INET)) {
      previous.setOption(StandardSocketOptions.SO_REUSEADDR, true);
      previous.bind(new InetSocketAddress("127.0.0.1", 0));
      port = ((InetSocketAddress) previous.getLocalAddress()).getPort();
      try (Socket client = new Socket("127.0.0.1", port)) {
        client.setSoTimeout(2000);
        previous.accept().close();
        assertEquals(-1, client.getInputStream().read());
      }
    }
    handler = new WebSocketServerHandler(() -> false);
    assertTrue(handler.startServer(port, true, false));
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
    assertEquals(200, response.statusCode(), "port=" + port + ", body=" + response.body());
    assertTrue(response.body().contains("MonkeyCraft"));
    assertEquals("no-cache", response.headers().firstValue("cache-control").orElse(""));
    HttpResponse<String> head =
        http.send(
            HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/"))
                .timeout(Duration.ofSeconds(2))
                .method("HEAD", HttpRequest.BodyPublishers.noBody())
                .build(),
            HttpResponse.BodyHandlers.ofString());
    assertEquals(200, head.statusCode());
    assertEquals("", head.body());
    assertEquals(
        response.headers().firstValue("content-length"),
        head.headers().firstValue("content-length"));

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

  @Test
  void slowLargeHttpDownloadDoesNotDelayAnotherWebSocketClient() throws Exception {
    HttpTestServer server = new HttpTestServer();
    server.start();
    assertTrue(server.started.await(2, TimeUnit.SECONDS));

    try (Socket slowHttp = new Socket()) {
      slowHttp.setReceiveBufferSize(1024);
      slowHttp.connect(new InetSocketAddress("127.0.0.1", server.getPort()));
      OutputStream request = slowHttp.getOutputStream();
      request.write(
          ("GET /canvaskit/canvaskit.wasm HTTP/1.1\r\n"
                  + "Host: 127.0.0.1\r\n"
                  + "Connection: close\r\n\r\n")
              .getBytes(StandardCharsets.US_ASCII));
      request.flush();

      Thread.sleep(200);
      CountDownLatch alive = new CountDownLatch(1);
      WebSocketClient websocket =
          new WebSocketClient(URI.create("ws://127.0.0.1:" + server.getPort())) {
            @Override
            public void onOpen(ServerHandshake handshake) {}

            @Override
            public void onMessage(String data) {
              if ("alive".equals(data)) {
                alive.countDown();
              }
            }

            @Override
            public void onClose(int code, String reason, boolean remote) {}

            @Override
            public void onError(Exception ex) {}
          };
      try {
        websocket.connect();
        assertTrue(alive.await(2, TimeUnit.SECONDS));
      } finally {
        websocket.close();
      }

      slowHttp.setSoTimeout(5000);
      InputStream response = slowHttp.getInputStream();
      String headers = readHeaders(response);
      assertTrue(headers.startsWith("HTTP/1.1 200"), headers);
      assertTrue(headers.contains("Content-Type: application/wasm"), headers);
      Matcher contentLength = Pattern.compile("(?im)^Content-Length: (\\d+)$").matcher(headers);
      assertTrue(contentLength.find(), headers);
      int expectedBytes = Integer.parseInt(contentLength.group(1));
      assertTrue(expectedBytes >= 7_000_000, "test must use the packed Flutter CanvasKit WASM");
      assertEquals(expectedBytes, readExactly(response, expectedBytes));
      assertEquals(-1, response.read());
    } finally {
      server.stop(0);
    }
  }

  @Test
  void stoppingServerClosesSlowHttpHandoffOutsideWebSocketConnections() throws Exception {
    HttpAwareWebSocketServerFactory factory =
        new HttpAwareWebSocketServerFactory(2, TimeUnit.SECONDS.toMillis(60));
    HttpTestServer server = new HttpTestServer(factory);
    server.start();
    assertTrue(server.started.await(2, TimeUnit.SECONDS));

    try {
      try (Socket slowHttp = openSlowCanvasKitDownload(server.getPort())) {
        awaitCondition(() -> factory.activeHttpCount() == 1, 2_000);
        server.stop(1_000);
        awaitCondition(() -> factory.activeHttpCount() == 0, 2_000);
        assertEof(slowHttp, 2_000);
      }
    } finally {
      server.stop(0);
    }
  }

  @Test
  void slowHttpCapacityRejectionLeavesWebSocketResponsive() throws Exception {
    HttpAwareWebSocketServerFactory factory =
        new HttpAwareWebSocketServerFactory(1, TimeUnit.SECONDS.toMillis(10));
    HttpTestServer server = new HttpTestServer(factory);
    server.start();
    assertTrue(server.started.await(2, TimeUnit.SECONDS));

    try (Socket slowHttp = openSlowCanvasKitDownload(server.getPort());
        Socket rejectedHttp = new Socket()) {
      awaitCondition(() -> factory.activeHttpCount() == 1, 2_000);
      rejectedHttp.connect(new InetSocketAddress("127.0.0.1", server.getPort()));
      rejectedHttp
          .getOutputStream()
          .write(
              ("GET /canvaskit/canvaskit.wasm HTTP/1.1\r\n"
                      + "Host: 127.0.0.1\r\n"
                      + "Connection: close\r\n\r\n")
                  .getBytes(StandardCharsets.US_ASCII));
      rejectedHttp.getOutputStream().flush();
      assertEof(rejectedHttp, 2_000);

      assertWebSocketAlive(server.getPort());
    } finally {
      server.stop(0);
    }
  }

  @Test
  void slowHttpDeadlineClosesHandoff() throws Exception {
    HttpAwareWebSocketServerFactory factory = new HttpAwareWebSocketServerFactory(1, 250);
    HttpTestServer server = new HttpTestServer(factory);
    server.start();
    assertTrue(server.started.await(2, TimeUnit.SECONDS));

    try {
      try (Socket slowHttp = openSlowCanvasKitDownload(server.getPort())) {
        awaitCondition(() -> factory.activeHttpCount() == 1, 2_000);
        awaitCondition(() -> factory.activeHttpCount() == 0, 3_000);
        assertEof(slowHttp, 2_000);
      }
    } finally {
      server.stop(0);
    }
  }

  private static final class HttpTestServer extends WebSocketServer {
    private final CountDownLatch started = new CountDownLatch(1);

    private HttpTestServer() {
      this(new HttpAwareWebSocketServerFactory());
    }

    private HttpTestServer(HttpAwareWebSocketServerFactory factory) {
      super(new InetSocketAddress("127.0.0.1", 0));
      setWebSocketFactory(factory);
    }

    @Override
    public void onOpen(WebSocket connection, ClientHandshake handshake) {
      connection.send("alive");
    }

    @Override
    public void onClose(WebSocket connection, int code, String reason, boolean remote) {}

    @Override
    public void onMessage(WebSocket connection, String message) {}

    @Override
    public void onError(WebSocket connection, Exception exception) {}

    @Override
    public void onStart() {
      started.countDown();
    }
  }

  private static Socket openSlowCanvasKitDownload(int port) throws Exception {
    Socket socket = new Socket();
    socket.setReceiveBufferSize(1024);
    socket.connect(new InetSocketAddress("127.0.0.1", port));
    OutputStream request = socket.getOutputStream();
    request.write(
        ("GET /canvaskit/canvaskit.wasm HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\n"
                + "Connection: close\r\n\r\n")
            .getBytes(StandardCharsets.US_ASCII));
    request.flush();
    return socket;
  }

  private static void assertWebSocketAlive(int port) throws Exception {
    CountDownLatch alive = new CountDownLatch(1);
    WebSocketClient websocket =
        new WebSocketClient(URI.create("ws://127.0.0.1:" + port)) {
          @Override
          public void onOpen(ServerHandshake handshake) {}

          @Override
          public void onMessage(String data) {
            if ("alive".equals(data)) {
              alive.countDown();
            }
          }

          @Override
          public void onClose(int code, String reason, boolean remote) {}

          @Override
          public void onError(Exception ex) {}
        };
    try {
      websocket.connect();
      assertTrue(alive.await(2, TimeUnit.SECONDS));
    } finally {
      websocket.close();
    }
  }

  private static void awaitCondition(BooleanSupplier condition, long timeoutMs) throws Exception {
    long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
    while (!condition.getAsBoolean()) {
      if (System.nanoTime() >= deadline) {
        throw new AssertionError("Timed out waiting for condition");
      }
      Thread.sleep(10);
    }
  }

  private static void assertEof(Socket socket, long timeoutMs) throws Exception {
    socket.setSoTimeout((int) timeoutMs);
    InputStream input = socket.getInputStream();
    byte[] buffer = new byte[16 * 1024];
    while (input.read(buffer) >= 0) {}
  }

  private static String readHeaders(InputStream input) throws Exception {
    ByteArrayOutputStream header = new ByteArrayOutputStream();
    int matched = 0;
    byte[] end = {'\r', '\n', '\r', '\n'};
    while (matched < end.length) {
      int next = input.read();
      assertTrue(next >= 0, "HTTP response ended before headers");
      header.write(next);
      matched = next == end[matched] ? matched + 1 : next == end[0] ? 1 : 0;
    }
    return header.toString(StandardCharsets.US_ASCII);
  }

  private static int readExactly(InputStream input, int expectedBytes) throws Exception {
    byte[] buffer = new byte[16 * 1024];
    int total = 0;
    while (total < expectedBytes) {
      int read = input.read(buffer, 0, Math.min(buffer.length, expectedBytes - total));
      assertTrue(
          read >= 0, "HTTP response ended after " + total + " of " + expectedBytes + " bytes");
      total += read;
    }
    return total;
  }
}
