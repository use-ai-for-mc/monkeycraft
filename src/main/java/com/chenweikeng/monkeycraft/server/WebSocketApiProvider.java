package com.chenweikeng.monkeycraft.server;

import com.chenweikeng.monkeycraft_api.v1.MonkeycraftApiProvider;

public final class WebSocketApiProvider implements MonkeycraftApiProvider {
  @Override
  public void setTimedNotification(
      Long fireAtEpochMs, String title, String body, boolean sound, String countDownText) {
    WebSocketServerHandler.getInstance()
        .sendTimedNotification(fireAtEpochMs, title, body, sound, countDownText);
  }

  @Override
  public void cancelTimedNotification() {
    WebSocketServerHandler.getInstance().cancelTimedNotification();
  }

  @Override
  public void sendImmediateNotification(String title, String body, boolean sound) {
    WebSocketServerHandler.getInstance().sendNudge(title, body, sound);
  }

  @Override
  public void startHibernation(String message) {
    WebSocketServerHandler.getInstance().startHibernation(message);
  }

  @Override
  public void setHibernationMessage(String message) {
    WebSocketServerHandler.getInstance().setHibernationMessage(message);
  }

  @Override
  public void endHibernation() {
    WebSocketServerHandler.getInstance().endHibernation();
  }

  @Override
  public boolean isClientConnected() {
    return WebSocketServerHandler.getInstance().isClientConnected();
  }

  @Override
  public boolean isHibernating() {
    return WebSocketServerHandler.getInstance().isHibernating();
  }
}
