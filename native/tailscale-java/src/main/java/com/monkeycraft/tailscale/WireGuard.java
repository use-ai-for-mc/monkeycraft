package com.monkeycraft.tailscale;

import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.Instant;
import java.util.*;
import java.util.function.LongSupplier;

/** WireGuard Noise IKpsk2 and transport. Based on the WireGuard protocol and MIT wireguard-go. */
final class WireGuard implements AutoCloseable {
  @FunctionalInterface
  interface Sender {
    void send(String peer, byte[] packet);
  }

  @FunctionalInterface
  interface Receiver {
    void receive(String peer, byte[] packet);
  }

  private static final byte[] INITIAL_CK =
      Crypto.hash(ascii("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"));
  private static final byte[] INITIAL_H =
      Crypto.hash(INITIAL_CK, ascii("WireGuard v1 zx2c4 Jason@zx2c4.com"));
  private static final long SECOND = 1_000_000_000L, REJECT_MESSAGES = -8193L;
  private final byte[] secret, publicKey, macKey, cookieKey;
  private final Sender sender;
  private final Receiver receiver;
  private final LongSupplier clock;
  private final Map<String, Peer> peers = new HashMap<>();
  private final Map<Integer, Session> sessions = new HashMap<>();
  private final Map<Integer, Peer> handshakes = new HashMap<>();
  private byte[] cookieSecret = Crypto.random(32);
  private long cookieBirth, tokenTime;
  private double tokens = 50;
  private boolean closed;

  WireGuard(byte[] secret, Sender sender, Receiver receiver) throws GeneralSecurityException {
    this(secret, sender, receiver, System::nanoTime);
  }

  WireGuard(byte[] secret, Sender sender, Receiver receiver, LongSupplier clock)
      throws GeneralSecurityException {
    this.secret = secret.clone();
    this.publicKey = Crypto.publicKey(secret);
    this.sender = sender;
    this.receiver = receiver;
    this.clock = clock;
    macKey = Crypto.hash(ascii("mac1----"), publicKey);
    cookieKey = Crypto.hash(ascii("cookie--"), publicKey);
    cookieBirth = tokenTime = clock.getAsLong();
  }

  synchronized void addPeer(byte[] key) {
    String id = Crypto.hex(key);
    peers.computeIfAbsent(id, k -> new Peer(key));
  }

  synchronized void removePeer(String id) {
    Peer p = peers.remove(id);
    if (p != null) {
      sessions
          .values()
          .removeIf(
              s -> {
                if (s.peer == p) {
                  s.erase();
                  return true;
                }
                return false;
              });
      handshakes.values().removeIf(v -> v == p);
      p.erase();
    }
  }

  synchronized void send(String peer, byte[] packet) {
    if (closed) return;
    Peer p = peers.get(peer);
    if (p == null || packet.length > 65_535) return;
    long now = clock.getAsLong();
    Session s = p.current;
    if (s != null && s.usable(now)) {
      transport(s, packet);
      if ((s.initiator && now - s.created >= 120 * SECOND) || s.counter >= 1L << 60)
        initiate(p, now);
    } else {
      if (p.queue.size() < 128) p.queue.add(packet.clone());
      initiate(p, now);
    }
  }

  /** Returns the authenticated peer identity, or null for rejected/unauthenticated packets. */
  synchronized String receive(byte[] packet, byte[] sourceAddress) {
    if (closed || packet.length < 4) return null;
    try {
      return switch (le(packet).getInt()) {
        case 1 -> consumeInitiation(packet, sourceAddress);
        case 2 -> consumeResponse(packet);
        case 3 -> {
          consumeCookie(packet);
          yield null;
        }
        case 4 -> consumeTransport(packet);
        default -> null;
      };
    } catch (GeneralSecurityException | IllegalArgumentException e) {
      return null;
    }
  }

  private void initiate(Peer p, long now) {
    if (p.handshake != null && now - p.lastInitiation < 5 * SECOND) return;
    if (p.attemptStart != 0 && now - p.attemptStart > 90 * SECOND) {
      p.queue.clear();
      p.clearHandshake();
      p.attemptStart = 0;
      return;
    }
    try {
      if (p.handshake != null) handshakes.remove(p.handshake.local);
      p.clearHandshake();
      Handshake h = new Handshake();
      h.local = newIndex();
      h.ephemeral = Crypto.privateKey();
      h.h = Crypto.hash(INITIAL_H, p.key);
      h.ck = INITIAL_CK.clone();
      byte[] e = Crypto.publicKey(h.ephemeral);
      h.mixKey(e);
      h.mixHash(e);
      byte[] encrypted = h.encrypt(h.mixDH(h.ephemeral, p.key), publicKey);
      byte[] timestamp = timestamp();
      byte[] ts = h.encrypt(h.mixDH(secret, p.key), timestamp);
      byte[] msg = le(148).putInt(1).putInt(h.local).put(e).put(encrypted).put(ts).array();
      p.handshake = h;
      handshakes.put(h.local, p);
      p.lastInitiation = now;
      if (p.attemptStart == 0) p.attemptStart = now;
      addMacs(p, msg);
      p.lastHandshakeMessage = msg;
      sender.send(p.id, msg);
    } catch (GeneralSecurityException e) {
      p.clearHandshake();
    }
  }

  private String consumeInitiation(byte[] msg, byte[] source) throws GeneralSecurityException {
    if (msg.length != 148 || !validMac(msg)) return null;
    long now = clock.getAsLong();
    tokens = Math.min(50, tokens + (now - tokenTime) * 50.0 / SECOND);
    tokenTime = now;
    if (tokens < 1) {
      if (source == null) return null;
      refreshCookie(now);
      byte[] cookie = Crypto.keyedHash(cookieSecret, 16, source);
      byte[] want = Crypto.keyedHash(cookie, 16, slice(msg, 0, 132));
      if (!MessageDigest.isEqual(want, slice(msg, 132, 148))) {
        // The sender identity is encrypted; the caller sends the returned cookie via its source
        // path.
        byte[] nonce = Crypto.random(24),
            sealed = Crypto.xaead(true, cookieKey, nonce, cookie, slice(msg, 116, 132));
        cookieReply = le(64).putInt(3).putInt(le(msg).getInt(4)).put(nonce).put(sealed).array();
        return null;
      }
    } else tokens -= 1;
    Handshake h = new Handshake();
    byte[] remoteEphemeral = slice(msg, 8, 40);
    h.h = Crypto.hash(INITIAL_H, publicKey);
    h.ck = INITIAL_CK.clone();
    h.mixHash(remoteEphemeral);
    h.mixKey(remoteEphemeral);
    byte[] remote = h.decrypt(h.mixDH(secret, remoteEphemeral), slice(msg, 40, 88));
    Peer p = peers.get(Crypto.hex(remote));
    if (p == null) return null;
    byte[] stamp = h.decrypt(h.mixDH(secret, p.key), slice(msg, 88, 116));
    if (Arrays.compareUnsigned(stamp, p.lastTimestamp) <= 0
        || now - p.lastReceivedInitiation < 20_000_000L) return null;
    p.lastTimestamp = stamp;
    p.lastReceivedInitiation = now;
    h.local = newIndex();
    h.remote = le(msg).getInt(4);
    h.ephemeral = Crypto.privateKey();
    byte[] ephemeral = Crypto.publicKey(h.ephemeral);
    h.mixHash(ephemeral);
    h.mixKey(ephemeral);
    h.mixKey(Crypto.dh(h.ephemeral, remoteEphemeral));
    h.mixKey(Crypto.dh(h.ephemeral, p.key));
    byte[] empty = h.encrypt(h.psk(), Crypto.EMPTY);
    byte[] response =
        le(92).putInt(2).putInt(h.local).putInt(h.remote).put(ephemeral).put(empty).array();
    byte[][] keys = Crypto.kdf(h.ck, Crypto.EMPTY, 2);
    Session s = new Session(p, h.local, h.remote, keys[1], keys[0], false, now);
    if (p.next != null) {
      sessions.remove(p.next.local);
      p.next.erase();
    }
    p.next = s;
    sessions.put(s.local, s);
    addMacs(p, response);
    p.lastHandshakeMessage = response;
    h.erase();
    sender.send(p.id, response);
    return p.id;
  }

  // A single event-loop consumes and sends this immediately, avoiding an unauthenticated peer
  // lookup.
  private byte[] cookieReply;

  synchronized byte[] takeCookieReply() {
    byte[] b = cookieReply;
    cookieReply = null;
    return b;
  }

  private String consumeResponse(byte[] msg) throws GeneralSecurityException {
    if (msg.length != 92 || !validMac(msg)) return null;
    Peer p = handshakes.get(le(msg).getInt(8));
    if (p == null || p.handshake == null) return null;
    Handshake original = p.handshake, h = original.copy();
    byte[] remote = slice(msg, 12, 44);
    try {
      h.mixHash(remote);
      h.mixKey(remote);
      h.mixKey(Crypto.dh(h.ephemeral, remote));
      h.mixKey(Crypto.dh(secret, remote));
      h.decrypt(h.psk(), slice(msg, 44, 60));
      byte[][] keys = Crypto.kdf(h.ck, Crypto.EMPTY, 2);
      Session s =
          new Session(p, h.local, le(msg).getInt(4), keys[0], keys[1], true, clock.getAsLong());
      handshakes.remove(h.local);
      p.clearHandshake();
      p.attemptStart = 0;
      promote(p, s);
      sessions.put(s.local, s);
      transport(s, Crypto.EMPTY);
      drain(p);
      return p.id;
    } finally {
      h.erase();
    }
  }

  private String consumeTransport(byte[] msg) throws GeneralSecurityException {
    if (msg.length < 32 || msg.length > 65_568) return null;
    ByteBuffer b = le(msg);
    Session s = sessions.get(b.getInt(4));
    long counter = b.getLong(8), now = clock.getAsLong();
    if (s == null || !s.usable(now) || !s.replay.mayAccept(counter)) return null;
    byte[] plain =
        Crypto.aead(
            false,
            s.rx,
            Crypto.nonce(counter, ByteOrder.LITTLE_ENDIAN),
            slice(msg, 16, msg.length),
            Crypto.EMPTY);
    if (!s.replay.accept(counter)) return null;
    if (s.peer.next == s) {
      s.peer.next = null;
      promote(s.peer, s);
      drain(s.peer);
    }
    s.lastReceive = now;
    if (plain.length > 0) {
      receiver.receive(s.peer.id, plain);
      s.keepaliveAt = now + 10 * SECOND;
    }
    if (s.initiator && now - s.created >= 165 * SECOND) initiate(s.peer, now);
    return s.peer.id;
  }

  private void transport(Session s, byte[] packet) {
    long now = clock.getAsLong();
    if (!s.usable(now)) return;
    try {
      int length = (packet.length + 15) & ~15;
      byte[] plain = Arrays.copyOf(packet, length);
      long counter = s.counter++;
      byte[] encrypted =
          Crypto.aead(
              true, s.tx, Crypto.nonce(counter, ByteOrder.LITTLE_ENDIAN), plain, Crypto.EMPTY);
      byte[] out =
          le(16 + encrypted.length)
              .putInt(4)
              .putInt(s.remote)
              .putLong(counter)
              .put(encrypted)
              .array();
      s.lastSend = now;
      s.keepaliveAt = 0;
      sender.send(s.peer.id, out);
    } catch (GeneralSecurityException e) {
      s.erase();
    }
  }

  private void promote(Peer p, Session s) {
    if (p.previous != null) {
      sessions.remove(p.previous.local);
      p.previous.erase();
    }
    p.previous = p.current;
    p.current = s;
  }

  private void drain(Peer p) {
    while (!p.queue.isEmpty() && p.current != null) transport(p.current, p.queue.remove());
  }

  private void consumeCookie(byte[] msg) throws GeneralSecurityException {
    if (msg.length != 64) return;
    int index = le(msg).getInt(4);
    Peer p = handshakes.get(index);
    if (p == null) {
      Session s = sessions.get(index);
      if (s != null) p = s.peer;
    }
    if (p == null || p.lastMac == null) return;
    byte[] cookie =
        Crypto.xaead(false, p.cookieKey, slice(msg, 8, 32), slice(msg, 32, 64), p.lastMac);
    if (cookie.length != 16) return;
    p.cookie = cookie;
    p.cookieSet = clock.getAsLong();
    if (p.lastHandshakeMessage != null) {
      byte[] retry = p.lastHandshakeMessage.clone();
      addMacs(p, retry);
      sender.send(p.id, retry);
    }
  }

  synchronized void tick() {
    if (closed) return;
    long now = clock.getAsLong();
    for (Peer p : peers.values()) {
      if (p.handshake != null && now - p.lastInitiation >= 5 * SECOND) initiate(p, now);
      if (p.current != null && p.current.keepaliveAt != 0 && now >= p.current.keepaliveAt)
        transport(p.current, Crypto.EMPTY);
    }
    sessions
        .values()
        .removeIf(
            s -> {
              if (!s.usable(now)) {
                s.erase();
                return true;
              }
              return false;
            });
  }

  private void addMacs(Peer p, byte[] msg) {
    int n = msg.length;
    byte[] mac = Crypto.keyedHash(p.macKey, 16, slice(msg, 0, n - 32));
    System.arraycopy(mac, 0, msg, n - 32, 16);
    p.lastMac = mac;
    Arrays.fill(msg, n - 16, n, (byte) 0);
    if (p.cookie != null && clock.getAsLong() - p.cookieSet < 120 * SECOND)
      System.arraycopy(Crypto.keyedHash(p.cookie, 16, slice(msg, 0, n - 16)), 0, msg, n - 16, 16);
  }

  private boolean validMac(byte[] m) {
    return MessageDigest.isEqual(
        Crypto.keyedHash(macKey, 16, slice(m, 0, m.length - 32)),
        slice(m, m.length - 32, m.length - 16));
  }

  private int newIndex() {
    int id;
    do {
      id = Crypto.RANDOM.nextInt();
    } while (id == 0 || sessions.containsKey(id) || handshakes.containsKey(id));
    return id;
  }

  private void refreshCookie(long now) {
    if (now - cookieBirth >= 120 * SECOND) {
      Arrays.fill(cookieSecret, (byte) 0);
      cookieSecret = Crypto.random(32);
      cookieBirth = now;
    }
  }

  static final class Replay {
    private long highest;
    private boolean initialized;
    private final long[] seen = new long[8192];

    Replay() {
      Arrays.fill(seen, -1L);
    }

    boolean mayAccept(long n) {
      return Long.compareUnsigned(n, REJECT_MESSAGES) < 0
          && (!initialized
              || Long.compareUnsigned(n, highest) > 0
              || Long.compareUnsigned(highest - n, 8192) < 0)
          && seen[(int) (n & 8191)] != n;
    }

    boolean accept(long n) {
      if (!mayAccept(n)) return false;
      seen[(int) (n & 8191)] = n;
      if (!initialized || Long.compareUnsigned(n, highest) > 0) highest = n;
      initialized = true;
      return true;
    }
  }

  private static final class Handshake {
    byte[] h, ck, ephemeral;
    int local, remote;

    void mixHash(byte[] data) {
      h = Crypto.hash(h, data);
    }

    void mixKey(byte[] data) {
      ck = Crypto.kdf(ck, data, 1)[0];
    }

    byte[] mixDH(byte[] a, byte[] b) throws GeneralSecurityException {
      byte[][] k = Crypto.kdf(ck, Crypto.dh(a, b), 2);
      ck = k[0];
      return k[1];
    }

    byte[] psk() {
      byte[][] k = Crypto.kdf(ck, new byte[32], 3);
      ck = k[0];
      mixHash(k[1]);
      return k[2];
    }

    byte[] encrypt(byte[] key, byte[] data) throws GeneralSecurityException {
      byte[] c = Crypto.aead(true, key, new byte[12], data, h);
      mixHash(c);
      return c;
    }

    byte[] decrypt(byte[] key, byte[] data) throws GeneralSecurityException {
      byte[] p = Crypto.aead(false, key, new byte[12], data, h);
      mixHash(data);
      return p;
    }

    Handshake copy() {
      Handshake c = new Handshake();
      c.h = h.clone();
      c.ck = ck.clone();
      c.ephemeral = ephemeral.clone();
      c.local = local;
      c.remote = remote;
      return c;
    }

    void erase() {
      for (byte[] b : new byte[][] {h, ck, ephemeral}) if (b != null) Arrays.fill(b, (byte) 0);
    }
  }

  private static final class Peer {
    final byte[] key, macKey, cookieKey;
    final String id;
    final ArrayDeque<byte[]> queue = new ArrayDeque<>();
    byte[] lastTimestamp = new byte[12], cookie, lastMac, lastHandshakeMessage;
    long lastReceivedInitiation = Long.MIN_VALUE / 2, lastInitiation, attemptStart, cookieSet;
    Handshake handshake;
    Session current, previous, next;

    Peer(byte[] key) {
      this.key = key.clone();
      id = Crypto.hex(key);
      macKey = Crypto.hash(ascii("mac1----"), key);
      cookieKey = Crypto.hash(ascii("cookie--"), key);
    }

    void clearHandshake() {
      if (handshake != null) handshake.erase();
      handshake = null;
    }

    void erase() {
      clearHandshake();
      queue.clear();
      for (Session s : new Session[] {current, previous, next}) if (s != null) s.erase();
    }
  }

  private static final class Session {
    final Peer peer;
    final int local, remote;
    final byte[] tx, rx;
    final boolean initiator;
    final long created;
    final Replay replay = new Replay();
    long counter, lastSend, lastReceive, keepaliveAt;
    boolean erased;

    Session(Peer p, int l, int r, byte[] tx, byte[] rx, boolean i, long now) {
      peer = p;
      local = l;
      remote = r;
      this.tx = tx;
      this.rx = rx;
      initiator = i;
      created = now;
    }

    boolean usable(long now) {
      return !erased
          && now - created < 180 * SECOND
          && Long.compareUnsigned(counter, REJECT_MESSAGES) < 0;
    }

    void erase() {
      erased = true;
      Arrays.fill(tx, (byte) 0);
      Arrays.fill(rx, (byte) 0);
    }
  }

  static byte[] timestamp() {
    Instant t = Instant.now();
    return ByteBuffer.allocate(12)
        .putLong(0x400000000000000aL + t.getEpochSecond())
        .putInt(t.getNano() & ~0xffffff)
        .array();
  }

  static ByteBuffer le(byte[] b) {
    return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN);
  }

  static ByteBuffer le(int n) {
    return le(new byte[n]);
  }

  static byte[] slice(byte[] b, int from, int to) {
    return Arrays.copyOfRange(b, from, to);
  }

  static byte[] ascii(String s) {
    return s.getBytes(StandardCharsets.US_ASCII);
  }

  public synchronized void close() {
    closed = true;
    for (Peer p : peers.values()) p.erase();
    peers.clear();
    sessions.clear();
    handshakes.clear();
    Arrays.fill(secret, (byte) 0);
    Arrays.fill(cookieSecret, (byte) 0);
  }
}
