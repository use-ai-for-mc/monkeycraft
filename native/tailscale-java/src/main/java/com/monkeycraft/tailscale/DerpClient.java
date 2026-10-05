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
import javax.net.ssl.*;

/** DERP v2 client. Relay sees only the WireGuard/disco encrypted packets. */
final class DerpClient implements AutoCloseable {
  @FunctionalInterface
  interface PacketReceiver {
    void receive(String sender, byte[] packet);
  }

  private final Socket socket;
  private final InputStream in;
  private final OutputStream out;
  private final ArrayBlockingQueue<Frame> outgoing = new ArrayBlockingQueue<>(256);
  private final PacketReceiver receiver;
  private final Consumer<Exception> failed;
  private final Thread reader, writer;
  private volatile boolean closed;
  private final java.util.concurrent.atomic.AtomicBoolean reported =
      new java.util.concurrent.atomic.AtomicBoolean();

  private record Frame(int type, byte[] data) {}

  DerpClient(
      JsonObject node,
      byte[] secret,
      SSLSocketFactory tlsFactory,
      Set<Socket> pending,
      PacketReceiver receiver,
      Consumer<Exception> failed)
      throws Exception {
    this.receiver = receiver;
    this.failed = failed;
    String host = node.get("HostName").getAsString(),
        certName = string(node, "CertName", host),
        ip = string(node, "IPv4", host);
    if (certName.startsWith("sha256-raw:"))
      throw new IOException("DERP pinned raw certificate is not supported");
    if (ip.equals("none") || ip.isEmpty()) ip = host;
    int port =
        node.has("DERPPort") && node.get("DERPPort").getAsInt() != 0
            ? node.get("DERPPort").getAsInt()
            : 443;
    Socket raw = new Socket();
    Socket secured = null;
    pending.add(raw);
    try {
      if (Thread.currentThread().isInterrupted()) throw new IOException("DERP connect cancelled");
      raw.connect(new InetSocketAddress(ip, port), 10_000);
      raw.setSoTimeout(90_000);
      SSLSocket tls = (SSLSocket) tlsFactory.createSocket(raw, certName, port, true);
      secured = tls;
      SSLParameters params = tls.getSSLParameters();
      params.setEndpointIdentificationAlgorithm("HTTPS");
      tls.setSSLParameters(params);
      tls.startHandshake();
      socket = tls;
      in = tls.getInputStream();
      out = tls.getOutputStream();
      if (host.indexOf('\r') >= 0 || host.indexOf('\n') >= 0)
        throw new IOException("invalid DERP hostname");
      out.write(
          ("GET /derp HTTP/1.1\r\nHost: "
                  + host
                  + "\r\nConnection: Upgrade\r\nUpgrade: DERP\r\n\r\n")
              .getBytes(StandardCharsets.US_ASCII));
      out.flush();
      String head = ControlHttp.readHttpHead(in);
      if (!head.startsWith("HTTP/1.1 101 ")) throw new IOException("DERP upgrade refused");
      Frame greeting = readFrame();
      byte[] magic = "DERP🔑".getBytes(StandardCharsets.UTF_8);
      if (greeting.type != 1
          || greeting.data.length < 40
          || !Arrays.equals(Arrays.copyOf(greeting.data, 8), magic))
        throw new IOException("invalid DERP greeting");
      byte[] serverKey = Arrays.copyOfRange(greeting.data, 8, 40);
      byte[] info = "{\"version\":2,\"CanAckPings\":true}".getBytes(StandardCharsets.US_ASCII);
      writeFrame(
          new Frame(
              2, Crypto.concat(Crypto.publicKey(secret), Crypto.box(secret, serverKey, info))));
      Frame serverInfo = readFrame();
      if (serverInfo.type != 3) throw new IOException("DERP server info missing");
      JsonParser.parseString(
          new String(Crypto.openBox(secret, serverKey, serverInfo.data), StandardCharsets.UTF_8));
      writeFrame(new Frame(7, new byte[] {1}));
    } catch (Exception e) {
      if (secured != null) secured.close();
      raw.close();
      throw e;
    } finally {
      pending.remove(raw);
    }
    reader = new Thread(this::readLoop, "tailscale-java-derp-read");
    writer = new Thread(this::writeLoop, "tailscale-java-derp-write");
    reader.setDaemon(true);
    writer.setDaemon(true);
    reader.start();
    writer.start();
  }

  boolean send(String destination, byte[] packet) {
    if (closed || packet.length > 65_536) return false;
    return outgoing.offer(
        new Frame(4, Crypto.concat(HexFormat.of().parseHex(destination), packet)));
  }

  private Frame readFrame() throws IOException {
    byte[] h = Noise.readExactly(in, 5);
    int n = ByteBuffer.wrap(h, 1, 4).getInt();
    if (n < 0 || n > 1_048_576) throw new IOException("invalid DERP frame length");
    return new Frame(Byte.toUnsignedInt(h[0]), Noise.readExactly(in, n));
  }

  private void writeFrame(Frame frame) throws IOException {
    out.write(ByteBuffer.allocate(5).put((byte) frame.type).putInt(frame.data.length).array());
    out.write(frame.data);
    out.flush();
  }

  private void readLoop() {
    try {
      while (!closed) {
        Frame f = readFrame();
        switch (f.type) {
          case 5 -> {
            if (f.data.length < 32 || f.data.length > 65_568)
              throw new IOException("invalid DERP packet");
            receiver.receive(
                Crypto.hex(Arrays.copyOf(f.data, 32)),
                Arrays.copyOfRange(f.data, 32, f.data.length));
          }
          case 0x12 -> {
            if (f.data.length != 8) throw new IOException("invalid DERP ping");
            if (!outgoing.offer(new Frame(0x13, f.data))) throw new IOException("DERP queue full");
          }
          case 0x15 -> throw new IOException("DERP server restarting");
          case 0x14 -> {
            if (f.data.length > 0) throw new IOException("DERP server health problem");
          }
          default -> {} // Unknown frame types are extensible; bounded above.
        }
      }
    } catch (Exception e) {
      fail(e);
    }
  }

  private void writeLoop() {
    try {
      while (!closed) {
        Frame f = outgoing.poll(30, TimeUnit.SECONDS);
        if (f == null) f = new Frame(0x12, Crypto.random(8));
        writeFrame(f);
      }
    } catch (Exception e) {
      fail(e);
    }
  }

  private void fail(Exception e) {
    if (!closed && reported.compareAndSet(false, true)) {
      close();
      failed.accept(e);
    }
  }

  private static String string(JsonObject o, String key, String def) {
    return o.has(key) && !o.get(key).getAsString().isEmpty() ? o.get(key).getAsString() : def;
  }

  public void close() {
    closed = true;
    try {
      socket.close();
    } catch (IOException ignored) {
    }
    outgoing.clear();
    if (writer != null) writer.interrupt();
  }
}
