package com.chenweikeng.monkeycraft.api.v1;

import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.fabricmc.fabric.api.event.Event;
import net.fabricmc.fabric.api.event.EventFactory;

public final class MonkeycraftApi {
  private MonkeycraftApi() {}

  public static final Event<MonkeycraftConnectedListener> CONNECTION =
      EventFactory.createArrayBacked(
          MonkeycraftConnectedListener.class,
          (listeners) ->
              (remoteAddress) -> {
                for (MonkeycraftConnectedListener listener : listeners) {
                  listener.onConnected(remoteAddress);
                }
              });

  public static final Event<MonkeycraftDisconnectedListener> DISCONNECTION =
      EventFactory.createArrayBacked(
          MonkeycraftDisconnectedListener.class,
          (listeners) ->
              () -> {
                for (MonkeycraftDisconnectedListener listener : listeners) {
                  listener.onDisconnected();
                }
              });

  public static void setTimedNotification(
      Long fireAtEpochMs, String title, String body, boolean sound) {
    WebSocketServerHandler.getInstance().sendTimedNotification(fireAtEpochMs, title, body, sound);
  }

  public static void cancelTimedNotification() {
    WebSocketServerHandler.getInstance().cancelTimedNotification();
  }

  public static void sendImmediateNotification(String title, String body, boolean sound) {
    WebSocketServerHandler.getInstance().sendNudge(title, body, sound);
  }

  public static void startHibernation(String message) {
    WebSocketServerHandler.getInstance().startHibernation(message);
  }

  public static void endHibernation() {
    WebSocketServerHandler.getInstance().endHibernation();
  }

  public static boolean isClientConnected() {
    return WebSocketServerHandler.getInstance().isClientConnected();
  }

  public static boolean isHibernating() {
    return WebSocketServerHandler.getInstance().isHibernating();
  }
}
