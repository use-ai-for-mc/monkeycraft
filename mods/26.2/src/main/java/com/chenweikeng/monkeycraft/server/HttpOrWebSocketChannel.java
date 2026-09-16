package com.chenweikeng.monkeycraft.server;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import org.java_websocket.WrappedByteChannel;

final class HttpOrWebSocketChannel implements WrappedByteChannel {
  private static final int MAX_HEADER_BYTES = 8192;
  private static final byte[] HEADER_END = {'\r', '\n', '\r', '\n'};
  private static final long HTTP_WRITE_TIMEOUT_NS = 10_000_000_000L;

  private enum State {
    HEADERS,
    WEBSOCKET,
    HTTP_DONE
  }

  private final SocketChannel channel;
  private final ByteBuffer headerBuf = ByteBuffer.allocate(MAX_HEADER_BYTES);
  private ByteBuffer replay;
  private State state = State.HEADERS;

  HttpOrWebSocketChannel(SocketChannel channel) {
    this.channel = channel;
  }

  @Override
  public int read(ByteBuffer dst) throws IOException {
    if (state == State.HTTP_DONE) {
      return -1;
    }
    if (state == State.WEBSOCKET) {
      if (replay != null && replay.hasRemaining()) {
        return copy(replay, dst);
      }
      replay = null;
      return channel.read(dst);
    }

    int n = channel.read(headerBuf);
    if (n < 0) {
      return -1;
    }
    ByteBuffer view = headerBuf.duplicate();
    view.flip();
    if (!containsHeaderEnd(view)) {
      if (!headerBuf.hasRemaining()) {
        writeHttp(
            400,
            "text/plain; charset=utf-8",
            "Header too large".getBytes(StandardCharsets.US_ASCII));
        finishHttp();
        return -1;
      }
      return 0;
    }

    headerBuf.flip();
    byte[] raw = new byte[headerBuf.remaining()];
    headerBuf.get(raw);
    if (isWebSocketUpgrade(raw)) {
      replay = ByteBuffer.wrap(raw);
      state = State.WEBSOCKET;
      return copy(replay, dst);
    }
    serveHttp(raw);
    finishHttp();
    return -1;
  }

  @Override
  public int write(ByteBuffer src) throws IOException {
    if (state == State.HTTP_DONE) {
      return 0;
    }
    return channel.write(src);
  }

  @Override
  public boolean isOpen() {
    return channel.isOpen();
  }

  @Override
  public void close() throws IOException {
    channel.close();
  }

  @Override
  public boolean isNeedWrite() {
    return false;
  }

  @Override
  public void writeMore() {}

  @Override
  public boolean isNeedRead() {
    return replay != null && replay.hasRemaining();
  }

  @Override
  public int readMore(ByteBuffer dst) throws IOException {
    return read(dst);
  }

  @Override
  public boolean isBlocking() {
    return false;
  }

  private void serveHttp(byte[] raw) throws IOException {
    String start = firstLine(raw);
    boolean head = start.startsWith("HEAD ");
    boolean get = start.startsWith("GET ");
    if (!head && !get) {
      writeHttp(
          405,
          "text/plain; charset=utf-8",
          "Method Not Allowed".getBytes(StandardCharsets.US_ASCII));
      return;
    }
    WebAssetServer.Response response = WebAssetServer.classpath().get(requestPath(start));
    writeHttp(response.status(), response.contentType(), head ? new byte[0] : response.body());
  }

  private void writeHttp(int status, String contentType, byte[] body) throws IOException {
    String reason =
        switch (status) {
          case 200 -> "OK";
          case 400 -> "Bad Request";
          case 404 -> "Not Found";
          case 405 -> "Method Not Allowed";
          default -> "OK";
        };
    byte[] header =
        ("HTTP/1.1 "
                + status
                + " "
                + reason
                + "\r\nContent-Type: "
                + contentType
                + "\r\nContent-Length: "
                + body.length
                + "\r\nConnection: close\r\n\r\n")
            .getBytes(StandardCharsets.US_ASCII);
    writeFully(ByteBuffer.wrap(header));
    if (body.length > 0) {
      writeFully(ByteBuffer.wrap(body));
    }
  }

  private void writeFully(ByteBuffer buf) throws IOException {
    long deadline = System.nanoTime() + HTTP_WRITE_TIMEOUT_NS;
    while (buf.hasRemaining()) {
      int written = channel.write(buf);
      if (written == 0) {
        if (System.nanoTime() >= deadline) {
          break;
        }
        Thread.onSpinWait();
      }
    }
  }

  private void finishHttp() throws IOException {
    state = State.HTTP_DONE;
    try {
      channel.shutdownOutput();
    } catch (IOException ignored) {
    }
    channel.close();
  }

  private static boolean isWebSocketUpgrade(byte[] raw) {
    String text = new String(raw, 0, indexOfHeaderEnd(raw) + 4, StandardCharsets.US_ASCII);
    for (String line : text.split("\r\n")) {
      int colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      String name = line.substring(0, colon).trim();
      String value = line.substring(colon + 1).trim();
      if (name.equalsIgnoreCase("Upgrade") && value.equalsIgnoreCase("websocket")) {
        return true;
      }
    }
    return false;
  }

  private static String firstLine(byte[] raw) {
    int end = indexOf(raw, new byte[] {'\r', '\n'}, 0);
    if (end < 0) {
      return "";
    }
    return new String(raw, 0, end, StandardCharsets.US_ASCII);
  }

  static String requestPath(String startLine) {
    int first = startLine.indexOf(' ');
    if (first < 0) {
      return "/";
    }
    int second = startLine.indexOf(' ', first + 1);
    if (second < 0) {
      return startLine.substring(first + 1);
    }
    return startLine.substring(first + 1, second);
  }

  private static boolean containsHeaderEnd(ByteBuffer view) {
    byte[] raw = new byte[view.remaining()];
    int pos = view.position();
    view.get(raw);
    view.position(pos);
    return indexOfHeaderEnd(raw) >= 0;
  }

  private static int indexOfHeaderEnd(byte[] raw) {
    return indexOf(raw, HEADER_END, 0);
  }

  private static int indexOf(byte[] haystack, byte[] needle, int from) {
    outer:
    for (int i = from; i <= haystack.length - needle.length; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }

  private static int copy(ByteBuffer src, ByteBuffer dst) {
    int n = Math.min(src.remaining(), dst.remaining());
    if (n <= 0) {
      return 0;
    }
    int limit = src.limit();
    src.limit(src.position() + n);
    dst.put(src);
    src.limit(limit);
    return n;
  }
}
