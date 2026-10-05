package com.monkeycraft.tailscale;

import com.google.gson.*;
import io.netty.buffer.*;
import io.netty.channel.*;
import io.netty.channel.embedded.EmbeddedChannel;
import io.netty.handler.codec.http2.*;
import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import javax.net.ssl.*;

/** HTTP/2 inside authenticated Noise. All transports and codecs run on the JVM. */
final class ControlHttp implements Closeable {
  // Research compatibility level, not a claim to implement all current upstream capabilities.
  static final int CAPABILITY = 39;
  private final URI base;
  private final byte[] machine, serverKey;
  private final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
  private volatile boolean closed;

  @FunctionalInterface
  interface DataSink {
    void accept(byte[] data) throws IOException;
  }

  ControlHttp(URI base, byte[] machine) throws Exception {
    validateURL(base);
    this.base = base;
    this.machine = machine.clone();
    HttpClient client =
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();
    HttpRequest request =
        HttpRequest.newBuilder(base.resolve("/key?v=" + CAPABILITY))
            .timeout(Duration.ofSeconds(15))
            .GET()
            .build();
    HttpResponse<InputStream> response =
        client.send(request, HttpResponse.BodyHandlers.ofInputStream());
    try (InputStream in = response.body()) {
      if (response.statusCode() != 200)
        throw new IOException("control key HTTP status " + response.statusCode());
      byte[] body = in.readNBytes(1_048_577);
      if (body.length > 1_048_576) throw new IOException("control key response too large");
      JsonObject obj =
          JsonParser.parseString(new String(body, StandardCharsets.UTF_8)).getAsJsonObject();
      serverKey = Crypto.key(obj.get("publicKey").getAsString(), "mkey:");
    }
  }

  static void validateURL(URI uri) throws Exception {
    if (uri.getHost() == null
        || uri.getUserInfo() != null
        || uri.getFragment() != null
        || uri.getQuery() != null) throw new IOException("invalid control URL");
    if (!"https".equals(uri.getScheme())) {
      if (!"http".equals(uri.getScheme())
          || !InetAddress.getByName(uri.getHost()).isLoopbackAddress())
        throw new IOException("control URL requires HTTPS (HTTP allowed only for local tests)");
    }
  }

  private Socket connect() throws IOException {
    if (closed) throw new IOException("control closed");
    int port = base.getPort() >= 0 ? base.getPort() : base.getScheme().equals("https") ? 443 : 80;
    Socket raw = new Socket();
    sockets.add(raw);
    try {
      raw.connect(new InetSocketAddress(base.getHost(), port), 10_000);
      raw.setSoTimeout(90_000);
      if (base.getScheme().equals("https")) {
        SSLSocket tls =
            (SSLSocket)
                ((SSLSocketFactory) SSLSocketFactory.getDefault())
                    .createSocket(raw, base.getHost(), port, true);
        SSLParameters params = tls.getSSLParameters();
        params.setEndpointIdentificationAlgorithm("HTTPS");
        tls.setSSLParameters(params);
        tls.startHandshake();
        sockets.remove(raw);
        sockets.add(tls);
        return tls;
      }
      return raw;
    } catch (IOException e) {
      sockets.remove(raw);
      raw.close();
      throw e;
    }
  }

  JsonObject post(String path, JsonObject body) throws Exception {
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    request(
        path,
        body,
        b -> {
          if (bytes.size() + b.length > 16 * 1024 * 1024)
            throw new IOException("control response too large");
          bytes.write(b);
        });
    return bytes.size() == 0
        ? new JsonObject()
        : JsonParser.parseString(bytes.toString(StandardCharsets.UTF_8)).getAsJsonObject();
  }

  void request(String path, JsonObject body, DataSink sink) throws Exception {
    Socket socket = connect();
    EmbeddedChannel channel = null;
    try {
      Noise.Initiation start = new Noise.Initiation(machine, serverKey, CAPABILITY);
      OutputStream output = socket.getOutputStream();
      InputStream input = socket.getInputStream();
      String upgrade =
          "POST /ts2021 HTTP/1.1\r\nHost: "
              + base.getRawAuthority()
              + "\r\n"
              + "Connection: Upgrade\r\n"
              + "Upgrade: tailscale-control-protocol\r\n"
              + "X-Tailscale-Handshake: "
              + Base64.getEncoder().encodeToString(start.message)
              + "\r\nContent-Length: 0\r\n\r\n";
      output.write(upgrade.getBytes(StandardCharsets.US_ASCII));
      output.flush();
      String head = readHttpHead(input);
      if (!head.startsWith("HTTP/1.1 101 ")
          || !head.toLowerCase(Locale.ROOT).contains("upgrade: tailscale-control-protocol"))
        throw new IOException("control refused protocol upgrade");
      Noise noise = start.finish(input, output, socket);
      Response listener = new Response(sink);
      Http2ConnectionHandler h2 =
          new Http2ConnectionHandlerBuilder().server(false).frameListener(listener).build();
      channel = new EmbeddedChannel(h2);
      ChannelHandlerContext ctx = channel.pipeline().context(h2);
      Http2Headers headers =
          new DefaultHttp2Headers()
              .method("POST")
              .scheme("https")
              .authority(base.getRawAuthority())
              .path(path)
              .set("content-type", "application/json");
      if (body.has("NodeKey")) headers.set("ts-lb", body.get("NodeKey").getAsString());
      byte[] payload = body.toString().getBytes(StandardCharsets.UTF_8);
      h2.encoder().writeHeaders(ctx, 1, headers, 0, false, ctx.newPromise());
      h2.encoder().writeData(ctx, 1, Unpooled.wrappedBuffer(payload), 0, true, ctx.newPromise());
      ctx.flush();
      flush(channel, noise);
      InputStream secure = noise.input();
      byte[] first = Noise.readExactly(secure, 9);
      if (Arrays.equals(Arrays.copyOf(first, 5), new byte[] {-1, -1, -1, 'T', 'S'})) {
        int n = ByteBuffer.wrap(first, 5, 4).getInt();
        if (n < 0 || n > 10 * 1024 * 1024) throw new IOException("invalid early payload");
        JsonParser.parseString(new String(Noise.readExactly(secure, n), StandardCharsets.UTF_8));
      } else channel.writeInbound(Unpooled.wrappedBuffer(first));
      flush(channel, noise);
      byte[] buffer = new byte[16_384];
      while (!listener.done) {
        int n = secure.read(buffer);
        if (n < 0) throw new EOFException("HTTP/2 response incomplete");
        channel.writeInbound(Unpooled.copiedBuffer(buffer, 0, n));
        flush(channel, noise);
        if (listener.failure != null) throw listener.failure;
      }
      if (listener.failure != null) throw listener.failure;
      if (listener.status != 200) throw new IOException("control HTTP status " + listener.status);
    } finally {
      sockets.remove(socket);
      socket.close();
      if (channel != null) channel.finishAndReleaseAll();
    }
  }

  private static void flush(EmbeddedChannel ch, Noise n) throws IOException {
    ch.runPendingTasks();
    ch.flushOutbound();
    ByteBuf b;
    while ((b = ch.readOutbound()) != null) {
      try {
        byte[] data = new byte[b.readableBytes()];
        b.readBytes(data);
        n.write(data);
      } finally {
        b.release();
      }
    }
    ch.checkException();
  }

  static String readHttpHead(InputStream in) throws IOException {
    ByteArrayOutputStream b = new ByteArrayOutputStream();
    int state = 0;
    while (b.size() < 16_384) {
      int c = in.read();
      if (c < 0) throw new EOFException("HTTP upgrade truncated");
      b.write(c);
      state =
          switch (state) {
            case 0 -> c == '\r' ? 1 : 0;
            case 1 -> c == '\n' ? 2 : 0;
            case 2 -> c == '\r' ? 3 : 0;
            default -> c == '\n' ? 4 : 0;
          };
      if (state == 4) return b.toString(StandardCharsets.US_ASCII);
    }
    throw new IOException("HTTP upgrade headers too large");
  }

  private static final class Response extends Http2FrameAdapter {
    private final DataSink sink;
    boolean done;
    int status;
    IOException failure;

    Response(DataSink sink) {
      this.sink = sink;
    }

    public void onHeadersRead(
        ChannelHandlerContext c, int id, Http2Headers h, int pad, boolean end) {
      if (id != 1) return;
      if (h.status() != null) status = Integer.parseInt(h.status().toString());
      done = end;
    }

    public void onHeadersRead(
        ChannelHandlerContext c,
        int id,
        Http2Headers h,
        int dep,
        short weight,
        boolean exclusive,
        int pad,
        boolean end) {
      onHeadersRead(c, id, h, pad, end);
    }

    public int onDataRead(ChannelHandlerContext c, int id, ByteBuf data, int pad, boolean end) {
      int n = data.readableBytes();
      if (id == 1) {
        byte[] b = new byte[n];
        data.getBytes(data.readerIndex(), b);
        try {
          if (status == 200) sink.accept(b);
        } catch (IOException e) {
          failure = e;
        }
        done = end;
      }
      return n + pad;
    }

    public void onRstStreamRead(ChannelHandlerContext c, int id, long error) {
      if (id == 1) {
        failure = new IOException("control stream reset " + error);
        done = true;
      }
    }

    public void onGoAwayRead(ChannelHandlerContext c, int last, long error, ByteBuf data) {
      if (error != 0 || last < 1) {
        failure = new IOException("control GOAWAY " + error);
        done = true;
      }
    }
  }

  public void close() {
    closed = true;
    for (Socket s : sockets) {
      try {
        s.close();
      } catch (IOException ignored) {
      }
    }
    sockets.clear();
  }
}
