package com.chenweikeng.monkeycraft.server;

import java.nio.channels.ByteChannel;
import java.nio.channels.SelectionKey;
import java.nio.channels.SocketChannel;
import java.util.List;
import org.java_websocket.WebSocketAdapter;
import org.java_websocket.WebSocketImpl;
import org.java_websocket.WebSocketServerFactory;
import org.java_websocket.drafts.Draft;

final class HttpAwareWebSocketServerFactory implements WebSocketServerFactory {
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
    return new HttpOrWebSocketChannel(channel);
  }

  @Override
  public void close() {}
}
