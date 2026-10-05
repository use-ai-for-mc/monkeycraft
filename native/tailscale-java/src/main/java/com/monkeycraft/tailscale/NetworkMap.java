package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.net.*;
import java.nio.*;
import java.time.*;
import java.util.*;

/** Control-map delta merge plus fail-closed filtering for the single TCP service. */
final class NetworkMap {
  JsonObject self, derp;
  final Map<Long, JsonObject> peers = new HashMap<>();
  final Map<String, JsonArray> filters = new TreeMap<>();
  boolean tailnetLock;

  void update(JsonObject m, boolean first) {
    if (bool(m, "KeepAlive", false)) return;
    if (first) {
      peers.clear();
      filters.clear();
      self = null;
      derp = null;
      tailnetLock = false;
    }
    if (present(m, "TKAInfo"))
      tailnetLock = true; // Disablement requires a verified secret too; unsupported here.
    if (present(m, "Node")) self = m.getAsJsonObject("Node").deepCopy();
    if (present(m, "DERPMap")) derp = m.getAsJsonObject("DERPMap").deepCopy();
    if (present(m, "Peers") && m.getAsJsonArray("Peers").size() > 0) {
      peers.clear();
      for (JsonElement e : m.getAsJsonArray("Peers")) putPeer(e.getAsJsonObject());
    } else {
      if (present(m, "PeersChanged"))
        for (JsonElement e : m.getAsJsonArray("PeersChanged")) putPeer(e.getAsJsonObject());
      if (present(m, "PeersRemoved"))
        for (JsonElement e : m.getAsJsonArray("PeersRemoved")) peers.remove(e.getAsLong());
    }
    if (present(m, "PeersChangedPatch"))
      for (JsonElement e : m.getAsJsonArray("PeersChangedPatch")) {
        JsonObject patch = e.getAsJsonObject(), peer = peers.get(patch.get("NodeID").getAsLong());
        if (peer == null) continue;
        for (var entry : patch.entrySet())
          if (!entry.getKey().equals("NodeID") && !entry.getValue().isJsonNull())
            peer.add(
                entry.getKey().equals("DERPRegion") ? "HomeDERP" : entry.getKey(),
                entry.getValue().deepCopy());
      }
    if (present(m, "PacketFilter"))
      filters.put("base", m.getAsJsonArray("PacketFilter").deepCopy());
    if (present(m, "PacketFilters")) {
      JsonObject f = m.getAsJsonObject("PacketFilters");
      if (f.has("*") && f.get("*").isJsonNull()) filters.clear();
      for (var e : f.entrySet()) {
        if (e.getKey().equals("*")) continue;
        if (e.getValue().isJsonNull()) filters.remove(e.getKey());
        else filters.put(e.getKey(), e.getValue().getAsJsonArray().deepCopy());
      }
    }
  }

  private void putPeer(JsonObject p) {
    peers.put(p.get("ID").getAsLong(), p.deepCopy());
  }

  JsonObject peer(String key) {
    for (JsonObject p : peers.values()) if (string(p, "Key", "").equals("nodekey:" + key)) return p;
    return null;
  }

  boolean ready() {
    return self != null && bool(self, "MachineAuthorized", false) && !expired(self) && !tailnetLock;
  }

  static boolean expired(JsonObject node) {
    if (bool(node, "Expired", false)) return true;
    String e = string(node, "KeyExpiry", "");
    if (e.isEmpty() || e.startsWith("0001-")) return false;
    try {
      return !Instant.parse(e).isAfter(Instant.now());
    } catch (DateTimeException invalid) {
      return true;
    }
  }

  static boolean usable(JsonObject peer) {
    return !expired(peer)
        && !bool(peer, "IsJailed", false)
        && !bool(peer, "UnsignedPeerAPIOnly", false);
  }

  boolean allows(String peerKey, byte[] source, byte[] destination, int port) {
    JsonObject p = peer(peerKey);
    if (!ready() || p == null || !usable(p) || !owns(p, source) || !owns(self, destination))
      return false;
    for (JsonArray group : filters.values())
      for (JsonElement e : group) {
        JsonObject rule = e.getAsJsonObject();
        boolean protocol = !present(rule, "IPProto") || rule.getAsJsonArray("IPProto").isEmpty();
        if (present(rule, "IPProto"))
          for (JsonElement n : rule.getAsJsonArray("IPProto"))
            if (n.getAsInt() == 6) protocol = true;
        if (!protocol || !present(rule, "SrcIPs") || !present(rule, "DstPorts")) continue;
        boolean src = false;
        int i = 0;
        for (JsonElement spec : rule.getAsJsonArray("SrcIPs")) {
          String s = spec.getAsString();
          if (present(rule, "SrcBits")
              && i < rule.getAsJsonArray("SrcBits").size()
              && !s.equals("*")
              && !s.contains("/")) s += "/" + rule.getAsJsonArray("SrcBits").get(i).getAsInt();
          i++;
          if (s.startsWith("cap:")) {
            if (present(p, "CapMap") && p.getAsJsonObject("CapMap").has(s.substring(4))) src = true;
          } else if (matches(s, source)) src = true;
        }
        if (!src) continue;
        for (JsonElement d : rule.getAsJsonArray("DstPorts")) {
          JsonObject dest = d.getAsJsonObject(), ports = dest.getAsJsonObject("Ports");
          String spec = dest.get("IP").getAsString();
          if (present(dest, "Bits") && !spec.equals("*") && !spec.contains("/"))
            spec += "/" + dest.get("Bits").getAsInt();
          if (port >= ports.get("First").getAsInt()
              && port <= ports.get("Last").getAsInt()
              && matches(spec, destination)) return true;
        }
      }
    return false;
  }

  static boolean owns(JsonObject node, byte[] address) {
    if (!present(node, "Addresses")) return false;
    for (JsonElement a : node.getAsJsonArray("Addresses")) {
      String s = a.getAsString().split("/", 2)[0];
      try {
        if (Arrays.equals(ip(s), address)) return true;
      } catch (IllegalArgumentException ignored) {
      }
    }
    return false;
  }

  static boolean matches(String s, byte[] address) {
    try {
      if (s.equals("*")) return true;
      if (s.contains("-")) {
        String[] range = s.split("-", -1);
        if (range.length != 2) return false;
        byte[] a = ip(range[0]), b = ip(range[1]);
        return a.length == address.length
            && b.length == address.length
            && Arrays.compareUnsigned(a, address) <= 0
            && Arrays.compareUnsigned(address, b) <= 0;
      }
      String[] cidr = s.split("/", -1);
      byte[] net = ip(cidr[0]);
      if (net.length != address.length || cidr.length > 2) return false;
      int bits = cidr.length == 1 ? net.length * 8 : Integer.parseInt(cidr[1]);
      if (bits < 0 || bits > net.length * 8) return false;
      for (int i = 0; i < bits; i++)
        if (((net[i / 8] ^ address[i / 8]) & (1 << (7 - i % 8))) != 0) return false;
      return true;
    } catch (IllegalArgumentException ex) {
      return false;
    }
  }

  static byte[] ip(String s) {
    if (!s.matches("[0-9a-fA-F:.]+")) throw new IllegalArgumentException("IP literal required");
    try {
      return InetAddress.getByName(s).getAddress();
    } catch (UnknownHostException e) {
      throw new IllegalArgumentException("invalid IP literal");
    }
  }

  record Packet(
      byte[] source, byte[] destination, int sourcePort, int destinationPort, int length) {}

  static Packet tcp(byte[] b) {
    if (b.length < 20) return null;
    int version = (b[0] & 255) >> 4, off, n;
    byte[] source, dest;
    if (version == 4) {
      off = (b[0] & 15) * 4;
      n = u16(b, 2);
      if (off < 20 || n > b.length || n < off + 20 || b[9] != 6 || (u16(b, 6) & 0x3fff) != 0)
        return null;
      source = Arrays.copyOfRange(b, 12, 16);
      dest = Arrays.copyOfRange(b, 16, 20);
    } else if (version == 6) {
      off = 40;
      if (b.length < 60 || b[6] != 6) return null;
      n = 40 + u16(b, 4);
      if (n > b.length || n < 60) return null;
      source = Arrays.copyOfRange(b, 8, 24);
      dest = Arrays.copyOfRange(b, 24, 40);
    } else return null;
    int tcpHeader = ((b[off + 12] & 255) >> 4) * 4;
    if (tcpHeader < 20 || off + tcpHeader > n) return null;
    return new Packet(source, dest, u16(b, off), u16(b, off + 2), n);
  }

  private static int u16(byte[] b, int i) {
    return ((b[i] & 255) << 8) | (b[i + 1] & 255);
  }

  static boolean present(JsonObject o, String k) {
    return o.has(k) && !o.get(k).isJsonNull();
  }

  static String string(JsonObject o, String k, String def) {
    return present(o, k) ? o.get(k).getAsString() : def;
  }

  static boolean bool(JsonObject o, String k, boolean def) {
    return present(o, k) ? o.get(k).getAsBoolean() : def;
  }
}
