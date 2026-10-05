package com.chenweikeng.monkeycraft.tailscale;

import static org.junit.jupiter.api.Assertions.*;

import com.monkeycraft.tailscale.TailscaleClient;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import org.junit.jupiter.api.Test;

class JavaTailscaleServiceTest {
  private static TailscaleClient.Status status(String state, String url, String error) {
    return new TailscaleClient.Status(
        state,
        url,
        "nodekey:private-test-value",
        List.of("100.64.0.8", "fd7a:115c:a1e0::8"),
        error,
        Map.of("connections", 2L));
  }

  @Test
  void readinessRequiresActualListenerAndNeverExposesNodeKeyAsDeviceId() {
    var result = JavaTailscaleService.convert(status("running", "", ""), 25566, false);
    assertFalse(result.isRunning());
    assertEquals("", result.nodeId());
    assertEquals(25566, result.port());
    assertEquals("100.64.0.8", result.tailnetIp());
    assertEquals(2, result.connections());
    assertTrue(JavaTailscaleService.convert(status("running", "", ""), 25566, true).isRunning());
    assertFalse(
        JavaTailscaleService.convert(status("needsApproval", "", ""), 25566, true).isRunning());
    assertFalse(
        JavaTailscaleService.convert(status("unsupported", "", "tailnet-lock"), 25566, false)
            .recoverable());
  }

  @Test
  void portChangeClosesPreviousClientAndIgnoresOldLoginCallbacks() throws Exception {
    List<FakeClient> clients = new CopyOnWriteArrayList<>();
    List<String> opened = new CopyOnWriteArrayList<>();
    JavaTailscaleService service =
        new JavaTailscaleService(
            (port, callback) -> {
              if (!clients.isEmpty()) assertTrue(clients.getLast().closed);
              FakeClient client = new FakeClient(port, callback);
              clients.add(client);
              return client;
            },
            opened::add,
            true);
    try {
      service.ensureRunning(25566);
      service.awaitControlForTest();
      service.ensureRunning(25566);
      service.awaitControlForTest();
      assertEquals(1, clients.size());
      service.ensureRunning(25567);
      service.awaitControlForTest();
      assertEquals(2, clients.size());
      clients.getFirst().emit(status("needsLogin", "https://login.tailscale.com/a/stale", ""));
      clients.getLast().emit(status("running", "", ""));
      service.awaitControlForTest();
      assertTrue(opened.isEmpty());
      assertEquals(25567, service.snapshot().port());
      assertTrue(service.snapshot().isRunning());
      service.stop();
      assertEquals("stopped", service.snapshot().state());
      service.awaitControlForTest();
      assertTrue(clients.getLast().closed);
    } finally {
      service.shutdown();
      service.awaitControlForTest();
    }
  }

  @Test
  void stopDuringCreationDoesNotStartOrLeakClient() throws Exception {
    CountDownLatch entered = new CountDownLatch(1);
    CountDownLatch release = new CountDownLatch(1);
    List<FakeClient> clients = new CopyOnWriteArrayList<>();
    JavaTailscaleService service =
        new JavaTailscaleService(
            (port, callback) -> {
              entered.countDown();
              assertTrue(release.await(5, TimeUnit.SECONDS));
              FakeClient client = new FakeClient(port, callback);
              clients.add(client);
              return client;
            },
            url -> fail("Should not open browser"),
            true);
    try {
      service.ensureRunning(25565);
      assertTrue(entered.await(5, TimeUnit.SECONDS));
      service.stop();
      release.countDown();
      service.awaitControlForTest();
      assertTrue(clients.getFirst().closed);
      assertFalse(clients.getFirst().started);
      assertEquals("stopped", service.snapshot().state());
    } finally {
      release.countDown();
      service.shutdown();
      service.awaitControlForTest();
    }
  }

  @Test
  void browserFailureCanBeRetriedWithoutResettingIdentityOrRepeatedAutomaticOpen()
      throws Exception {
    List<FakeClient> clients = new ArrayList<>();
    AtomicInteger opens = new AtomicInteger();
    JavaTailscaleService service =
        new JavaTailscaleService(
            (port, callback) -> {
              FakeClient client = new FakeClient(port, callback);
              clients.add(client);
              return client;
            },
            url -> {
              if (opens.incrementAndGet() == 1) throw new Exception("test");
            },
            true);
    try {
      service.login(25565);
      service.awaitControlForTest();
      var login = status("needsLogin", "https://login.tailscale.com/a/test", "");
      clients.getFirst().emit(login);
      service.awaitControlForTest();
      assertEquals("LOGIN_BROWSER_FAILED", service.snapshot().errorCode());
      clients.getFirst().emit(login);
      service.awaitControlForTest();
      assertEquals(1, opens.get());
      service.login(25565);
      service.awaitControlForTest();
      assertEquals(2, opens.get());
      assertEquals("", service.snapshot().errorCode());
      assertEquals(1, clients.size());
      assertEquals(0, clients.getFirst().logins);
    } finally {
      service.shutdown();
      service.awaitControlForTest();
    }
  }

  @Test
  void logoutAfterStopStillRevokesPersistedIdentityAndReportsRemoteFailure() throws Exception {
    List<FakeClient> clients = new CopyOnWriteArrayList<>();
    JavaTailscaleService service =
        new JavaTailscaleService(
            (port, callback) -> {
              FakeClient client = new FakeClient(port, callback);
              client.logoutError = "remote-logout-unconfirmed";
              clients.add(client);
              return client;
            },
            url -> fail("Should not open browser"),
            true);
    try {
      service.logout();
      service.awaitControlForTest();
      assertEquals(1, clients.getFirst().logouts);
      assertTrue(clients.getFirst().closed);
      assertEquals("remote-logout-unconfirmed", service.snapshot().error());
      assertFalse(service.snapshot().isRunning());
    } finally {
      service.shutdown();
      service.awaitControlForTest();
    }
  }

  private static final class FakeClient implements JavaTailscaleService.Client {
    final int port;
    final Consumer<TailscaleClient.Status> callback;
    volatile TailscaleClient.Status current = JavaTailscaleServiceTest.status("starting", "", "");
    volatile boolean closed, started;
    int logins, logouts;
    String logoutError = "";

    FakeClient(int port, Consumer<TailscaleClient.Status> callback) {
      this.port = port;
      this.callback = callback;
    }

    public void start() {
      started = true;
    }

    public void login() {
      logins++;
    }

    public void logout() {
      logouts++;
      emit(JavaTailscaleServiceTest.status("needsLogin", "", logoutError));
    }

    public TailscaleClient.Status status() {
      return current;
    }

    public boolean isListening() {
      return !closed && current.state().equals("running");
    }

    public void close() {
      closed = true;
    }

    void emit(TailscaleClient.Status value) {
      current = value;
      callback.accept(value);
    }
  }
}
