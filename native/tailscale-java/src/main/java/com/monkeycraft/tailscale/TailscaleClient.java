package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import javax.net.ssl.*;

/**
 * Experimental in-process Java client for one tailnet TCP listener and a fixed loopback service.
 */
public final class TailscaleClient implements AutoCloseable {
  public record Config(
      Path stateDirectory,
      URI controlURL,
      String hostname,
      int listenPort,
      InetSocketAddress loopbackTarget) {
    public Config {
      Objects.requireNonNull(stateDirectory);
      Objects.requireNonNull(controlURL);
      Objects.requireNonNull(hostname);
      Objects.requireNonNull(loopbackTarget);
      if (listenPort < 1 || listenPort > 65535 || hostname.isBlank() || hostname.length() > 253)
        throw new IllegalArgumentException("invalid client configuration");
      if (loopbackTarget.isUnresolved()
          || !loopbackTarget.getAddress().isLoopbackAddress()
          || loopbackTarget.getPort() == 0)
        throw new IllegalArgumentException(
            "target must be a fixed numeric loopback address and port");
    }
  }

  public record Status(
      String state,
      String authURL,
      String nodeKey,
      List<String> addresses,
      String error,
      Map<String, Long> traffic) {}

  private final Config config;
  private final Consumer<Status> listener;
  private final IdentityStore identity;
  private final SSLSocketFactory tls;
  private final boolean labBlockUDP, labLoopback;
  private volatile Status status = new Status("stopped", "", "", List.of(), "", Map.of());
  private volatile boolean stopping, closed;
  private volatile ControlHttp control;
  private volatile DataPlane plane;
  private Thread worker;
  private ScheduledExecutorService updates;

  public TailscaleClient(Config config, Consumer<Status> listener) throws Exception {
    this(config, listener, (SSLSocketFactory) SSLSocketFactory.getDefault(), false, false);
  }

  TailscaleClient(
      Config config,
      Consumer<Status> listener,
      SSLSocketFactory tls,
      boolean labBlockUDP,
      boolean labLoopback)
      throws Exception {
    ControlHttp.validateURL(config.controlURL());
    this.config = config;
    this.listener = Objects.requireNonNull(listener);
    this.tls = tls;
    this.labBlockUDP = labBlockUDP;
    this.labLoopback = labLoopback;
    identity = new IdentityStore(config.stateDirectory());
  }

  public synchronized void start() {
    if (closed) throw new IllegalStateException("client closed");
    if (worker != null && worker.isAlive()) return;
    stopping = false;
    worker = new Thread(this::run, "tailscale-java-control");
    worker.setDaemon(true);
    worker.start();
  }

  void labDropUdp(boolean drop) {
    DataPlane d = plane;
    if (d != null) d.labDropUdp(drop);
  }

  public boolean isListening() {
    DataPlane d = plane;
    return !stopping && d != null && d.isListening();
  }

  public Status status() {
    Status s = status;
    DataPlane d = plane;
    return new Status(
        s.state, s.authURL, s.nodeKey, s.addresses, s.error, d == null ? s.traffic : d.stats());
  }

  public synchronized void login() throws Exception {
    stop();
    identity.loggedOut = false;
    identity.save();
    start();
  }

  private void run() {
    if (identity.loggedOut) {
      emit("needsLogin", "", List.of(), "");
      return;
    }
    int failures = 0;
    while (!stopping) {
      try {
        emit("starting", "", List.of(), "");
        if (stopping) return;
        control = new ControlHttp(config.controlURL(), identity.machine);
        while (!stopping) {
          register();
          if (stopping) return;
          AtomicBoolean dirty = new AtomicBoolean(true);
          DataPlane data =
              new DataPlane(
                  identity.node,
                  config.listenPort(),
                  config.loopbackTarget(),
                  tls,
                  labBlockUDP,
                  labLoopback,
                  () -> dirty.set(true),
                  code -> emit("error", "", List.of(), code));
          plane = data;
          NetworkMap map = new NetworkMap();
          updates =
              Executors.newSingleThreadScheduledExecutor(
                  r -> {
                    Thread t = new Thread(r, "tailscale-java-control-update");
                    t.setDaemon(true);
                    return t;
                  });
          updates.scheduleWithFixedDelay(
              () -> {
                if (stopping || !dirty.compareAndSet(true, false)) return;
                try {
                  JsonObject req = mapRequest(data, false);
                  req.addProperty("OmitPeers", true);
                  control.request("/machine/map", req, b -> {});
                } catch (Exception e) {
                  dirty.set(true);
                }
              },
              500,
              500,
              TimeUnit.MILLISECONDS);
          try {
            MapDecoder decoder =
                new MapDecoder(
                    message -> {
                      if (stopping) return;
                      boolean first = map.self == null;
                      map.update(message, first);
                      if (map.tailnetLock) throw new UnsupportedFeature("tailnet-lock");
                      try {
                        data.update(message, first);
                      } catch (Exception e) {
                        throw new IOException("cannot apply control map", e);
                      }
                      if (map.self != null) {
                        if (NetworkMap.expired(map.self)) throw new Expired();
                        List<String> addresses = new ArrayList<>();
                        if (map.self.has("Addresses"))
                          for (JsonElement a : map.self.getAsJsonArray("Addresses"))
                            addresses.add(a.getAsString().split("/", 2)[0]);
                        emit(
                            NetworkMap.bool(map.self, "MachineAuthorized", false)
                                ? "running"
                                : "needsApproval",
                            "",
                            List.copyOf(addresses),
                            "");
                      }
                      if (NetworkMap.present(message, "PopBrowserURL"))
                        emit(
                            status.state,
                            validAuthURL(message.get("PopBrowserURL").getAsString()),
                            status.addresses,
                            "");
                    });
            control.request("/machine/map", mapRequest(data, true), decoder::accept);
            throw new IOException("map stream ended");
          } catch (Expired expired) {
            emit("needsLogin", "", List.of(), "");
            identity.rotateNode();
          } finally {
            updates.shutdownNow();
            updates = null;
            data.close();
            plane = null;
          }
        }
      } catch (UnsupportedFeature unsupported) {
        emit("unsupported", "", List.of(), unsupported.code);
        return;
      } catch (Exception e) {
        if (!stopping) {
          emit("reconnecting", "", List.of(), "control-" + e.getClass().getSimpleName());
          try {
            Thread.sleep(Math.min(15_000, 500L << Math.min(failures++, 5)));
          } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return;
          }
        }
      } finally {
        ControlHttp h = control;
        if (h != null) h.close();
        control = null;
        DataPlane d = plane;
        if (d != null) d.close();
        plane = null;
        ScheduledExecutorService u = updates;
        if (u != null) u.shutdownNow();
        updates = null;
      }
    }
  }

  private void register() throws Exception {
    String followup = "";
    int rotations = 0;
    while (!stopping) {
      JsonObject request = registration();
      if (!followup.isEmpty()) request.addProperty("Followup", followup);
      JsonObject reply = control.post("/machine/register", request);
      if (!NetworkMap.string(reply, "Error", "").isEmpty())
        throw new IOException("control rejected registration");
      if (NetworkMap.present(reply, "NodeKeySignature")
          && !reply.get("NodeKeySignature").getAsString().isEmpty())
        throw new UnsupportedFeature("tailnet-lock");
      if (NetworkMap.bool(reply, "NodeKeyExpired", false)) {
        if (++rotations > 3) throw new IOException("repeated key expiry");
        identity.rotateNode();
        followup = "";
        continue;
      }
      String url = NetworkMap.string(reply, "AuthURL", "");
      if (!url.isEmpty()) {
        followup = validAuthURL(url);
        emit("needsLogin", followup, List.of(), "");
        continue;
      }
      identity.oldNode = null;
      identity.save();
      if (!NetworkMap.bool(reply, "MachineAuthorized", false))
        emit("needsApproval", "", List.of(), "");
      return;
    }
  }

  private JsonObject registration() throws Exception {
    JsonObject r = new JsonObject();
    r.addProperty("Version", ControlHttp.CAPABILITY);
    r.addProperty("NodeKey", "nodekey:" + Crypto.hex(Crypto.publicKey(identity.node)));
    if (identity.oldNode != null)
      r.addProperty("OldNodeKey", "nodekey:" + Crypto.hex(identity.oldNode));
    r.add("Hostinfo", hostinfo(null));
    return r;
  }

  private JsonObject mapRequest(DataPlane data, boolean stream) throws Exception {
    JsonObject r = new JsonObject();
    r.addProperty("Version", ControlHttp.CAPABILITY);
    r.addProperty("NodeKey", "nodekey:" + Crypto.hex(Crypto.publicKey(identity.node)));
    r.addProperty("DiscoKey", data.discoKey());
    r.addProperty("KeepAlive", true);
    r.addProperty("Stream", stream);
    r.add("Hostinfo", hostinfo(data));
    JsonArray eps = new JsonArray();
    for (String s : data.endpoints()) eps.add(s);
    r.add("Endpoints", eps);
    return r;
  }

  private JsonObject hostinfo(DataPlane data) {
    JsonObject h = new JsonObject();
    h.addProperty("Hostname", config.hostname());
    h.addProperty("OS", "java");
    h.addProperty("IPNVersion", "tailscale-java-research");
    if (data != null) {
      JsonObject n = new JsonObject();
      n.addProperty("PreferredDERP", data.home());
      h.add("NetInfo", n);
    }
    return h;
  }

  private static String validAuthURL(String s) throws IOException {
    try {
      URI uri = URI.create(s);
      if ((!uri.getScheme().equals("https") && !uri.getScheme().equals("http"))
          || uri.getHost() == null
          || uri.getUserInfo() != null) throw new IllegalArgumentException();
      return s;
    } catch (RuntimeException e) {
      throw new IOException("invalid login URL");
    }
  }

  private void emit(String state, String url, List<String> addresses, String error) {
    String key = "";
    try {
      key = "nodekey:" + Crypto.hex(Crypto.publicKey(identity.node));
    } catch (Exception ignored) {
    }
    Status next =
        new Status(state, url, key, addresses, error, plane == null ? Map.of() : plane.stats());
    Status previous = status;
    status = next;
    if (!next.state.equals(previous.state)
        || !next.authURL.equals(previous.authURL)
        || !next.nodeKey.equals(previous.nodeKey)
        || !next.addresses.equals(previous.addresses)
        || !next.error.equals(previous.error))
      try {
        listener.accept(next);
      } catch (RuntimeException ignored) {
      }
  }

  public void stop() {
    stopping = true;
    ControlHttp h = control;
    if (h != null) h.close();
    DataPlane d = plane;
    if (d != null) d.close();
    ScheduledExecutorService u = updates;
    if (u != null) u.shutdownNow();
    Thread t = worker;
    if (t != null && t != Thread.currentThread()) {
      t.interrupt();
      try {
        t.join(5000);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
    emit("stopped", "", List.of(), "");
  }

  public synchronized void logout() throws Exception {
    stop();
    String error = "";
    try (ControlHttp h = new ControlHttp(config.controlURL(), identity.machine)) {
      JsonObject r = registration();
      r.addProperty("Expiry", Instant.now().minusSeconds(60).toString());
      h.post("/machine/register", r);
    } catch (Exception e) {
      error = "remote-logout-unconfirmed";
    }
    identity.loggedOut = true;
    identity.rotateNode();
    identity.oldNode = null;
    identity.save();
    emit("needsLogin", "", List.of(), error);
  }

  public synchronized void close() throws IOException {
    if (closed) return;
    closed = true;
    stop();
    identity.close();
  }

  private static final class Expired extends IOException {}

  private static final class UnsupportedFeature extends IOException {
    final String code;

    UnsupportedFeature(String code) {
      this.code = code;
    }
  }

  private static final class MapDecoder {
    @FunctionalInterface
    interface Listener {
      void message(JsonObject object) throws IOException;
    }

    final Listener listener;
    byte[] buffer = new byte[8192];
    int start, end;

    MapDecoder(Listener listener) {
      this.listener = listener;
    }

    void accept(byte[] bytes) throws IOException {
      if (end + bytes.length > buffer.length) {
        if (start > 0) {
          System.arraycopy(buffer, start, buffer, 0, end - start);
          end -= start;
          start = 0;
        }
        if (end + bytes.length > buffer.length)
          buffer = Arrays.copyOf(buffer, Math.max(end + bytes.length, buffer.length * 2));
      }
      System.arraycopy(bytes, 0, buffer, end, bytes.length);
      end += bytes.length;
      while (end - start >= 4) {
        int n = ByteBuffer.wrap(buffer, start, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
        if (n < 0 || n > 16 * 1024 * 1024) throw new IOException("map message too large");
        if (end - start < n + 4) return;
        try {
          listener.message(
              JsonParser.parseString(new String(buffer, start + 4, n, StandardCharsets.UTF_8))
                  .getAsJsonObject());
        } catch (JsonParseException | IllegalStateException e) {
          throw new IOException("invalid map JSON", e);
        }
        start += n + 4;
      }
      if (start == end) {
        start = 0;
        end = 0;
      }
    }
  }
}
