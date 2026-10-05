package com.chenweikeng.monkeycraft.tailscale;

public interface TailscaleBackend {
  TailscaleSnapshot ensureRunning(int targetPort);

  TailscaleSnapshot login(int targetPort);

  TailscaleSnapshot status();

  TailscaleSnapshot snapshot();

  void stop();

  void logout();

  void shutdown();
}
