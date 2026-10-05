package com.monkeycraft.tailscale;

import com.google.gson.*;
import io.github.shri299.wirefin.ip.IpAddress;
import io.github.shri299.wirefin.ipv4.Ipv4Address;
import io.github.shri299.wirefin.ipv6.Ipv6Address;
import io.github.shri299.wirefin.runtime.PacketProcessor;
import io.github.shri299.wirefin.tcp.connection.*;
import io.github.shri299.wirefin.tcp.state.TcpState;
import java.io.*;
import java.net.*;
import java.nio.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import javax.net.ssl.*;

/** Decrypted virtual IP -> policy -> Java TCP -> one fixed loopback destination. */
final class DataPlane implements AutoCloseable {
  private final ArrayBlockingQueue<Runnable> queue = new ArrayBlockingQueue<>(4096);
  private final Thread loop;
  private final WireGuard wireguard;
  private final MagicSocket magic;
  private final NetworkMap map = new NetworkMap();
  private final int listenPort;
  private final InetSocketAddress target;
  private final Consumer<String> error;
  private final Map<TcpConnection, Bridge> bridges = new HashMap<>();
  private final Set<String> wirePeers = new HashSet<>();
  private PacketProcessor stack;
  private volatile boolean listening;
  private List<String> addresses = List.of();
  private volatile boolean closed;
  private String processingPeer;
  private final ConcurrentHashMap<String, String> routes = new ConcurrentHashMap<>();
  private volatile List<String> endpointSnapshot = List.of();
  private volatile int homeSnapshot;
  private volatile Map<String, Long> stats = Map.of();

  DataPlane(
      byte[] secret,
      int listenPort,
      InetSocketAddress target,
      SSLSocketFactory tls,
      boolean blockUdp,
      boolean allowLoopback,
      Runnable endpointsChanged,
      Consumer<String> error)
      throws Exception {
    if (!target.getAddress().isLoopbackAddress())
      throw new IllegalArgumentException("target must be fixed loopback");
    this.listenPort = listenPort;
    this.target = target;
    this.error = error;
    wireguard = new WireGuard(secret, this::encrypted, this::decrypted);
    magic =
        new MagicSocket(
            secret,
            tls,
            blockUdp,
            allowLoopback,
            this::enqueue,
            (peer, packet, source) -> {
              String authenticated =
                  wireguard.receive(
                      packet, source == null ? null : MagicSocket.encodeEndpoint(source));
              byte[] cookie = wireguard.takeCookieReply();
              if (cookie != null && source != null) magicSendRaw(source, cookie);
              return authenticated;
            },
            () -> {
              endpointsChanged.run();
            });
    loop = new Thread(this::run, "tailscale-java-data");
    loop.setDaemon(true);
    loop.start();
  }

  private void magicSendRaw(InetSocketAddress source, byte[] cookie) {
    magic.sendRaw(source, cookie);
  }

  void labDropUdp(boolean drop) {
    magic.labDropUdp(drop);
  }

  String discoKey() {
    return magic.discoKey();
  }

  List<String> endpoints() {
    return endpointSnapshot;
  }

  int home() {
    return homeSnapshot;
  }

  boolean isListening() {
    return listening && !closed;
  }

  Map<String, Long> stats() {
    return stats;
  }

  private boolean enqueue(Runnable r) {
    return !closed && queue.offer(r);
  }

  void update(JsonObject response, boolean first) throws Exception {
    CompletableFuture<Void> applied = new CompletableFuture<>();
    if (closed
        || !queue.offer(
            () -> {
              try {
                map.update(response, first);
                applyMap();
                applied.complete(null);
              } catch (Exception e) {
                dropStack();
                applied.completeExceptionally(e);
              }
            },
            5,
            TimeUnit.SECONDS)) throw new IOException("data plane unavailable");
    applied.get(10, TimeUnit.SECONDS);
  }

  private void applyMap() throws Exception {
    magic.update(map);
    Set<String> active = new HashSet<>();
    routes.clear();
    for (JsonObject p : map.peers.values())
      if (NetworkMap.usable(p)) {
        byte[] key = Crypto.key(p.get("Key").getAsString(), "nodekey:");
        String id = Crypto.hex(key);
        active.add(id);
        if (!wirePeers.contains(id)) wireguard.addPeer(key);
        if (NetworkMap.present(p, "Addresses"))
          for (JsonElement a : p.getAsJsonArray("Addresses"))
            routes.put(Crypto.hex(NetworkMap.ip(a.getAsString().split("/", 2)[0])), id);
      }
    for (String id : wirePeers) if (!active.contains(id)) wireguard.removePeer(id);
    wirePeers.clear();
    wirePeers.addAll(active);
    if (!map.ready()) {
      dropStack();
      return;
    }
    List<String> now = new ArrayList<>();
    for (JsonElement e : map.self.getAsJsonArray("Addresses"))
      now.add(e.getAsString().split("/", 2)[0]);
    if (stack == null || !now.equals(addresses)) {
      dropStack();
      addresses = List.copyOf(now);
      List<IpAddress> local = new ArrayList<>();
      for (String a : addresses) {
        byte[] b = NetworkMap.ip(a);
        local.add(
            b.length == 4 ? new Ipv4Address(ByteBuffer.wrap(b).getInt()) : new Ipv6Address(b));
      }
      TcpConnection.Config tcp =
          new TcpConnection.Config(
              65_535,
              1200,
              536,
              Duration.ofSeconds(1),
              Duration.ofSeconds(1),
              Duration.ofSeconds(60),
              Duration.ofSeconds(60));
      stack =
          new PacketProcessor(
              local,
              () -> Integer.toUnsignedLong(Crypto.RANDOM.nextInt()),
              this::outbound,
              System::nanoTime,
              tcp);
      stack.listen(
          listenPort,
          64,
          false,
          c -> {
            stack.accepted(c.key());
            if (bridges.size() >= 16) {
              stack.cancel(c);
              return;
            }
            String peer = routes.get(Crypto.hex(c.key().remoteAddress().bytes()));
            if (peer == null
                || !map.allows(
                    peer,
                    c.key().remoteAddress().bytes(),
                    c.key().localAddress().bytes(),
                    listenPort)) {
              stack.cancel(c);
              return;
            }
            Bridge bridge = new Bridge(c, peer);
            bridges.put(c, bridge);
            bridge.start();
          });
      listening = true;
    }
    for (Bridge b : new ArrayList<>(bridges.values()))
      if (!map.allows(
          b.peer,
          b.c.key().remoteAddress().bytes(),
          b.c.key().localAddress().bytes(),
          listenPort)) {
        b.close();
        stack.cancel(b.c);
        bridges.remove(b.c);
      }
  }

  private void encrypted(String peer, byte[] packet) {
    magic.send(peer, packet);
  }

  private void decrypted(String peer, byte[] packet) {
    if (stack == null) return;
    NetworkMap.Packet parsed = NetworkMap.tcp(packet);
    if (parsed == null
        || parsed.destinationPort() != listenPort
        || !map.allows(peer, parsed.source(), parsed.destination(), parsed.destinationPort()))
      return;
    processingPeer = peer;
    try {
      for (byte[] response : stack.process(Arrays.copyOf(packet, parsed.length())))
        wireguard.send(peer, response);
    } catch (IllegalArgumentException malformed) {
      /* Drop malformed packet. */
    } finally {
      processingPeer = null;
    }
  }

  private void outbound(byte[] packet) {
    NetworkMap.Packet parsed = NetworkMap.tcp(packet);
    if (parsed == null || parsed.sourcePort() != listenPort) return;
    String peer = routes.get(Crypto.hex(parsed.destination()));
    if (peer != null && map.allows(peer, parsed.destination(), parsed.source(), listenPort))
      wireguard.send(peer, packet);
  }

  private void run() {
    try {
      while (!closed) {
        Runnable task = queue.poll(10, TimeUnit.MILLISECONDS);
        if (task != null) task.run();
        for (int i = 0; i < 100 && (task = queue.poll()) != null; i++) task.run();
        if (map.self != null && NetworkMap.expired(map.self)) dropStack();
        if (stack != null) {
          for (Bridge b : new ArrayList<>(bridges.values())) b.tick();
          stack.pollRetransmissions(System.nanoTime());
        }
        wireguard.tick();
        magic.tick();
        endpointSnapshot = magic.endpoints();
        homeSnapshot = magic.home();
        stats =
            Map.of(
                "directSent",
                magic.directSent,
                "derpSent",
                magic.derpSent,
                "directReceived",
                magic.directReceived,
                "derpReceived",
                magic.derpReceived,
                "connections",
                (long) bridges.size());
      }
    } catch (InterruptedException expected) {
      Thread.currentThread().interrupt();
    } catch (Exception e) {
      error.accept("data-plane-" + e.getClass().getSimpleName());
    } finally {
      closed = true;
      dropStack();
      wireguard.close();
      magic.close();
    }
  }

  private void dropStack() {
    listening = false;
    for (Bridge b : bridges.values()) b.close();
    bridges.clear();
    stack = null;
    addresses = List.of();
  }

  private final class Bridge implements AutoCloseable {
    final TcpConnection c;
    final String peer;
    final ArrayBlockingQueue<byte[]> toHost = new ArrayBlockingQueue<>(32),
        toTail = new ArrayBlockingQueue<>(32);
    final Socket socket = new Socket();
    volatile boolean failed, connected, ended;
    boolean sentHostEOF, sentTailEOF;
    Thread reader, writer;

    Bridge(TcpConnection c, String peer) {
      this.c = c;
      this.peer = peer;
    }

    void start() {
      reader =
          new Thread(
              () -> {
                try {
                  socket.connect(target, 5000);
                  socket.setTcpNoDelay(true);
                  connected = true;
                  writer =
                      new Thread(
                          () -> {
                            try {
                              OutputStream out = socket.getOutputStream();
                              while (!ended) {
                                byte[] data = toHost.take();
                                if (data.length == 0) {
                                  socket.shutdownOutput();
                                  return;
                                }
                                out.write(data);
                              }
                            } catch (Exception e) {
                              if (!ended) failed = true;
                            }
                          },
                          "tailscale-java-loopback-write");
                  writer.setDaemon(true);
                  writer.start();
                  InputStream in = socket.getInputStream();
                  byte[] buf = new byte[16_384];
                  int n;
                  while ((n = in.read(buf)) >= 0) if (n > 0) toTail.put(Arrays.copyOf(buf, n));
                  toTail.put(new byte[0]);
                } catch (Exception e) {
                  if (!ended) failed = true;
                }
              },
              "tailscale-java-loopback-read");
      reader.setDaemon(true);
      reader.start();
    }

    void tick() throws InterruptedException {
      if (failed || c.state() == TcpState.CLOSED || c.state() == TcpState.TIME_WAIT) {
        close();
        stack.cancel(c);
        bridges.remove(c);
        return;
      }
      if (!connected) return;
      if (c.readableBytes() > 0 && toHost.remainingCapacity() > 0) {
        byte[] b = new byte[Math.min(c.readableBytes(), 16_384)];
        int n = c.read(b, 0, b.length);
        if (n > 0) toHost.offer(Arrays.copyOf(b, n));
      }
      if (c.endOfStream()
          && c.readableBytes() == 0
          && !sentHostEOF
          && toHost.remainingCapacity() > 0) {
        toHost.offer(new byte[0]);
        sentHostEOF = true;
      }
      if (!sentTailEOF
          && c.pendingSendBytes() < 512 * 1024
          && (c.state() == TcpState.ESTABLISHED || c.state() == TcpState.CLOSE_WAIT)) {
        byte[] b = toTail.poll();
        if (b != null) {
          if (b.length == 0) {
            stack.transmit(c, c.close(System.nanoTime()));
            sentTailEOF = true;
          } else stack.transmit(c, c.send(b, System.nanoTime()));
        }
      }
    }

    public void close() {
      ended = true;
      try {
        socket.close();
      } catch (IOException ignored) {
      }
      if (reader != null) reader.interrupt();
      if (writer != null) writer.interrupt();
      toHost.clear();
      toTail.clear();
    }
  }

  public void close() {
    closed = true;
    loop.interrupt();
    if (Thread.currentThread() != loop)
      try {
        loop.join(5000);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
  }
}
