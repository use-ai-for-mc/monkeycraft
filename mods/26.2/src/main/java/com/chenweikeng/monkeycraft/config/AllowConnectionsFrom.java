package com.chenweikeng.monkeycraft.config;

public enum AllowConnectionsFrom {
  ONLY_LOCALHOST,
  ONLY_LOCAL_NETWORK,
  LOCAL_NETWORK_AND_TAILSCALE_RANGE,
  ANYWHERE;

  public NetworkScope toNetworkScope() {
    return switch (this) {
      case ONLY_LOCALHOST -> NetworkScope.THIS_COMPUTER;
      case ANYWHERE -> NetworkScope.ANYONE;
      default -> NetworkScope.LOCAL_NETWORK;
    };
  }
}
