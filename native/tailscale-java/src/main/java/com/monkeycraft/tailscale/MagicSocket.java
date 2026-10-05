package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import java.util.zip.CRC32;
import javax.net.ssl.*;

/**
 * UDP discovery/STUN and DERP fallback. Mutable path state is confined to the supplied event loop.
 */
final class MagicSocket implements AutoCloseable {
  @FunctionalInterface
  interface Inbound {
    String receive(String viaPeer, byte[] packet, InetSocketAddress source);
  }

  private static final byte[] MAGIC = "TS💬".getBytes(StandardCharsets.UTF_8);
  private final byte[] nodeSecret, nodePublic, discoSecret = Crypto.privateKey(), discoPublic;
  private final DatagramSocket udp;
  private final boolean blockUDP, loopback;
  private final Predicate<Runnable> execute;
  private final Inbound inbound;
  private final Runnable changed;
  private final SSLSocketFactory tls;
  private final ExecutorService connector;
  private final Map<String, Path> peers = new HashMap<>();
  private final Map<Integer, DerpClient> derps = new HashMap<>();
  private final Set<Integer> connecting = new HashSet<>();
  private final Map<Integer, Long> retryAt = new HashMap<>();
  private final Set<Socket> connectingSockets = ConcurrentHashMap.newKeySet();
  private final Map<String, Probe> probes = new HashMap<>();
  private final Map<String, Probe> stun = new HashMap<>();
  private final LinkedHashSet<InetSocketAddress> endpoints = new LinkedHashSet<>();
  private final Map<InetSocketAddress, Long> observedEndpoints = new HashMap<>();
  private volatile boolean labDropUdp;

  void labDropUdp(boolean drop) {
    labDropUdp = drop;
  }

  private JsonObject derpMap;
  private int home;
  private long nextStun, nextInterfaces;
  private volatile boolean closed;
  long directSent, derpSent, directReceived, derpReceived;

  private record Probe(String peer, InetSocketAddress target, long sent) {}

  private static final class Path {
    final String id;
    byte[] disco;
    int region;
    List<InetSocketAddress> endpoints = List.of();
    InetSocketAddress direct;
    long verified, lastProbe, lastActive;

    Path(String id) {
      this.id = id;
    }
  }

  MagicSocket(
      byte[] secret,
      SSLSocketFactory tls,
      boolean blockUDP,
      boolean loopback,
      Predicate<Runnable> execute,
      Inbound inbound,
      Runnable changed)
      throws Exception {
    nodeSecret = secret.clone();
    nodePublic = Crypto.publicKey(secret);
    discoPublic = Crypto.publicKey(discoSecret);
    this.tls = tls;
    this.blockUDP = blockUDP;
    this.loopback = loopback;
    this.execute = execute;
    this.inbound = inbound;
    this.changed = changed;
    udp = new DatagramSocket(new InetSocketAddress(0));
    udp.setReceiveBufferSize(1 << 20);
    connector =
        Executors.newFixedThreadPool(
            2,
            r -> {
              Thread t = new Thread(r, "tailscale-java-derp-connect");
              t.setDaemon(true);
              return t;
            });
    Thread reader = new Thread(this::readUDP, "tailscale-java-udp");
    reader.setDaemon(true);
    reader.start();
    refreshInterfaces();
  }

  String discoKey() {
    return "discokey:" + Crypto.hex(discoPublic);
  }

  int home() {
    return home;
  }

  List<String> endpoints() {
    return endpoints.stream().map(MagicSocket::format).toList();
  }

  void update(NetworkMap map) {
    if (closed) return;
    derpMap = map.derp;
    Set<String> retained = new HashSet<>();
    for (JsonObject p : map.peers.values()) {
      if (!NetworkMap.usable(p)) continue;
      String id = Crypto.hex(Crypto.key(p.get("Key").getAsString(), "nodekey:"));
      retained.add(id);
      Path path = peers.computeIfAbsent(id, Path::new);
      String dk = NetworkMap.string(p, "DiscoKey", "");
      byte[] disco = dk.isEmpty() ? null : Crypto.key(dk, "discokey:");
      if (!Arrays.equals(path.disco, disco)) {
        path.direct = null;
        path.verified = 0;
        path.disco = disco;
      }
      path.region = p.has("HomeDERP") ? p.get("HomeDERP").getAsInt() : 0;
      if (path.region == 0) {
        String old = NetworkMap.string(p, "DERP", "");
        if (old.startsWith("127.3.3.40:")) path.region = Integer.parseInt(old.substring(11));
      }
      ArrayList<InetSocketAddress> eps = new ArrayList<>();
      if (NetworkMap.present(p, "Endpoints"))
        for (JsonElement ep : p.getAsJsonArray("Endpoints")) {
          InetSocketAddress addr = parse(ep.getAsString());
          if (valid(addr) && eps.size() < 64) eps.add(addr);
        }
      path.endpoints = List.copyOf(eps);
    }
    peers.keySet().retainAll(retained);
    if (derpMap != null && NetworkMap.present(derpMap, "Regions")) {
      JsonObject regions = derpMap.getAsJsonObject("Regions");
      if (!regions.has(Integer.toString(home))) {
        home =
            regions.keySet().stream()
                .mapToInt(Integer::parseInt)
                .filter(
                    i ->
                        !NetworkMap.bool(
                            regions.getAsJsonObject(Integer.toString(i)), "Avoid", false))
                .min()
                .orElse(0);
        changed.run();
      }
      for (Integer id : new ArrayList<>(derps.keySet()))
        if (!regions.has(id.toString())) {
          derps.remove(id).close();
        }
      if (home != 0) ensureDerp(home);
    }
  }

  void send(String peer, byte[] packet) {
    if (closed) return;
    Path path = peers.get(peer);
    if (path == null) return;
    long now = System.nanoTime();
    path.lastActive = now;
    boolean direct = path.direct != null && now - path.verified < 15_000_000_000L && !blockUDP;
    if (direct) {
      sendUDP(path.direct, packet);
      directSent++;
    } else {
      int region = path.region != 0 ? path.region : home;
      DerpClient d = derps.get(region);
      if (d != null && d.send(peer, packet)) derpSent++;
      else ensureDerp(region);
    }
    if (now - path.lastProbe > 2_000_000_000L) probe(path, now);
  }

  private void probe(Path p, long now) {
    if (blockUDP || p.disco == null) return;
    p.lastProbe = now;
    LinkedHashSet<InetSocketAddress> destinations = new LinkedHashSet<>(p.endpoints);
    if (p.direct != null) destinations.add(p.direct);
    for (InetSocketAddress address : destinations) {
      if (probes.size() >= 4096) break;
      byte[] id = Crypto.random(12);
      probes.put(Crypto.hex(id), new Probe(p.id, address, now));
      disco(
          p,
          address,
          ByteBuffer.allocate(46).put((byte) 1).put((byte) 0).put(id).put(nodePublic).array());
    }
    DerpClient relay = derps.get(p.region != 0 ? p.region : home);
    if (relay != null) {
      ByteBuffer msg = ByteBuffer.allocate(2 + 18 * endpoints.size()).put((byte) 3).put((byte) 0);
      for (InetSocketAddress ep : endpoints) msg.put(encodeEndpoint(ep));
      try {
        relay.send(p.id, wrap(p, msg.array()));
      } catch (GeneralSecurityException ignored) {
      }
    }
  }

  private void disco(Path p, InetSocketAddress target, byte[] payload) {
    try {
      sendUDP(target, wrap(p, payload));
    } catch (GeneralSecurityException ignored) {
    }
  }

  private byte[] wrap(Path p, byte[] msg) throws GeneralSecurityException {
    return Crypto.concat(MAGIC, discoPublic, Crypto.box(discoSecret, p.disco, msg));
  }

  private void receive(String viaPeer, byte[] packet, InetSocketAddress source) {
    if (closed) return;
    if (packet.length >= 6 && Arrays.equals(Arrays.copyOf(packet, 6), MAGIC)) {
      receiveDisco(viaPeer, packet, source);
      return;
    }
    String authenticated = inbound.receive(viaPeer, packet, source);
    if (authenticated != null) {
      if (source == null) derpReceived++;
      else {
        directReceived++;
        Path p = peers.get(authenticated);
        if (p != null && packet.length > 0 && packet[0] == 4) {
          p.direct = source;
          p.verified = System.nanoTime();
        }
      }
    }
  }

  private void receiveDisco(String viaPeer, byte[] packet, InetSocketAddress source) {
    if (packet.length < 78) return;
    byte[] publicKey = Arrays.copyOfRange(packet, 6, 38);
    List<Path> possible =
        peers.values().stream()
            .filter(
                p ->
                    p.disco != null
                        && Arrays.equals(p.disco, publicKey)
                        && (viaPeer == null || viaPeer.equals(p.id)))
            .toList();
    if (possible.isEmpty()) return;
    try {
      byte[] msg =
          Crypto.openBox(discoSecret, publicKey, Arrays.copyOfRange(packet, 38, packet.length));
      if (msg.length < 2) return;
      long now = System.nanoTime();
      switch (msg[0]) {
        case 1 -> {
          if (msg.length < 14) return;
          Path p = possible.get(0);
          if (msg.length >= 46) {
            String claimed = Crypto.hex(Arrays.copyOfRange(msg, 14, 46));
            p = possible.stream().filter(x -> x.id.equals(claimed)).findFirst().orElse(null);
            if (p == null) return;
          }
          if (source != null) {
            disco(
                p,
                source,
                ByteBuffer.allocate(32)
                    .put((byte) 2)
                    .put((byte) 0)
                    .put(msg, 2, 12)
                    .put(encodeEndpoint(source))
                    .array());
            if (now - p.lastProbe > 2_000_000_000L) {
              p.lastProbe = now;
              byte[] id = Crypto.random(12);
              probes.put(Crypto.hex(id), new Probe(p.id, source, now));
              disco(
                  p,
                  source,
                  ByteBuffer.allocate(46)
                      .put((byte) 1)
                      .put((byte) 0)
                      .put(id)
                      .put(nodePublic)
                      .array());
            }
          }
        }
        case 2 -> {
          if (msg.length < 32 || source == null) return;
          String id = Crypto.hex(Arrays.copyOfRange(msg, 2, 14));
          Probe sent = probes.get(id);
          if (sent == null || now - sent.sent > 10_000_000_000L || !sent.target.equals(source))
            return;
          Path p = peers.get(sent.peer);
          if (p == null || !possible.contains(p)) return;
          probes.remove(id);
          p.direct = source;
          p.verified = now;
        }
        case 3 -> {
          if (source != null || viaPeer == null || msg[1] != 0 || (msg.length - 2) % 18 != 0)
            return;
          Path p = possible.get(0);
          List<InetSocketAddress> extra = new ArrayList<>(p.endpoints);
          for (int i = 2; i + 18 <= msg.length && extra.size() < 64; i += 18) {
            InetSocketAddress ep = decodeEndpoint(msg, i);
            if (valid(ep) && !extra.contains(ep)) extra.add(ep);
          }
          p.endpoints = List.copyOf(extra);
          if (now - p.lastProbe > 500_000_000L) probe(p, now);
        }
        default -> {}
      }
    } catch (GeneralSecurityException | IllegalArgumentException ignored) {
    }
  }

  private void ensureDerp(int id) {
    if (id == 0
        || closed
        || derps.containsKey(id)
        || connecting.contains(id)
        || System.nanoTime() < retryAt.getOrDefault(id, 0L)
        || derpMap == null) return;
    JsonObject regions = derpMap.getAsJsonObject("Regions");
    if (regions == null || !regions.has(Integer.toString(id))) return;
    List<JsonObject> nodes = new ArrayList<>();
    for (JsonElement e : regions.getAsJsonObject(Integer.toString(id)).getAsJsonArray("Nodes"))
      if (!NetworkMap.bool(e.getAsJsonObject(), "STUNOnly", false))
        nodes.add(e.getAsJsonObject().deepCopy());
    connecting.add(id);
    connector.execute(
        () -> {
          DerpClient connected = null;
          for (JsonObject node : nodes) {
            if (closed) break;
            try {
              connected =
                  new DerpClient(
                      node,
                      nodeSecret,
                      tls,
                      connectingSockets,
                      (peer, packet) -> execute.test(() -> receive(peer, packet, null)),
                      e ->
                          execute.test(
                              () -> {
                                DerpClient old = derps.remove(id);
                                if (old != null) old.close();
                                retryAt.put(id, System.nanoTime() + 2_000_000_000L);
                              }));
              break;
            } catch (Exception ignored) {
            }
          }
          DerpClient result = connected;
          if (!execute.test(
              () -> {
                connecting.remove(id);
                if (closed) {
                  if (result != null) result.close();
                  return;
                }
                if (result != null) {
                  derps.put(id, result);
                  nextStun = 0;
                  for (Path p : peers.values()) if (p.region == id) probe(p, System.nanoTime());
                } else retryAt.put(id, System.nanoTime() + 2_000_000_000L);
              })) {
            if (result != null) result.close();
          }
        });
  }

  void tick() {
    if (closed) return;
    long now = System.nanoTime();
    if (now >= nextInterfaces) {
      nextInterfaces = now + 20_000_000_000L;
      refreshInterfaces();
    }
    if (now >= nextStun) {
      nextStun = now + 20_000_000_000L;
      requestStun(now);
      ensureDerp(home);
      for (Path p : peers.values())
        if (now - p.lastActive < 60_000_000_000L) ensureDerp(p.region != 0 ? p.region : home);
    }
    for (Path p : peers.values())
      if (now - p.lastActive < 60_000_000_000L && now - p.lastProbe > 5_000_000_000L) probe(p, now);
    probes.values().removeIf(p -> now - p.sent > 10_000_000_000L);
    stun.values().removeIf(p -> now - p.sent > 10_000_000_000L);
  }

  private void requestStun(long now) {
    if (blockUDP || derpMap == null || !NetworkMap.present(derpMap, "Regions")) return;
    for (JsonElement region : derpMap.getAsJsonObject("Regions").asMap().values())
      for (JsonElement e : region.getAsJsonObject().getAsJsonArray("Nodes")) {
        JsonObject n = e.getAsJsonObject();
        int port = n.has("STUNPort") ? n.get("STUNPort").getAsInt() : 0;
        if (port < 0) continue;
        if (port == 0) port = 3478;
        String ip = NetworkMap.string(n, "IPv4", "");
        if (ip.isEmpty() || ip.equals("none")) continue;
        InetSocketAddress target;
        try {
          target = new InetSocketAddress(InetAddress.getByAddress(NetworkMap.ip(ip)), port);
        } catch (Exception bad) {
          continue;
        }
        byte[] tx = Crypto.random(12);
        ByteBuffer b =
            ByteBuffer.allocate(40)
                .putShort((short) 1)
                .putShort((short) 20)
                .putInt(0x2112a442)
                .put(tx)
                .putShort((short) 0x8022)
                .putShort((short) 8)
                .put("tailnode".getBytes(StandardCharsets.US_ASCII));
        CRC32 crc = new CRC32();
        crc.update(b.array(), 0, 32);
        b.putShort((short) 0x8028).putShort((short) 4).putInt((int) crc.getValue() ^ 0x5354554e);
        stun.put(Crypto.hex(tx), new Probe("", target, now));
        sendUDP(target, b.array());
      }
  }

  private void receiveStun(byte[] packet, InetSocketAddress from) {
    if (packet.length < 20) return;
    ByteBuffer b = ByteBuffer.wrap(packet);
    if (b.getShort() != 0x101) return;
    int length = Short.toUnsignedInt(b.getShort());
    if (length + 20 != packet.length || b.getInt() != 0x2112a442) return;
    byte[] tx = new byte[12];
    b.get(tx);
    String id = Crypto.hex(tx);
    Probe p = stun.get(id);
    if (p == null || !p.target.equals(from) || System.nanoTime() - p.sent > 10_000_000_000L) return;
    for (int off = 20; off + 4 <= packet.length; ) {
      int type = Short.toUnsignedInt(b.getShort(off)), n = Short.toUnsignedInt(b.getShort(off + 2));
      if (off + 4 + n > packet.length) return;
      if (type == 0x20 && (n == 8 || n == 20)) {
        int fam = packet[off + 5] & 255;
        if ((fam != 1 || n != 8) && (fam != 2 || n != 20)) return;
        int port = Short.toUnsignedInt(b.getShort(off + 6)) ^ 0x2112;
        byte[] ip = Arrays.copyOfRange(packet, off + 8, off + 4 + n),
            mask = ByteBuffer.allocate(16).putInt(0x2112a442).put(tx).array();
        for (int i = 0; i < ip.length; i++) ip[i] ^= mask[i];
        try {
          InetSocketAddress observed = new InetSocketAddress(InetAddress.getByAddress(ip), port);
          if (valid(observed)) {
            observedEndpoints.put(observed, System.nanoTime());
            if (endpoints.add(observed)) changed.run();
          }
          stun.remove(id);
        } catch (UnknownHostException ignored) {
        }
        return;
      }
      off += 4 + ((n + 3) & ~3);
    }
  }

  private void refreshInterfaces() {
    LinkedHashSet<InetSocketAddress> next = new LinkedHashSet<>();
    try {
      for (NetworkInterface n : Collections.list(NetworkInterface.getNetworkInterfaces()))
        if (n.isUp())
          for (InetAddress a : Collections.list(n.getInetAddresses())) {
            InetSocketAddress ep = new InetSocketAddress(a, udp.getLocalPort());
            if (valid(ep)) next.add(ep);
          }
    } catch (SocketException ignored) {
    }
    observedEndpoints.entrySet().removeIf(e -> System.nanoTime() - e.getValue() > 60_000_000_000L);
    next.addAll(observedEndpoints.keySet());
    if (!next.equals(endpoints)) {
      endpoints.clear();
      endpoints.addAll(next);
      changed.run();
    }
  }

  private void readUDP() {
    byte[] buffer = new byte[65_536];
    while (!closed) {
      try {
        DatagramPacket p = new DatagramPacket(buffer, buffer.length);
        udp.receive(p);
        if (blockUDP || labDropUdp) continue;
        byte[] bytes =
            Arrays.copyOfRange(p.getData(), p.getOffset(), p.getOffset() + p.getLength());
        InetSocketAddress from = (InetSocketAddress) p.getSocketAddress();
        execute.test(
            () -> {
              if (bytes.length >= 20 && bytes[0] == 1 && bytes[1] == 1) receiveStun(bytes, from);
              else receive(null, bytes, from);
            });
      } catch (IOException e) {
        if (!closed) execute.test(this::close);
        return;
      }
    }
  }

  void sendRaw(InetSocketAddress source, byte[] packet) {
    sendUDP(source, packet);
  }

  private void sendUDP(InetSocketAddress destination, byte[] packet) {
    if (blockUDP || labDropUdp || closed || destination == null) return;
    try {
      udp.send(new DatagramPacket(packet, packet.length, destination));
    } catch (IOException ignored) {
    }
  }

  private boolean valid(InetSocketAddress e) {
    return e != null
        && !e.isUnresolved()
        && e.getPort() > 0
        && !e.getAddress().isAnyLocalAddress()
        && !e.getAddress().isMulticastAddress()
        && !e.getAddress().isLinkLocalAddress()
        && (loopback || !e.getAddress().isLoopbackAddress());
  }

  static InetSocketAddress parse(String s) {
    try {
      int colon = s.lastIndexOf(':');
      if (colon < 1) return null;
      String ip = s.substring(0, colon);
      if (ip.startsWith("[") && ip.endsWith("]")) ip = ip.substring(1, ip.length() - 1);
      return new InetSocketAddress(
          InetAddress.getByAddress(NetworkMap.ip(ip)), Integer.parseInt(s.substring(colon + 1)));
    } catch (Exception e) {
      return null;
    }
  }

  static String format(InetSocketAddress e) {
    String ip = e.getAddress().getHostAddress();
    return (ip.contains(":") ? "[" + ip + "]" : ip) + ":" + e.getPort();
  }

  static byte[] encodeEndpoint(InetSocketAddress e) {
    byte[] ip = e.getAddress().getAddress();
    ByteBuffer b = ByteBuffer.allocate(18);
    if (ip.length == 4) b.position(10).putShort((short) 0xffff);
    b.put(ip).putShort((short) e.getPort());
    return b.array();
  }

  static InetSocketAddress decodeEndpoint(byte[] b, int off) {
    try {
      return new InetSocketAddress(
          InetAddress.getByAddress(Arrays.copyOfRange(b, off, off + 16)),
          Short.toUnsignedInt(ByteBuffer.wrap(b, off + 16, 2).getShort()));
    } catch (UnknownHostException e) {
      throw new IllegalArgumentException(e);
    }
  }

  public void close() {
    closed = true;
    udp.close();
    connector.shutdownNow();
    for (Socket socket : connectingSockets)
      try {
        socket.close();
      } catch (IOException ignored) {
      }
    connectingSockets.clear();
    for (DerpClient d : derps.values()) d.close();
    derps.clear();
    Arrays.fill(nodeSecret, (byte) 0);
    Arrays.fill(discoSecret, (byte) 0);
  }
}
