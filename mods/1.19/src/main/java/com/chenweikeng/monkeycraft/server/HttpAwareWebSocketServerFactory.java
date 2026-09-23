package com.chenweikeng.monkeycraft.server;

import java.nio.channels.ByteChannel;
import java.nio.channels.SelectionKey;
import java.nio.channels.SocketChannel;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.java_websocket.WebSocketAdapter;
import org.java_websocket.WebSocketImpl;
import org.java_websocket.WebSocketServerFactory;
import org.java_websocket.drafts.Draft;

final class HttpAwareWebSocketServerFactory implements WebSocketServerFactory {
  private static final int MAX_HTTP_DOWNLOADS = 16;
  private static final long HTTP_DOWNLOAD_TIMEOUT_MS = TimeUnit.SECONDS.toMillis(60);

  private final Set<HttpOrWebSocketChannel> activeHttpChannels = ConcurrentHashMap.newKeySet();
  private final ThreadPoolExecutor httpWorkers;
  private final ScheduledExecutorService httpTimeouts;
  private final long downloadTimeoutMs;
  private final AtomicBoolean closed = new AtomicBoolean(false);

  HttpAwareWebSocketServerFactory() {
    this(MAX_HTTP_DOWNLOADS, HTTP_DOWNLOAD_TIMEOUT_MS);
  }

  HttpAwareWebSocketServerFactory(int maxHttpDownloads, long downloadTimeoutMs) {
    if (maxHttpDownloads < 1 || downloadTimeoutMs < 1) {
      throw new IllegalArgumentException("HTTP limits must be positive");
    }
    this.downloadTimeoutMs = downloadTimeoutMs;
    AtomicInteger workerId = new AtomicInteger();
    ThreadFactory workerFactory =
        runnable -> {
          Thread thread =
              new Thread(runnable, "MonkeycraftHttpAsset-" + workerId.incrementAndGet());
          thread.setDaemon(true);
          return thread;
        };
    httpWorkers =
        new ThreadPoolExecutor(
            0,
            maxHttpDownloads,
            30,
            TimeUnit.SECONDS,
            new SynchronousQueue<>(),
            workerFactory,
            new ThreadPoolExecutor.AbortPolicy());
    AtomicInteger timeoutId = new AtomicInteger();
    httpTimeouts =
        new ScheduledThreadPoolExecutor(
            1,
            runnable -> {
              Thread thread =
                  new Thread(
                      runnable, "MonkeycraftHttpAssetTimeout-" + timeoutId.incrementAndGet());
              thread.setDaemon(true);
              return thread;
            });
    ((ScheduledThreadPoolExecutor) httpTimeouts).setRemoveOnCancelPolicy(true);
  }

  @Override
  public WebSocketImpl createWebSocket(WebSocketAdapter a, Draft d) {
    return new WebSocketImpl(a, d);
  }

  @Override
  public WebSocketImpl createWebSocket(WebSocketAdapter a, List<Draft> drafts) {
    return new WebSocketImpl(a, drafts);
  }

  @Override
  public ByteChannel wrapChannel(SocketChannel channel, SelectionKey key) {
    return new HttpOrWebSocketChannel(channel, key, this);
  }

  boolean startHttp(HttpOrWebSocketChannel channel) {
    if (closed.get()) {
      return false;
    }
    activeHttpChannels.add(channel);
    if (closed.get()) {
      activeHttpChannels.remove(channel);
      return false;
    }
    try {
      httpWorkers.execute(
          () -> {
            ScheduledFuture<?> timeout = null;
            try {
              timeout =
                  httpTimeouts.schedule(
                      channel::closeQuietly, downloadTimeoutMs, TimeUnit.MILLISECONDS);
              channel.writeQueuedHttp();
            } catch (RejectedExecutionException ignored) {
              channel.closeQuietly();
            } finally {
              if (timeout != null) {
                timeout.cancel(false);
              }
              activeHttpChannels.remove(channel);
            }
          });
      return true;
    } catch (RuntimeException e) {
      activeHttpChannels.remove(channel);
      return false;
    }
  }

  int activeHttpCount() {
    return activeHttpChannels.size();
  }

  @Override
  public void close() {
    if (!closed.compareAndSet(false, true)) {
      return;
    }
    for (HttpOrWebSocketChannel channel : activeHttpChannels) {
      channel.closeQuietly();
    }
    httpWorkers.shutdownNow();
    httpTimeouts.shutdownNow();
  }
}
