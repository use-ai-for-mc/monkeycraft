package com.chenweikeng.monkeycraft.tailscale;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import net.fabricmc.loader.api.FabricLoader;

public final class HelperTailscaleService {
  private static final int PROTOCOL_VERSION = 1;
  private static final int MAX_DIAGNOSTIC_CHARS = 2048;
  private static final int MAX_PROTOCOL_LINE_CHARS = 65536;
  private static final Gson GSON = new Gson();
  private static final HelperTailscaleService INSTANCE = new HelperTailscaleService();

  private final ExecutorService ioExecutor =
      Executors.newCachedThreadPool(
          runnable -> {
            Thread thread = new Thread(runnable, "MonkeyCraft Tailscale helper");
            thread.setDaemon(true);
            return thread;
          });
  private final ExecutorService controlExecutor;
  private final SecureRandom random = new SecureRandom();
  private final Path helperOverride;
  private final Path stateDirOverride;
  private final Consumer<String> loginOpener;
  private volatile Process process;
  private volatile BufferedWriter input;
  private volatile String nonce = "";
  private volatile TailscaleSnapshot snapshot = TailscaleSnapshot.stopped();
  private volatile String stderrTail = "";
  private volatile boolean starting;
  private long generation;
  private long processGeneration;
  private int activeTargetPort;
  private String pendingAuthUrl = "";
  private boolean logoutPending;
  private String logoutRequestId = "";

  private HelperTailscaleService() {
    this(null, null, null);
  }

  HelperTailscaleService(Path helperOverride, Path stateDirOverride, Consumer<String> loginOpener) {
    this(helperOverride, stateDirOverride, loginOpener, null);
  }

  HelperTailscaleService(
      Path helperOverride,
      Path stateDirOverride,
      Consumer<String> loginOpener,
      ExecutorService controlExecutor) {
    this.helperOverride = helperOverride;
    this.stateDirOverride = stateDirOverride;
    this.loginOpener = loginOpener;
    this.controlExecutor =
        controlExecutor != null
            ? controlExecutor
            : Executors.newSingleThreadExecutor(
                runnable -> {
                  Thread thread = new Thread(runnable, "MonkeyCraft Tailscale control");
                  thread.setDaemon(true);
                  return thread;
                });
  }

  public static HelperTailscaleService get() {
    return INSTANCE;
  }

  public TailscaleSnapshot ensureRunning(int targetPort) {
    if (targetPort < 1 || targetPort > 65535) {
      snapshot = failed("INVALID_TARGET", "MonkeyCraft server is not running", false);
      return snapshot;
    }
    long taskGeneration;
    Process replacedProcess = null;
    BufferedWriter replacedInput = null;
    synchronized (this) {
      if (starting) {
        return snapshot;
      }
      if (logoutPending) {
        return snapshot;
      }
      if (process != null && process.isAlive() && activeTargetPort == targetPort) {
        return snapshot;
      }
      if (process != null && process.isAlive()) {
        replacedProcess = process;
        replacedInput = input;
        process = null;
        input = null;
        activeTargetPort = 0;
      }
      starting = true;
      taskGeneration = ++generation;
      snapshot = new TailscaleSnapshot("starting", "", "", targetPort, false, 0, "", "", false);
    }
    Process processToReplace = replacedProcess;
    BufferedWriter inputToReplace = replacedInput;
    controlExecutor.execute(
        () -> {
          try {
            if (processToReplace != null) {
              terminate(processToReplace, inputToReplace);
            }
            synchronized (this) {
              if (generation != taskGeneration) {
                return;
              }
              if (process == null || !process.isAlive()) {
                startProcess(taskGeneration);
              } else {
                processGeneration = taskGeneration;
              }
              if (generation != taskGeneration) {
                return;
              }
              activeTargetPort = targetPort;
              send("start", "start-" + System.nanoTime(), targetPort);
            }
          } catch (IOException e) {
            synchronized (this) {
              if (generation == taskGeneration) {
                snapshot = failed("HELPER_START_FAILED", e.getMessage(), true);
              }
            }
          } finally {
            synchronized (this) {
              if (generation == taskGeneration) {
                starting = false;
              }
            }
          }
        });
    return snapshot;
  }

  public TailscaleSnapshot status() {
    controlExecutor.execute(() -> sendQuietly("status"));
    return snapshot;
  }

  public TailscaleSnapshot login(int targetPort) {
    TailscaleSnapshot current = ensureRunning(targetPort);
    synchronized (this) {
      if (logoutPending) {
        return snapshot;
      }
      if (current.needsLogin() || isLoginBrowserFailure()) {
        return reopenLogin();
      }
    }
    return current;
  }

  public void logout() {
    String requestId;
    synchronized (this) {
      if (process == null || !process.isAlive()) {
        requestId = "";
      } else {
        logoutPending = true;
        pendingAuthUrl = "";
        logoutRequestId = "logout-" + System.nanoTime();
        requestId = logoutRequestId;
      }
    }
    if (requestId.isEmpty()) {
      stop();
      return;
    }
    controlExecutor.execute(() -> sendQuietly("logout", requestId));
  }

  public void stop() {
    Process current;
    BufferedWriter currentInput;
    synchronized (this) {
      generation++;
      starting = false;
      activeTargetPort = 0;
      pendingAuthUrl = "";
      logoutPending = false;
      logoutRequestId = "";
      snapshot = TailscaleSnapshot.stopped();
      current = process;
      currentInput = input;
      process = null;
      input = null;
    }
    controlExecutor.execute(
        () -> {
          if (current != null) {
            terminate(current, currentInput);
          }
        });
  }

  public void shutdown() {
    synchronized (this) {
      generation++;
      starting = false;
      activeTargetPort = 0;
      pendingAuthUrl = "";
      logoutPending = false;
      logoutRequestId = "";
      snapshot = TailscaleSnapshot.stopped();
    }
    controlExecutor.execute(
        () -> {
          Process current;
          BufferedWriter currentInput;
          synchronized (this) {
            current = process;
            currentInput = input;
            process = null;
            input = null;
          }
          if (current != null) {
            terminate(current, currentInput);
          }
        });
  }

  public TailscaleSnapshot snapshot() {
    return snapshot;
  }

  public String diagnostics() {
    return stderrTail;
  }

  boolean isProcessAliveForTest() {
    return process != null && process.isAlive();
  }

  void awaitControlForTest() throws Exception {
    controlExecutor.submit(() -> {}).get(3, TimeUnit.SECONDS);
  }

  private void startProcess(long taskGeneration) throws IOException {
    Path helper = helperOverride != null ? helperOverride : helperPath();
    if (helper == null) {
      throw new IOException("This MonkeyCraft build has no helper for this operating system");
    }
    nonce = newNonce();
    ProcessBuilder builder = new ProcessBuilder(helper.toString());
    builder.redirectErrorStream(false);
    process = builder.start();
    processGeneration = taskGeneration;
    pendingAuthUrl = "";
    input =
        new BufferedWriter(
            new OutputStreamWriter(process.getOutputStream(), StandardCharsets.UTF_8));
    snapshot = new TailscaleSnapshot("starting", "", "", 0, false, 0, "", "", false);
    Process current = process;
    current
        .onExit()
        .thenRun(
            () -> {
              if (acceptsEvents(current, taskGeneration)) {
                snapshot = failed("HELPER_EXITED", "Helper exited unexpectedly", true);
              }
            });
    ioExecutor.execute(() -> readStdout(current));
    ioExecutor.execute(() -> readStderr(current));
  }

  private Path helperPath() {
    String os = System.getProperty("os.name", "").toLowerCase();
    String arch = System.getProperty("os.arch", "").toLowerCase();
    String platform;
    String name = "monkeycraft-tailscale-helper";
    if (os.contains("mac") || os.contains("darwin")) {
      platform =
          arch.contains("aarch64") || arch.contains("arm64") ? "darwin-arm64" : "darwin-amd64";
    } else if (os.contains("win") && (arch.contains("amd64") || arch.contains("x86_64"))) {
      platform = "windows-amd64";
      name += ".exe";
    } else if (os.contains("linux") && (arch.contains("amd64") || arch.contains("x86_64"))) {
      platform = "linux-amd64";
    } else {
      return null;
    }
    Path target =
        FabricLoader.getInstance()
            .getConfigDir()
            .resolve("monkeycraft")
            .resolve("native")
            .resolve(platform)
            .resolve(name);
    return NativeHelperExtractor.findOrExtract(
        HelperTailscaleService.class,
        "/native/tailscale/" + platform + "/" + name,
        target,
        !name.endsWith(".exe"));
  }

  private void send(String command, String requestId, int port) throws IOException {
    if (input == null) {
      throw new IOException("helper is not running");
    }
    JsonObject message = new JsonObject();
    message.addProperty("protocolVersion", PROTOCOL_VERSION);
    message.addProperty("sessionNonce", nonce);
    message.addProperty("requestId", requestId);
    message.addProperty("command", command);
    if ("start".equals(command)) {
      message.addProperty("target", "127.0.0.1:" + port);
      message.addProperty("listenPort", port);
      message.addProperty("stateDir", stateDir().toString());
      message.addProperty("hostname", "monkeycraft");
    }
    input.write(GSON.toJson(message));
    input.newLine();
    input.flush();
  }

  private void sendQuietly(String command) {
    sendQuietly(command, command + "-" + System.nanoTime());
  }

  private void sendQuietly(String command, String requestId) {
    if (process != null && process.isAlive()) {
      try {
        send(command, requestId, 0);
      } catch (IOException e) {
        snapshot = failed("HELPER_IO_FAILED", e.getMessage(), true);
      }
    }
  }

  private void invalidateAndSend(String command) {
    synchronized (this) {
      generation++;
      starting = false;
    }
    controlExecutor.execute(() -> sendQuietly(command));
  }

  private void readStdout(Process current) {
    try (BufferedReader reader =
        new BufferedReader(
            new InputStreamReader(current.getInputStream(), StandardCharsets.UTF_8))) {
      String line;
      while ((line = readLineLimited(reader)) != null) {
        handleMessage(current, line);
      }
    } catch (IOException e) {
      MonkeycraftClient.LOGGER.debug("Tailscale helper stdout closed: {}", e.getMessage());
      if (acceptsEvents(current)) {
        snapshot = failed("HELPER_PROTOCOL_FAILED", "Helper sent an invalid response", true);
      }
    } finally {
      if (acceptsEvents(current)) {
        snapshot =
            failed(
                current.isAlive() ? "HELPER_PROTOCOL_FAILED" : "HELPER_EXITED",
                current.isAlive() ? "Helper protocol stream closed" : "Helper exited unexpectedly",
                true);
      }
    }
  }

  private void readStderr(Process current) {
    try (BufferedReader reader =
        new BufferedReader(
            new InputStreamReader(current.getErrorStream(), StandardCharsets.UTF_8))) {
      String line;
      while ((line = readLineLimited(reader)) != null) {
        if (acceptsEvents(current)) {
          appendDiagnostic(redact(line));
        }
      }
    } catch (IOException ignored) {
    }
  }

  private void handleMessage(Process current, String line) {
    long messageGeneration = -1;
    try {
      synchronized (this) {
        if (!acceptsEvents(current)) {
          return;
        }
        messageGeneration = processGeneration;
      }
      if (!acceptsEvents(current, messageGeneration)) {
        return;
      }
      JsonObject message = JsonParser.parseString(line).getAsJsonObject();
      if (!message.has("protocolVersion")
          || message.get("protocolVersion").getAsInt() != PROTOCOL_VERSION) {
        snapshot =
            failed(
                "HELPER_PROTOCOL_UNSUPPORTED", "Helper protocol version is not supported", false);
        return;
      }
      if (!nonce.equals(string(message, "sessionNonce"))) {
        snapshot = failed("HELPER_NONCE_MISMATCH", "Helper session validation failed", false);
        return;
      }
      String event = string(message, "event");
      String authUrl = string(message, "authUrl");
      if ("authRequired".equals(event)) {
        synchronized (this) {
          if (!acceptsEvents(current, messageGeneration) || logoutPending) {
            return;
          }
          if (!authUrl.isBlank() && authUrl.equals(pendingAuthUrl)) {
            return;
          }
          pendingAuthUrl = authUrl;
        }
        if (!openBrowser(current, messageGeneration, authUrl)) {
          return;
        }
      }
      boolean stopAfterLogout = false;
      synchronized (this) {
        if (!acceptsEvents(current, messageGeneration)) {
          return;
        }
        String state = string(message, "state");
        boolean logoutResult =
            logoutPending && logoutRequestId.equals(string(message, "requestId"));
        if (logoutResult) {
          if ("error".equals(event)) {
            logoutPending = false;
            logoutRequestId = "";
          } else if ("needsLogin".equals(state)) {
            logoutPending = false;
            logoutRequestId = "";
            stopAfterLogout = true;
          }
        }
        if (isLoginBrowserFailure()
            && !"authRequired".equals(event)
            && !"error".equals(event)
            && !"running".equals(state)
            && !"listening".equals(event)
            && !logoutResult
            && ("needsLogin".equals(state) || "starting".equals(state))) {
          return;
        }
        snapshot =
            new TailscaleSnapshot(
                string(message, "state"),
                string(message, "tailnetIp"),
                string(message, "nodeId"),
                integer(message, "port"),
                bool(message, "listening"),
                integer(message, "connections"),
                string(message, "errorCode"),
                redact(string(message, "error")),
                bool(message, "recoverable"));
      }
      if (stopAfterLogout) {
        stop();
      }
    } catch (RuntimeException e) {
      if (acceptsEvents(current, messageGeneration)) {
        snapshot = failed("INVALID_HELPER_MESSAGE", "Helper sent an invalid response", true);
      }
    }
  }

  private synchronized boolean acceptsEvents(Process current) {
    return process == current && processGeneration == generation;
  }

  private synchronized boolean acceptsEvents(Process current, long eventGeneration) {
    return acceptsEvents(current) && eventGeneration == generation;
  }

  public TailscaleSnapshot reopenLogin() {
    Process current;
    long currentGeneration;
    String authUrl;
    synchronized (this) {
      if (logoutPending) {
        return snapshot;
      }
      current = process;
      currentGeneration = processGeneration;
      authUrl = pendingAuthUrl;
      if (current == null || !current.isAlive() || authUrl.isBlank()) {
        snapshot = failed("LOGIN_URL_MISSING", "Tailscale did not provide a login URL", true);
        return snapshot;
      }
    }
    controlExecutor.execute(() -> openBrowser(current, currentGeneration, authUrl));
    return snapshot;
  }

  private boolean isLoginBrowserFailure() {
    return "LOGIN_BROWSER_FAILED".equals(snapshot.errorCode())
        || "LOGIN_BROWSER_UNAVAILABLE".equals(snapshot.errorCode())
        || "LOGIN_URL_MISSING".equals(snapshot.errorCode());
  }

  private static String string(JsonObject object, String key) {
    return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : "";
  }

  private static int integer(JsonObject object, String key) {
    return object.has(key) ? object.get(key).getAsInt() : 0;
  }

  private static boolean bool(JsonObject object, String key) {
    return object.has(key) && object.get(key).getAsBoolean();
  }

  private static TailscaleSnapshot failed(String code, String detail, boolean recoverable) {
    return new TailscaleSnapshot("failed", "", "", 0, false, 0, code, redact(detail), recoverable);
  }

  private static String redact(String value) {
    if (value == null) {
      return "";
    }
    return value
        .replaceAll(
            "https://login\\.tailscale\\.com/[^\\s]+", "https://login.tailscale.com/[redacted]")
        .replaceAll("tskey-[A-Za-z0-9_-]+", "tskey-[redacted]");
  }

  private void appendDiagnostic(String line) {
    String combined = stderrTail.isEmpty() ? line : stderrTail + " | " + line;
    stderrTail =
        combined.length() > MAX_DIAGNOSTIC_CHARS
            ? combined.substring(combined.length() - MAX_DIAGNOSTIC_CHARS)
            : combined;
  }

  private boolean openBrowser(Process current, long eventGeneration, String url) {
    synchronized (this) {
      if (!acceptsEvents(current, eventGeneration) || logoutPending) {
        return false;
      }
    }
    if (url.isBlank()) {
      if (acceptsEvents(current, eventGeneration) && !logoutPending) {
        snapshot = failed("LOGIN_URL_MISSING", "Tailscale did not provide a login URL", true);
      }
      return false;
    }
    try {
      if (loginOpener != null) {
        loginOpener.accept(url);
        clearLoginBrowserFailure(current, eventGeneration);
        return true;
      }
      SystemBrowserOpener.open(url);
      clearLoginBrowserFailure(current, eventGeneration);
      return true;
    } catch (Exception e) {
      if (acceptsEvents(current, eventGeneration) && !logoutPending) {
        snapshot = failed("LOGIN_BROWSER_FAILED", "Could not open the Tailscale login page", true);
      }
    }
    return false;
  }

  private void clearLoginBrowserFailure(Process current, long eventGeneration) {
    synchronized (this) {
      if (!acceptsEvents(current, eventGeneration) || logoutPending || !isLoginBrowserFailure()) {
        return;
      }
      snapshot =
          new TailscaleSnapshot("needsLogin", "", "", activeTargetPort, false, 0, "", "", false);
    }
  }

  private String newNonce() {
    byte[] bytes = new byte[24];
    random.nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  private static void terminate(Process current, BufferedWriter currentInput) {
    try {
      if (currentInput != null) {
        currentInput.close();
      }
      if (!current.waitFor(3, TimeUnit.SECONDS)) {
        current.descendants().forEach(ProcessHandle::destroy);
        current.destroy();
      }
      if (current.isAlive()) {
        current.descendants().forEach(ProcessHandle::destroyForcibly);
        current.destroyForcibly();
      }
    } catch (IOException e) {
      current.destroyForcibly();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      current.destroyForcibly();
    }
  }

  private static String readLineLimited(BufferedReader reader) throws IOException {
    StringBuilder result = new StringBuilder();
    while (true) {
      int next = reader.read();
      if (next < 0) {
        return result.isEmpty() ? null : result.toString();
      }
      if (next == '\n') {
        return result.toString();
      }
      if (next != '\r') {
        if (result.length() >= MAX_PROTOCOL_LINE_CHARS) {
          throw new IOException("helper protocol line exceeds maximum length");
        }
        result.append((char) next);
      }
    }
  }

  private Path stateDir() {
    if (stateDirOverride != null) {
      return stateDirOverride;
    }
    return FabricLoader.getInstance()
        .getConfigDir()
        .resolve("monkeycraft")
        .resolve("tailscale-state");
  }
}
