package com.chenweikeng.monkeycraft.server;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.BooleanSupplier;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.slf4j.LoggerFactory;

@Timeout(15)
class WebSocketServerShutdownTest {
  private WebSocketServerHandler handler;

  @AfterEach
  void cleanUp() {
    if (handler != null) handler.shutdown();
  }

  @Test
  void titleScreenAutoStartThenClientShutdownStopsAllWebSocketThreads() {
    handler = newHandler();
    int port = handler.startServerWithPortRange(9600, true, true);
    assertTrue(port > 0);
    assertTrue(handler.isRunning());
    assertTrue(handler.isPersistent());
    assertTrue(await(WebSocketServerShutdownTest::hasLiveWebSocketServerThread, 2000));
    assertDoesNotThrow(
        () ->
            org.junit.jupiter.api.Assertions.assertTimeout(
                Duration.ofSeconds(5), handler::shutdown));
    assertStopped(handler);
    assertTrue(await(() -> !hasLiveWebSocketServerThread(), 4000));
  }

  @Test
  void worldJoinAutoStartThenClientShutdownStopsAllWebSocketThreads() {
    handler = newHandler();
    int port = handler.startServerWithPortRange(9600, true, false);
    assertTrue(port > 0);
    assertTrue(handler.isRunning());
    assertFalse(handler.isPersistent());
    handler.shutdown();
    assertStopped(handler);
    assertTrue(await(() -> !hasLiveWebSocketServerThread(), 4000));
  }

  @Test
  void clientShutdownIsSafeWhenServerNeverStarted() {
    handler = newHandler();
    assertDoesNotThrow(handler::shutdown);
    assertStopped(handler);
    assertFalse(handler.startServerWithPortRange(9600, true, true) > 0);
  }

  @Test
  void repeatedClientShutdownIsIdempotent() {
    handler = newHandler();
    assertTrue(handler.startServerWithPortRange(9600, true, true) > 0);
    handler.shutdown();
    assertDoesNotThrow(handler::shutdown);
    assertStopped(handler);
    assertTrue(await(() -> !hasLiveWebSocketServerThread(), 4000));
  }

  @Test
  void webSocketStopFailureDoesNotSkipRemainingResources() {
    List<String> attempted = new ArrayList<>();
    assertDoesNotThrow(
        () ->
            ShutdownSequence.run(
                LoggerFactory.getLogger(WebSocketServerShutdownTest.class),
                new ShutdownSequence.Step(
                    "WebSocket server",
                    () -> {
                      attempted.add("websocket");
                      throw new IllegalStateException("simulated WebSocket stop failure");
                    }),
                new ShutdownSequence.Step("H264 streamer", () -> attempted.add("streamer")),
                new ShutdownSequence.Step("map capture state", () -> attempted.add("map"))));
    assertEquals(Arrays.asList("websocket", "streamer", "map"), attempted);
  }

  private static WebSocketServerHandler newHandler() {
    return new WebSocketServerHandler(() -> false);
  }

  private static void assertStopped(WebSocketServerHandler subject) {
    assertFalse(subject.isRunning());
    assertFalse(subject.isPersistent());
    assertEquals(-1, subject.getCurrentPort());
  }

  private static boolean hasLiveWebSocketServerThread() {
    return Thread.getAllStackTraces().keySet().stream()
        .anyMatch(
            thread ->
                thread.isAlive()
                    && (thread.getName().startsWith("WebSocketSelector-")
                        || thread.getName().startsWith("WebSocketWorker-")
                        || thread.getName().startsWith("connectionLostChecker-")));
  }

  private static boolean await(BooleanSupplier condition, long timeoutMillis) {
    long deadline = System.nanoTime() + Duration.ofMillis(timeoutMillis).toNanos();
    while (System.nanoTime() < deadline) {
      if (condition.getAsBoolean()) return true;
      try {
        Thread.sleep(10);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        return condition.getAsBoolean();
      }
    }
    return condition.getAsBoolean();
  }
}
