package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.io.IOException;
import java.nio.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Adversarial protocol checks, independent of the Go/Tailscale end-to-end fixtures. */
public final class ProtocolTests {
  static void check(boolean condition, String name) {
    if (!condition) throw new AssertionError(name);
  }

  public static void main(String[] args) throws Exception {
    Properties vectors = new Properties();
    try (var in = Files.newInputStream(Path.of(args[0]))) {
      vectors.load(in);
    }
    java.util.function.Function<String, byte[]> b =
        k -> HexFormat.of().parseHex(vectors.getProperty(k));
    check(
        Arrays.equals(Crypto.dh(b.apply("aPrivate"), b.apply("bPublic")), b.apply("shared")),
        "X25519 Go vector");
    check(
        Arrays.equals(
            Crypto.xaead(
                true,
                b.apply("aeadKey"),
                b.apply("nonce24"),
                b.apply("plain"),
                WireGuard.ascii("cookie-mac1")),
            b.apply("xaead")),
        "XChaCha Go vector");
    try {
      Crypto.dh(Crypto.privateKey(), new byte[32]);
      throw new AssertionError("low-order key accepted");
    } catch (GeneralSecurityException expected) {
    }
    testWireGuard();
    testPolicy();
    testIdentity(Path.of(args[1]));
    System.out.println(
        "PROTOCOL_TESTS_OK java="
            + System.getProperty("java.version")
            + " Go-XChaCha-vector cookie rekey bad-tag replay forged-counter expired-key"
            + " unknown-peer policy-deltas spoofing IPv6 identity-lock restart-permissions");
  }

  record Frame(boolean toB, byte[] packet) {}

  static void testWireGuard() throws Exception {
    long[] clock = {1_000_000_000L};
    byte[] ka = Crypto.privateKey(), kb = Crypto.privateKey();
    String pa = Crypto.hex(Crypto.publicKey(ka)), pb = Crypto.hex(Crypto.publicKey(kb));
    ArrayDeque<Frame> frames = new ArrayDeque<>();
    List<byte[]> receivedA = new ArrayList<>(), receivedB = new ArrayList<>();
    try (WireGuard a =
            new WireGuard(
                ka,
                (p, m) -> frames.add(new Frame(true, m)),
                (p, m) -> receivedA.add(m),
                () -> clock[0]);
        WireGuard b =
            new WireGuard(
                kb,
                (p, m) -> frames.add(new Frame(false, m)),
                (p, m) -> receivedB.add(m),
                () -> clock[0])) {
      a.addPeer(Crypto.publicKey(kb));
      b.addPeer(Crypto.publicKey(ka));
      byte[] source = {127, 0, 0, 1, 42, 42};
      // Saturate the unauthenticated handshake budget with valid MAC1 but invalid X25519 keys.
      byte[] junk = ByteBuffer.allocate(148).order(ByteOrder.LITTLE_ENDIAN).putInt(1).array();
      byte[] mac =
          Crypto.keyedHash(
              Crypto.hash(WireGuard.ascii("mac1----"), Crypto.publicKey(kb)),
              16,
              Arrays.copyOf(junk, 116));
      System.arraycopy(mac, 0, junk, 116, 16);
      for (int i = 0; i < 50; i++)
        check(b.receive(junk, source) == null, "invalid initiation accepted");
      a.send(pb, WireGuard.ascii("first-payload"));
      Frame init = frames.remove();
      check(init.packet[0] == 1, "missing initiation");
      check(b.receive(init.packet, source) == null, "under-load handshake without cookie accepted");
      byte[] cookie = b.takeCookieReply();
      check(cookie != null && cookie[0] == 3, "cookie challenge absent");
      check(a.receive(cookie, source) == null, "cookie treated as authenticated transport");
      Frame retry = frames.remove();
      check(!Arrays.equals(init.packet, retry.packet), "MAC2 not added");
      check(pa.equals(b.receive(retry.packet, source)), "authenticated sender identity mismatch");
      check(!frames.isEmpty(), "cookie handshake did not produce response");
      pump(a, b, frames, source);
      check(receivedB.size() == 1, "initial payload not delivered");
      a.send(pb, WireGuard.ascii("authenticated"));
      Frame transport = frames.remove();
      check(transport.packet[0] == 4, "transport type");
      byte[] bad = transport.packet.clone();
      bad[bad.length - 1] ^= 1;
      check(b.receive(bad, source) == null, "bad tag accepted");
      byte[] forged = transport.packet.clone();
      ByteBuffer.wrap(forged).order(ByteOrder.LITTLE_ENDIAN).putLong(8, 1_000_000);
      check(b.receive(forged, source) == null, "forged counter accepted");
      check(
          pa.equals(b.receive(transport.packet, source)),
          "valid packet rejected after forged counter");
      int count = receivedB.size();
      check(
          b.receive(transport.packet, source) == null && receivedB.size() == count,
          "transport replay accepted");
      check(b.receive(init.packet, source) == null, "handshake replay accepted");
      b.takeCookieReply();
      clock[0] += 121_000_000_000L;
      Thread.sleep(30);
      a.send(pb, WireGuard.ascii("rekey-start"));
      boolean newHandshake = frames.stream().anyMatch(f -> f.packet[0] == 1);
      check(newHandshake, "missing time-based rekey");
      pump(a, b, frames, source);
      b.send(pa, WireGuard.ascii("reverse-new-session"));
      pump(a, b, frames, source);
      check(!receivedA.isEmpty(), "reverse packet after rekey");
      a.send(pb, WireGuard.ascii("expires"));
      Frame expired = frames.remove();
      clock[0] += 181_000_000_000L;
      check(b.receive(expired.packet, source) == null, "expired session accepted");
      a.removePeer(pb);
      a.send(pb, new byte[20]);
      check(frames.isEmpty(), "removed peer was sent traffic");
    }
    WireGuard.Replay replay = new WireGuard.Replay();
    check(
        replay.accept(8193) && replay.accept(2) && !replay.accept(1) && !replay.accept(2),
        "replay window edge");
    check(!replay.accept(-8193L), "message-limit accepted");
  }

  static void pump(WireGuard a, WireGuard b, ArrayDeque<Frame> frames, byte[] source) {
    int bound = 0;
    while (!frames.isEmpty()) {
      if (++bound > 100) throw new AssertionError("protocol loop");
      Frame f = frames.remove();
      (f.toB ? b : a).receive(f.packet, source);
    }
  }

  static JsonObject json(String s) {
    return JsonParser.parseString(s).getAsJsonObject();
  }

  static void testPolicy() throws Exception {
    String key = Crypto.hex(Crypto.publicKey(Crypto.privateKey()));
    NetworkMap m = new NetworkMap();
    m.update(
        json(
            "{\"Node\":{\"MachineAuthorized\":true,\"Addresses\":[\"100.64.0.1/32\",\"fd7a:115c:a1e0::1/128\"]},\"Peers\":[{\"ID\":2,\"Key\":\"nodekey:"
                + key
                + "\",\"MachineAuthorized\":true,\"Addresses\":[\"100.64.0.2/32\",\"fd7a:115c:a1e0::2/128\"]}],\"PacketFilter\":[{\"SrcIPs\":[\"100.64.0.0/24\"],\"IPProto\":[6],\"DstPorts\":[{\"IP\":\"*\",\"Ports\":{\"First\":9600,\"Last\":9600}}]}]}"),
        true);
    byte[] src = NetworkMap.ip("100.64.0.2"), dst = NetworkMap.ip("100.64.0.1");
    check(m.allows(key, src, dst, 9600), "allow rule");
    JsonObject peer = m.peers.get(2L);
    peer.remove("MachineAuthorized");
    check(m.allows(key, src, dst, 9600), "hosted peer without self-only authorization field rejected");
    peer.addProperty("MachineAuthorized", false);
    check(m.allows(key, src, dst, 9600), "peer authorization field treated as local machine status");
    for (String flag : List.of("Expired", "IsJailed", "UnsignedPeerAPIOnly")) {
      peer.addProperty(flag, true);
      check(!m.allows(key, src, dst, 9600), "restricted peer allowed: " + flag);
      peer.remove(flag);
    }
    m.self.remove("MachineAuthorized");
    check(!m.ready() && !m.allows(key, src, dst, 9600), "unapproved local machine allowed");
    m.self.addProperty("MachineAuthorized", true);

    check(!m.allows(key, src, dst, 9601), "wrong port allowed");
    check(!m.allows(key, NetworkMap.ip("100.64.0.3"), dst, 9600), "source spoof allowed");
    m.update(json("{\"PacketFilter\":null}"), false);
    check(m.allows(key, src, dst, 9600), "null filter lost prior policy");
    m.update(json("{\"PacketFilters\":{\"*\":null}}"), false);
    check(!m.allows(key, src, dst, 9600), "wildcard clear failed");
    m.update(
        json(
            "{\"PacketFilters\":{\"v6\":[{\"SrcIPs\":[\"fd7a:115c:a1e0::2-fd7a:115c:a1e0::3\"],\"DstPorts\":[{\"IP\":\"fd7a:115c:a1e0::/48\",\"Ports\":{\"First\":9600,\"Last\":9600}}]}]}}"),
        false);
    check(
        m.allows(key, NetworkMap.ip("fd7a:115c:a1e0::2"), NetworkMap.ip("fd7a:115c:a1e0::1"), 9600),
        "IPv6 grant");
    m.update(
        json("{\"PeersChangedPatch\":[{\"NodeID\":2,\"KeyExpiry\":\"2020-01-01T00:00:00Z\"}]}"),
        false);
    check(!m.allows(key, src, dst, 9600), "expired peer allowed");
    m.update(json("{\"TKAInfo\":{\"Disabled\":true}}"), false);
    check(!m.ready(), "unverified TKA disable accepted");
  }

  static void testIdentity(Path root) throws Exception {
    Path dir = Files.createTempDirectory(root, "identity-test-");
    byte[] machine, node;
    try (IdentityStore one = new IdentityStore(dir)) {
      machine = one.machine.clone();
      node = one.node.clone();
      try {
        new IdentityStore(dir);
        throw new AssertionError("concurrent identity writer");
      } catch (IOException expected) {
      }
    }
    try (IdentityStore two = new IdentityStore(dir)) {
      check(
          Arrays.equals(machine, two.machine) && Arrays.equals(node, two.node),
          "identity not restored");
      two.rotateNode();
      check(
          !Arrays.equals(node, two.node) && Arrays.equals(Crypto.publicKey(node), two.oldNode),
          "rotation not preserved");
    }
    if (Files.getFileAttributeView(dir, java.nio.file.attribute.PosixFileAttributeView.class)
        != null)
      check(
          Files.getPosixFilePermissions(dir.resolve("identity.json"))
              .equals(java.nio.file.attribute.PosixFilePermissions.fromString("rw-------")),
          "identity permissions");
    for (Path file : List.of(dir.resolve("identity.json"), dir.resolve("identity.lock")))
      Files.delete(file);
    Files.delete(dir);
  }
}
