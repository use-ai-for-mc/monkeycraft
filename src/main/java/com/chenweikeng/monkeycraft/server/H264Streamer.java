package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.mixin.NativeImageAccessor;
import com.mojang.blaze3d.platform.NativeImage;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.java_websocket.WebSocket;
import org.jcodec.codecs.h264.H264Encoder;
import org.jcodec.common.model.ColorSpace;
import org.jcodec.common.model.Picture;

public class H264Streamer {
  private final Picture picture;
  private volatile H264Encoder encoder;
  private volatile ByteBuffer buffer;
  private final int width;
  private final int height;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final AtomicBoolean isEncoding = new AtomicBoolean(false);
  private final AtomicInteger pendingFrames = new AtomicInteger(0);
  private final AtomicInteger droppedBackpressure = new AtomicInteger(0);
  private final AtomicInteger droppedBusy = new AtomicInteger(0);
  private final int colorMode;
  private final int fps;
  private volatile boolean needsIdr = true;
  private long lastLogTime = 0;

  public H264Streamer(int width, int height, int colorMode, int fps) {
    this.width = width;
    this.height = height;
    this.colorMode = colorMode;
    this.fps = fps;

    this.picture = Picture.create(width, height, ColorSpace.YUV420J);
    this.buffer = ByteBuffer.allocate(Math.max(1024 * 1024, width * height * 6));
    this.encoder = createEncoder();
  }

  public void ack() {
    pendingFrames.updateAndGet(v -> v > 0 ? v - 1 : 0);
  }

  public void resetBackpressure() {
    pendingFrames.set(0);
    needsIdr = true;
  }

  public void encodeAndSend(NativeImage image, WebSocket conn) {
    if (!conn.isOpen()) {
      image.close();
      return;
    }

    // Backpressure check: If more than 1 frame is in flight, drop this one.
    if (pendingFrames.get() > 1) {
      droppedBackpressure.incrementAndGet();
      needsIdr = true;
      image.close();
      return;
    }

    if (!isEncoding.compareAndSet(false, true)) {
      droppedBusy.incrementAndGet();
      needsIdr = true;
      image.close();
      return;
    }

    executor.submit(
        () -> {
          try {
            if (needsIdr) {
              encoder = createEncoder();
              needsIdr = false;
            }

            // Direct pixel access
            convertNativeImageToYuv(image, picture);
            try {
              image.close();
            } catch (Exception ignored) {
            }

            // 2. Encode frame
            ByteBuffer encoded = encodeFrame(picture);
            int size = encoded.remaining();

            // 3. Send raw NAL units
            if (conn.isOpen()) {
              byte[] data = new byte[size];
              encoded.get(data);
              conn.send(data);
              pendingFrames.incrementAndGet();
            }
          } catch (Exception e) {
            e.printStackTrace();
            needsIdr = true;
          } finally {
            try {
              image.close();
            } catch (Exception ignored) {
            }
            isEncoding.set(false);
          }
        });
  }

  public void close() {
    executor.shutdownNow();
  }

  private H264Encoder createEncoder() {
    H264Encoder next = H264Encoder.createH264Encoder();
    next.setKeyInterval(Math.max(1, fps));
    return next;
  }

  private ByteBuffer encodeFrame(Picture src) {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        ByteBuffer out = buffer;
        out.clear();
        return encoder.encodeFrame(src, out).getData();
      } catch (RuntimeException e) {
        ByteBuffer next = ByteBuffer.allocate(buffer.capacity() * 2);
        buffer = next;
        if (attempt == 1) throw e;
      }
    }
    throw new IllegalStateException("Failed to encode frame");
  }

  private void convertNativeImageToYuv(NativeImage src, Picture dst) {
    byte[] y = dst.getPlaneData(0);
    byte[] u = dst.getPlaneData(1);
    byte[] v = dst.getPlaneData(2);

    int w = src.getWidth();
    int h = src.getHeight();
    int minW = Math.min(w, width);
    int minH = Math.min(h, height);

    for (int row = 0; row < minH; row++) {
      for (int col = 0; col < minW; col++) {
        int color = ((NativeImageAccessor) (Object) src).monkeycraft$getPixelABGR(col, row);

        // Assuming ABGR format (packed int)
        int a = (color >> 24) & 0xFF;
        int b = (color >> 16) & 0xFF;
        int g = (color >> 8) & 0xFF;
        int r = (color >> 0) & 0xFF;

        // Apply color reduction
        if (colorMode == 1) { // High Perf (12-bit)
          r &= 0xF0;
          g &= 0xF0;
          b &= 0xF0;
        } else if (colorMode == 2) { // Retro (6-bit)
          r &= 0xC0;
          g &= 0xC0;
          b &= 0xC0;
        } else if (colorMode == 3) { // Grayscale
          int gray = (r + g + b) / 3;
          r = g = b = gray;
        }

        int Y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
        int U = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
        int V = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

        y[row * width + col] = clampAndCenterByte(Y);

        if (row % 2 == 0 && col % 2 == 0) {
          int chromaIndex = (row / 2) * (width / 2) + (col / 2);
          u[chromaIndex] = clampAndCenterByte(U);
          v[chromaIndex] = clampAndCenterByte(V);
        }
      }
    }
  }

  private byte clampAndCenterByte(int value) {
    int clamped;
    if (value < 0) clamped = 0;
    else if (value > 255) clamped = 255;
    else clamped = value;
    return (byte) (clamped - 128);
  }
}
