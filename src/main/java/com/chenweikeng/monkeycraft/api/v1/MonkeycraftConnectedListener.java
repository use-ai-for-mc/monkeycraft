package com.chenweikeng.monkeycraft.api.v1;

@FunctionalInterface
public interface MonkeycraftConnectedListener {
  void onConnected(String remoteAddress);
}
