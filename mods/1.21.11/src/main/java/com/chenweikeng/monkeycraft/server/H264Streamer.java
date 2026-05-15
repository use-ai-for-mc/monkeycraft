package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft.mixin.NativeImageAccessor;
import com.mojang.blaze3d.platform.NativeImage;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.java_websocket.WebSocket;
import org.jcodec.codecs.h264.H264Encoder;
import org.jcodec.common.model.ColorSpace;
import org.jcodec.common.model.Picture;

public class H264Streamer {
  private static final byte[] FRAME_HEADER_MAGIC = {0x4D, 0x43};
  private static final int COLOR_MODE_NORMAL = 0;
  private static final int COLOR_MODE_HIGH_PERF = 1;
  private static final int COLOR_MODE_RETRO = 2;
  private static final int COLOR_MODE_GRAYSCALE = 3;
  private static final int HIGH_PERF_MASK = 0xF0;
  private static final int RETRO_MASK = 0xC0;
  private static final int MAX_PENDING_FRAMES = 1;
  private static final int NAL_TYPE_IDR = 5;

  private final Picture picture;
  private volatile H264Encoder encoder;
  private volatile ByteBuffer buffer;
  private final int width;
  private final int height;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private final AtomicBoolean isEncoding = new AtomicBoolean(false);
  private final AtomicInteger pendingFrames = new AtomicInteger(0);
  private final int colorMode;
  private final int fps;
  private volatile boolean needsIdr = true;
  private volatile boolean sendResolutionHeader = true;

  public H264Streamer(int width, int height, int colorMode, int fps) {
    this.width = width;
    this.height = height;
    this.colorMode = colorMode;
    this.fps = fps;

    this.picture = Picture.create(width, height, ColorSpace.YUV420J);
    this.buffer = ByteBuffer.allocate(Math.max(1024 * 1024, width * height * 6));
    this.encoder = createEncoder();
  }

  public int getWidth() {
    return width;
  }

  public int getHeight() {
    return height;
  }

  public void ack() {
    pendingFrames.updateAndGet(v -> v > 0 ? v - 1 : 0);
  }

  public void resetBackpressure() {
    pendingFrames.set(0);
    needsIdr = true;
    sendResolutionHeader = true;
  }

  private boolean isIdrFrame(byte[] data) {
    for (int i = 0; i < data.length - 4; i++) {
      if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1) {
        int nalType = data[i + 4] & 0x1F;
        if (nalType == NAL_TYPE_IDR) return true;
      }
    }
    return false;
  }

  public void encodeAndSend(NativeImage image, WebSocket conn) {
    if (!conn.isOpen()) {
      image.close();
      return;
    }

    if (pendingFrames.get() > MAX_PENDING_FRAMES) {
      needsIdr = true;
      image.close();
      return;
    }

    if (!isEncoding.compareAndSet(false, true)) {
      needsIdr = true;
      image.close();
      return;
    }

    try {
      executor.submit(
          () -> {
            try {
              if (needsIdr) {
                encoder = createEncoder();
                needsIdr = false;
                sendResolutionHeader = true;
              }

              convertNativeImageToYuv(image, picture);
              try {
                image.close();
              } catch (Exception ignored) {
              }

              ByteBuffer encoded = encodeFrame(picture);
              int size = encoded.remaining();

              if (conn.isOpen()) {
                byte[] h264Data = new byte[size];
                encoded.get(h264Data);

                boolean isIdr = isIdrFrame(h264Data);
                byte[] dataToSend;

                if (isIdr && sendResolutionHeader) {
                  dataToSend = new byte[6 + h264Data.length];
                  System.arraycopy(FRAME_HEADER_MAGIC, 0, dataToSend, 0, 2);
                  dataToSend[2] = (byte) ((width >> 8) & 0xFF);
                  dataToSend[3] = (byte) (width & 0xFF);
                  dataToSend[4] = (byte) ((height >> 8) & 0xFF);
                  dataToSend[5] = (byte) (height & 0xFF);
                  System.arraycopy(h264Data, 0, dataToSend, 6, h264Data.length);
                  sendResolutionHeader = false;
                } else {
                  dataToSend = h264Data;
                }

                conn.send(dataToSend);
                pendingFrames.incrementAndGet();

                if (!isIdr) {
                  needsIdr = true;
                }
              }
            } catch (Exception e) {
              needsIdr = true;
            } finally {
              try {
                image.close();
              } catch (Exception ignored) {
              }
              isEncoding.set(false);
            }
          });
    } catch (RejectedExecutionException e) {
      // close() shut the executor down on another thread (stream reconfigure
      // or server stop) between the guards above and this submit — drop the
      // frame instead of letting the exception crash the render thread.
      needsIdr = true;
      isEncoding.set(false);
      try {
        image.close();
      } catch (Exception ignored) {
      }
    }
  }

  public void close() {
    executor.shutdownNow();
    try {
      executor.awaitTermination(2, TimeUnit.SECONDS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
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

        int a = (color >> 24) & 0xFF;
        int b = (color >> 16) & 0xFF;
        int g = (color >> 8) & 0xFF;
        int r = (color >> 0) & 0xFF;

        if (colorMode == COLOR_MODE_HIGH_PERF) {
          r &= HIGH_PERF_MASK;
          g &= HIGH_PERF_MASK;
          b &= HIGH_PERF_MASK;
        } else if (colorMode == COLOR_MODE_RETRO) {
          r &= RETRO_MASK;
          g &= RETRO_MASK;
          b &= RETRO_MASK;
        } else if (colorMode == COLOR_MODE_GRAYSCALE) {
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
