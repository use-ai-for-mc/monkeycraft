package com.chenweikeng.monkeycraft.tailscale;

import com.monkeycraft.tailscale.TailscaleClient;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.file.Path;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import java.util.function.Supplier;

final class JavaTailscaleService implements TailscaleBackend {
  interface Client extends AutoCloseable {
    void start();

    void login() throws Exception;

    void logout() throws Exception;

    TailscaleClient.Status status();

    boolean isListening();

    void close() throws Exception;
  }

  interface Factory {
    Client create(int port, Consumer<TailscaleClient.Status> listener) throws Exception;
  }

  interface Browser {
    void open(String url) throws Exception;
  }

  private record Session(long generation, int port, Client client) {}

  private final Factory factory;
  private final Browser browser;
  private final boolean supported;
  private final ExecutorService control =
      Executors.newSingleThreadExecutor(
          r -> {
            Thread thread = new Thread(r, "MonkeyCraft Java Tailscale control");
            thread.setDaemon(true);
            return thread;
          });
  private volatile long generation;
  private volatile Session session;
  private volatile TailscaleSnapshot fallback = TailscaleSnapshot.stopped();
  private volatile String browserError = "";
  private int requestedPort;
  private boolean loggingOut;
  private String authUrl = "";

  JavaTailscaleService(Supplier<Path> stateDirectory) {
    this(
        (port, listener) -> {
          TailscaleClient client =
              new TailscaleClient(
                  new TailscaleClient.Config(
                      stateDirectory.get(),
                      URI.create("https://controlplane.tailscale.com"),
                      "monkeycraft-java",
                      port,
                      new InetSocketAddress("127.0.0.1", port)),
                  listener);
          return new Client() {
            public void start() {
              client.start();
            }

            public void login() throws Exception {
              client.login();
            }

            public void logout() throws Exception {
              client.logout();
            }

            public TailscaleClient.Status status() {
              return client.status();
            }

            public boolean isListening() {
              return client.isListening();
            }

            public void close() throws Exception {
              client.close();
            }
          };
        },
        SystemBrowserOpener::open,
        EmbeddedTailscalePlatform.isSupported());
  }

  JavaTailscaleService(Factory factory, Browser browser, boolean supported) {
    this.factory = factory;
    this.browser = browser;
    this.supported = supported;
  }

  @Override
  public synchronized TailscaleSnapshot ensureRunning(int targetPort) {
    if (!supported || loggingOut) return snapshot();
    if (targetPort < 1 || targetPort > 65535) {
      return failed("INVALID_TARGET", "MonkeyCraft server is not running", false);
    }
    if (requestedPort == targetPort) return snapshot();
    requestedPort = targetPort;
    long epoch = ++generation;
    browserError = "";
    fallback = new TailscaleSnapshot("starting", "", "", targetPort, false, 0, "", "", false);
    control.execute(
        () -> {
          closeSession();
          if (generation != epoch) return;
          authUrl = "";
          try {
            Client client =
                factory.create(
                    targetPort, status -> control.execute(() -> onStatus(epoch, status)));
            session = new Session(epoch, targetPort, client);
            if (generation != epoch) {
              closeSession();
              return;
            }
            client.start();
          } catch (Exception | LinkageError e) {
            closeSession();
            synchronized (this) {
              if (generation == epoch) {
                requestedPort = 0;
                fallback =
                    failed(
                        "JAVA_START_FAILED",
                        "Java Tailscale could not start (" + e.getClass().getSimpleName() + ")",
                        true);
              }
            }
          }
        });
    return snapshot();
  }

  @Override
  public synchronized TailscaleSnapshot login(int targetPort) {
    ensureRunning(targetPort);
    if (!supported || loggingOut || requestedPort != targetPort) return snapshot();
    long epoch = generation;
    control.execute(
        () -> {
          Session active = session;
          if (generation != epoch || active == null || active.generation() != epoch) return;
          TailscaleClient.Status status = active.client().status();
          if (!status.authURL().isBlank()) {
            authUrl = status.authURL();
            openBrowser(epoch, authUrl);
          } else if (status.state().equals("needsLogin") || status.state().equals("stopped")) {
            try {
              active.client().login();
            } catch (Exception e) {
              if (generation == epoch) browserError = "Java Tailscale login could not start";
            }
          }
        });
    return snapshot();
  }

  private void onStatus(long epoch, TailscaleClient.Status status) {
    if (generation != epoch) return;
    if (!status.authURL().isBlank() && !status.authURL().equals(authUrl)) {
      authUrl = status.authURL();
      openBrowser(epoch, authUrl);
    }
    if (status.state().equals("running")) browserError = "";
  }

  private void openBrowser(long epoch, String url) {
    if (generation != epoch) return;
    try {
      browser.open(url);
      if (generation == epoch) browserError = "";
    } catch (Exception e) {
      if (generation == epoch)
        browserError = "Could not open the Tailscale login page; press Log in to retry";
    }
  }

  @Override
  public TailscaleSnapshot status() {
    return snapshot();
  }

  @Override
  public TailscaleSnapshot snapshot() {
    if (!supported)
      return failed("UNSUPPORTED_PLATFORM", EmbeddedTailscalePlatform.UNSUPPORTED_MESSAGE, false);
    long epoch = generation;
    Session active = session;
    if (active == null || active.generation() != epoch) return fallback;
    TailscaleClient.Status status = active.client().status();
    String error = browserError;
    TailscaleSnapshot result =
        error.isEmpty()
            ? convert(status, active.port(), active.client().isListening())
            : failed("LOGIN_BROWSER_FAILED", error, true);
    return generation == epoch ? result : fallback;
  }

  static TailscaleSnapshot convert(TailscaleClient.Status status, int port, boolean listening) {
    String ip = status.addresses().stream().filter(a -> !a.contains(":")).findFirst().orElse("");
    String error = status.error();
    String code = error.isEmpty() ? "" : "JAVA_TAILSCALE_ERROR";
    if (status.state().equals("unsupported")) code = "JAVA_FEATURE_UNSUPPORTED";
    return new TailscaleSnapshot(
        status.state(),
        ip,
        "",
        port,
        status.state().equals("running") && listening,
        status.traffic().getOrDefault("connections", 0L).intValue(),
        code,
        error,
        status.state().equals("reconnecting"));
  }

  @Override
  public synchronized void stop() {
    ++generation;
    requestedPort = 0;
    loggingOut = false;
    browserError = "";
    fallback = TailscaleSnapshot.stopped();
    control.execute(this::closeSession);
  }

  @Override
  public synchronized void logout() {
    if (!supported || loggingOut) return;
    long epoch = ++generation;
    loggingOut = true;
    requestedPort = 0;
    browserError = "";
    fallback = new TailscaleSnapshot("stopping", "", "", 0, false, 0, "", "", false);
    control.execute(
        () -> {
          TailscaleSnapshot result = TailscaleSnapshot.stopped();
          try {
            Session active = session;
            Client client = active == null ? factory.create(25565, status -> {}) : active.client();
            if (active == null) session = new Session(epoch, 25565, client);
            client.logout();
            TailscaleClient.Status status = client.status();
            if (!status.error().isEmpty()) result = convert(status, 0, false);
          } catch (Exception e) {
            result = failed("JAVA_LOGOUT_FAILED", "Could not complete Tailscale logout", true);
          } finally {
            closeSession();
            synchronized (this) {
              if (generation == epoch) {
                loggingOut = false;
                fallback = result;
              }
            }
          }
        });
  }

  private void closeSession() {
    Session active = session;
    session = null;
    authUrl = "";
    if (active != null) {
      try {
        active.client().close();
      } catch (Exception e) {
        fallback = failed("JAVA_CLOSE_FAILED", "Could not close Java Tailscale", true);
      }
    }
  }

  @Override
  public void shutdown() {
    stop();
  }

  void awaitControlForTest() throws Exception {
    control.submit(() -> {}).get(15, TimeUnit.SECONDS);
  }

  private static TailscaleSnapshot failed(String code, String detail, boolean recoverable) {
    return new TailscaleSnapshot("failed", "", "", 0, false, 0, code, detail, recoverable);
  }
}
