package com.monkeycraft.tailscale;

import io.github.shri299.wirefin.ipv4.Ipv4Address;
import io.github.shri299.wirefin.runtime.PacketProcessor;
import io.github.shri299.wirefin.tcp.connection.TcpConnection;
import java.net.*;
import java.nio.*;
import java.util.*;

public final class WireGuardProbe {
  public static void main(String[] args) throws Exception {
    byte[] secret = Crypto.privateKey(), remote = HexFormat.of().parseHex(args[0]);
    String peer = Crypto.hex(remote);
    DatagramSocket udp = new DatagramSocket(new InetSocketAddress("127.0.0.1", 0));
    udp.setSoTimeout(10);
    InetSocketAddress destination = new InetSocketAddress("127.0.0.1", Integer.parseInt(args[1]));
    ArrayList<TcpConnection> connections = new ArrayList<>();
    WireGuard[] wg = new WireGuard[1];
    PacketProcessor stack =
        new PacketProcessor(
            Ipv4Address.parse("100.64.0.2"),
            () -> Integer.toUnsignedLong(Crypto.RANDOM.nextInt()),
            p -> wg[0].send(peer, p));
    stack.listen(
        9600,
        c -> {
          connections.add(c);
          stack.accepted(c.key());
        });
    wg[0] =
        new WireGuard(
            secret,
            (id, p) -> {
              try {
                udp.send(new DatagramPacket(p, p.length, destination));
              } catch (Exception e) {
                throw new RuntimeException(e);
              }
            },
            (id, p) -> {
              int n = Short.toUnsignedInt(ByteBuffer.wrap(p, 2, 2).getShort());
              for (byte[] out : stack.process(Arrays.copyOf(p, n))) wg[0].send(id, out);
            });
    wg[0].addPeer(remote);
    System.out.println(Crypto.hex(Crypto.publicKey(secret)) + " " + udp.getLocalPort());
    System.out.flush();
    if (args.length > 2) wg[0].send(peer, new byte[0]);
    byte[] buffer = new byte[65536];
    while (true) {
      try {
        DatagramPacket p = new DatagramPacket(buffer, buffer.length);
        udp.receive(p);
        if (!p.getSocketAddress().equals(destination)) continue;
        wg[0].receive(
            Arrays.copyOfRange(p.getData(), p.getOffset(), p.getOffset() + p.getLength()),
            new byte[] {127, 0, 0, 1});
        byte[] cookie = wg[0].takeCookieReply();
        if (cookie != null) udp.send(new DatagramPacket(cookie, cookie.length, destination));
      } catch (SocketTimeoutException expected) {
      }
      for (TcpConnection c : connections) {
        if (c.readableBytes() > 0 && c.pendingSendBytes() < 512 * 1024) {
          byte[] b = new byte[Math.min(c.readableBytes(), 16384)];
          int n = c.read(b, 0, b.length);
          stack.transmit(c, c.send(Arrays.copyOf(b, n), System.nanoTime()));
        }
      }
      stack.pollRetransmissions(System.nanoTime());
      wg[0].tick();
    }
  }
}
