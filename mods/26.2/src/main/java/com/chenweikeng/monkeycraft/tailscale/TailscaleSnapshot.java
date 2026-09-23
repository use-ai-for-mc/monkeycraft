package com.chenweikeng.monkeycraft.tailscale;

public record TailscaleSnapshot(
    String state,
    String tailnetIp,
    String nodeId,
    int port,
    boolean listening,
    int connections,
    String errorCode,
    String error,
    boolean recoverable) {
  public static TailscaleSnapshot stopped() {
    return new TailscaleSnapshot("stopped", "", "", 0, false, 0, "", "", false);
  }

  public boolean needsLogin() {
    return "needsLogin".equals(state);
  }

  public boolean isRunning() {
    return "running".equals(state) && listening;
  }
}
