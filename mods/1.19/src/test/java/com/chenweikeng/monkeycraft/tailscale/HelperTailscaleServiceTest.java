package com.chenweikeng.monkeycraft.tailscale;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;

class HelperTailscaleServiceTest {
  @Test
  void ignoresWrongNonceAndProtocolAndRedactsLoginDiagnostics() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-service");
    AtomicReference<String> opened = new AtomicReference<>();
    HelperTailscaleService service =
        new HelperTailscaleService(fakeHelper(root, false), root.resolve("state"), opened::set);
    try {
      service.ensureRunning(9600);
      waitFor(() -> service.snapshot().needsLogin());

      assertEquals("https://login.tailscale.com/a/test-secret", opened.get());
      assertFalse(service.snapshot().error().contains("test-secret"));
      assertFalse(service.snapshot().toString().contains("test-secret"));
      assertFalse(service.diagnostics().contains("test-secret"));
      assertFalse(service.snapshot().errorCode().equals("INVALID_HELPER_MESSAGE"));
    } finally {
      service.shutdown();
    }
  }

  @Test
  void shutdownEndsTheChildAndRestartKeepsTheSameStateDirectory() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-restart");
    Path state = root.resolve("state");
    HelperTailscaleService service =
        new HelperTailscaleService(fakeHelper(root, true), state, url -> {});
    try {
      service.ensureRunning(9600);
      waitFor(() -> "HELPER_EXITED".equals(service.snapshot().errorCode()));
      service.ensureRunning(9600);
      waitFor(() -> service.snapshot().needsLogin());
      service.stop();
      waitFor(() -> "stopped".equals(service.snapshot().state()));
      long pid = Long.parseLong(Files.readString(root.resolve("pid")).trim());
      service.shutdown();
      waitFor(() -> ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false) == false);

      List<String> stateDirs = Files.readAllLines(root.resolve("state-dirs"));
      assertEquals(2, stateDirs.size());
      assertTrue(stateDirs.stream().allMatch(state.toString()::equals));
    } finally {
      service.shutdown();
    }
  }

  @Test
  void immediateShutdownCancelsAQueuedStart() throws Exception {
    Assumptions.assumeTrue(!System.getProperty("os.name", "").toLowerCase().contains("win"));
    Path root = Files.createTempDirectory("monkeycraft-helper-cancel");
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
    assertTrue(blocked.await(3, TimeUnit.SECONDS));
    HelperTailscaleService service =
        new HelperTailscaleService(
            fakeHelper(root, false), root.resolve("state"), url -> {}, control);
    try {
      service.ensureRunning(9600);
      service.shutdown();
      release.countDown();
      service.awaitControlForTest();

      assertFalse(Files.exists(root.resolve("runs")));
      assertFalse(service.isProcessAliveForTest());
    } finally {
      release.countDown();
      service.shutdown();
      control.shutdownNow();
    }
  }

  private static Path fakeHelper(Path root, boolean exitFirst) throws Exception {
    Path script = root.resolve("fake-helper.sh");
    Path count = root.resolve("runs");
    Path stateDirs = root.resolve("state-dirs");
    String body =
        """
        #!/bin/sh
        count_file='%s'
        state_file='%s'
        pid_file='%s'
        count=0
        if [ -f "$count_file" ]; then count=$(cat "$count_file"); fi
        count=$((count + 1))
        printf '%%s' "$count" > "$count_file"
        printf '%%s' "$$" > "$pid_file"
        IFS= read -r first || exit 0
        nonce=$(printf '%%s' "$first" | sed -n 's/.*"sessionNonce":"\\([^"\\]*\\)".*/\\1/p')
        state=$(printf '%%s' "$first" | sed -n 's/.*"stateDir":"\\([^"\\]*\\)".*/\\1/p')
        printf '%%s\\n' "$state" >> "$state_file"
        printf '{"protocolVersion":99,"sessionNonce":"wrong","event":"stateChanged","state":"failed"}\\n'
        printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"ready","state":"stopped"}\\n' "$nonce"
        if [ "$count" = "1" ] && [ "%s" = "true" ]; then exec 1>&-; sleep 0.1; exit 0; fi
        printf 'https://login.tailscale.com/a/test-secret tskey-secret' >&2
        printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"authRequired","state":"needsLogin","authUrl":"https://login.tailscale.com/a/test-secret"}\\n' "$nonce"
        while IFS= read -r line; do
          command=$(printf '%%s' "$line" | sed -n 's/.*"command":"\\([^"\\]*\\)".*/\\1/p')
          case "$command" in
            stop) printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stopped","state":"stopped"}\\n' "$nonce" ;;
            shutdown) printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stopped","state":"stopped"}\\n' "$nonce"; exit 0 ;;
            logout) printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stateChanged","state":"needsLogin"}\\n' "$nonce" ;;
            status) printf '{"protocolVersion":1,"sessionNonce":"%%s","event":"stateChanged","state":"needsLogin"}\\n' "$nonce" ;;
          esac
        done
        """
            .formatted(count, stateDirs, root.resolve("pid"), exitFirst);
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
    boolean value();
  }
}
