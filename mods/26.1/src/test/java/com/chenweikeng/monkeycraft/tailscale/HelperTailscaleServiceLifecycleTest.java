package com.chenweikeng.monkeycraft.tailscale;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;

class HelperTailscaleServiceLifecycleTest {
  @Test
  void repeatedAuthUrlOpensOnceButExplicitReopenStillWorks() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-duplicate-auth");
    AtomicInteger browserAttempts = new AtomicInteger();
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "duplicate"),
            root.resolve("state"),
            url -> browserAttempts.incrementAndGet());
    try {
      service.ensureRunning(9600);
      waitFor(() -> "needsApproval".equals(service.snapshot().state()));
      assertEquals(1, browserAttempts.get());
      service.reopenLogin();
      service.awaitControlForTest();
      assertEquals(2, browserAttempts.get());
      assertEquals(
          1, Files.readAllLines(root.resolve("commands")).stream().filter("start"::equals).count());
    } finally {
      service.shutdown();
    }
  }

  @Test
  void browserFailureSurvivesStatusAndRepeatedEnsureRetriesIt() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-browser-failure");
    AtomicInteger browserAttempts = new AtomicInteger();
    AtomicBoolean failBrowser = new AtomicBoolean(true);
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "auth"),
            root.resolve("state"),
            url -> {
              browserAttempts.incrementAndGet();
              if (failBrowser.get()) {
                throw new IllegalStateException("no browser");
              }
            });
    try {
      service.ensureRunning(9600);
      waitFor(() -> "LOGIN_BROWSER_FAILED".equals(service.snapshot().errorCode()));
      service.status();
      waitFor(() -> Files.exists(root.resolve("status.done")));
      assertEquals("LOGIN_BROWSER_FAILED", service.snapshot().errorCode());

      failBrowser.set(false);
      service.login(9600);
      waitFor(() -> service.snapshot().needsLogin() && service.snapshot().errorCode().isEmpty());
      assertEquals(2, browserAttempts.get());
      assertEquals(
          1, Files.readAllLines(root.resolve("commands")).stream().filter("start"::equals).count());
    } finally {
      service.shutdown();
    }
  }

  @Test
  void stopIgnoresLateAuthAndRestartCreatesNewChild() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-late-auth");
    AtomicInteger browserAttempts = new AtomicInteger();
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "late"), root.resolve("state"), url -> browserAttempts.incrementAndGet());
    try {
      service.ensureRunning(9600);
      waitFor(() -> Files.exists(root.resolve("runs")));
      service.stop();
      service.awaitControlForTest();
      assertEquals("stopped", service.snapshot().state());
      assertEquals(0, browserAttempts.get());
      assertFalse(service.isProcessAliveForTest());

      service.ensureRunning(9600);
      waitFor(() -> Files.readString(root.resolve("runs")).trim().equals("2"));
      assertEquals(0, browserAttempts.get());
    } finally {
      service.shutdown();
    }
  }

  @Test
  void duplicateEnsureRunningDoesNotRepeatStartForTheSameLiveHelper() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-duplicate-start");
    AtomicInteger browserAttempts = new AtomicInteger();
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "auth"), root.resolve("state"), url -> browserAttempts.incrementAndGet());
    try {
      service.ensureRunning(9600);
      waitFor(() -> browserAttempts.get() == 1);
      service.ensureRunning(9600);
      service.awaitControlForTest();
      assertEquals(1, browserAttempts.get());
      assertEquals(
          1, Files.readAllLines(root.resolve("commands")).stream().filter("start"::equals).count());
    } finally {
      service.shutdown();
    }
  }

  @Test
  void targetPortChangeRestartsTheChildInsteadOfSendingAnotherStart() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-port-change");
    AtomicInteger browserAttempts = new AtomicInteger();
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "auth"), root.resolve("state"), url -> browserAttempts.incrementAndGet());
    try {
      service.ensureRunning(9600);
      waitFor(() -> browserAttempts.get() == 1);
      service.ensureRunning(9601);
      waitFor(() -> Files.readString(root.resolve("runs")).trim().equals("2"));
      waitFor(() -> browserAttempts.get() == 2);
      assertEquals(
          2, Files.readAllLines(root.resolve("commands")).stream().filter("start"::equals).count());
    } finally {
      service.shutdown();
    }
  }

  @Test
  void logoutWaitsForNeedsLoginBeforeStoppingAndAllowsNewLogin() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-logout");
    AtomicInteger browserAttempts = new AtomicInteger();
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "auth"), root.resolve("state"), url -> browserAttempts.incrementAndGet());
    try {
      service.ensureRunning(9600);
      waitFor(() -> browserAttempts.get() == 1);
      service.logout();
      waitFor(() -> Files.exists(root.resolve("status.logout-old")));
      assertTrue(service.isProcessAliveForTest());
      service.login(9600);
      assertTrue(service.isProcessAliveForTest());
      assertEquals(1, browserAttempts.get());
      assertFalse("LOGIN_URL_MISSING".equals(service.snapshot().errorCode()));
      waitFor(() -> "stopped".equals(service.snapshot().state()));
      waitFor(() -> service.isProcessAliveForTest() == false);

      service.ensureRunning(9600);
      waitFor(() -> Files.readString(root.resolve("runs")).trim().equals("2"));
      waitFor(() -> browserAttempts.get() == 2);
    } finally {
      service.shutdown();
    }
  }

  @Test
  void logoutCancelsAStartQueuedBeforeTheHelperExists() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-queued-logout");
    AtomicInteger browserAttempts = new AtomicInteger();
    ExecutorService control = Executors.newSingleThreadExecutor();
    CountDownLatch blocked = new CountDownLatch(1);
    CountDownLatch release = new CountDownLatch(1);
    control.execute(
        () -> {
          blocked.countDown();
          try {
            release.await();
          } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
          }
        });
    assertTrue(blocked.await(3, java.util.concurrent.TimeUnit.SECONDS));
    HelperTailscaleService service =
        new HelperTailscaleService(
            helper(root, "auth"),
            root.resolve("state"),
            url -> browserAttempts.incrementAndGet(),
            control);
    try {
      service.ensureRunning(9600);
      service.logout();
      release.countDown();
      service.awaitControlForTest();
      assertEquals("stopped", service.snapshot().state());
      assertFalse(Files.exists(root.resolve("runs")));
      assertEquals(0, browserAttempts.get());
    } finally {
      release.countDown();
      service.shutdown();
      control.shutdownNow();
    }
  }

  private static Path helper(Path root, String mode) throws Exception {
    Path script = root.resolve("helper.sh");
    String body =
        """
        #!/bin/sh
        runs='%s'
        status='%s'
        commands='%s'
        mode='%s'
        count=0
        if [ -f "$runs" ]; then count=$(cat "$runs"); fi
        count=$((count + 1))
        printf '%%s' "$count" > "$runs"
        IFS= read -r first || exit 0
        printf 'start\n' >> "$commands"
        nonce=$(printf '%%s' "$first" | sed -n 's/.*"sessionNonce":"\\([^"\\]*\\)".*/\\1/p')
        printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"ready","state":"stopped"}\n' "$nonce"
        if [ "$mode" = auth ] || [ "$mode" = duplicate ]; then
          printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"authRequired","state":"needsLogin","authUrl":"https://login.tailscale.com/a/test-secret"}\n' "$nonce"
          if [ "$mode" = duplicate ]; then
            printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"authRequired","state":"needsLogin","authUrl":"https://login.tailscale.com/a/test-secret"}\n' "$nonce"
            printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"authRequired","state":"needsLogin","authUrl":"https://login.tailscale.com/a/test-secret"}\n' "$nonce"
            printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stateChanged","state":"needsApproval"}\n' "$nonce"
          fi
          while IFS= read -r line; do
            command=$(printf '%%s' "$line" | sed -n 's/.*"command":"\\([^"\\]*\\)".*/\\1/p')
            request_id=$(printf '%%s' "$line" | sed -n 's/.*"requestId":"\\([^"\\]*\\)".*/\\1/p')
            printf '%%s\n' "$command" >> "$commands"
            if [ "$command" = status ]; then
              printf '1' > "$status"
              printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stateChanged","state":"needsLogin"}\n' "$nonce"
              printf '1' > "$status.done"
            fi
            if [ "$command" = start ]; then
              printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"error","state":"needsLogin","errorCode":"ALREADY_STARTED","error":"already started","recoverable":true}\n' "$nonce"
            fi
            if [ "$command" = logout ]; then
              printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stateChanged","state":"needsLogin"}\n' "$nonce"
              printf '1' > "$status.logout-old"
              sleep 0.1
              printf '{"protocolVersion":1,"sessionNonce":"%%s","requestId":"%%s","event":"stateChanged","state":"needsLogin"}\n' "$nonce" "$request_id"
            fi
          done
        else
          while IFS= read -r ignored; do :; done
          printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"authRequired","state":"needsLogin","authUrl":"https://login.tailscale.com/a/test-secret"}\n' "$nonce"
          sleep 1
        fi
        """
            .formatted(
                root.resolve("runs"), root.resolve("status"), root.resolve("commands"), mode);
    Files.writeString(script, body);
    script.toFile().setExecutable(true);
    return script;
  }

  private static void waitFor(Check check) throws Exception {
    long deadline = System.nanoTime() + 3_000_000_000L;
    while (System.nanoTime() < deadline) {
      if (check.value()) {
        return;
      }
      Thread.sleep(10);
    }
    assertTrue(check.value(), "timed out waiting for helper state");
  }

  @FunctionalInterface
  private interface Check {
    boolean value() throws Exception;
  }
}
