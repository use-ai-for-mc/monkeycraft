package com.chenweikeng.monkeycraft.config;

public enum AllowConnectionsFrom {
  ONLY_LOCALHOST,
  ONLY_LOCAL_NETWORK,
  LOCAL_NETWORK_AND_TAILSCALE_RANGE,
  ANYWHERE;

  /** Maps a legacy value to the base scope in the split model. */
  public NetworkScope toNetworkScope() {
    return switch (this) {
      case ONLY_LOCALHOST -> NetworkScope.THIS_COMPUTER;
      case ANYWHERE -> NetworkScope.ANYONE;
      // ONLY_LOCAL_NETWORK and LOCAL_NETWORK_AND_TAILSCALE_RANGE
      default -> NetworkScope.LOCAL_NETWORK;
    };
  }

  /** Maps a legacy value to the Tailscale access policy in the split model. */
  public TailscaleAccess toTailscaleAccess() {
    return switch (this) {
      case ONLY_LOCALHOST -> TailscaleAccess.NEVER;
      case LOCAL_NETWORK_AND_TAILSCALE_RANGE -> TailscaleAccess.ALWAYS;
      // ONLY_LOCAL_NETWORK and ANYWHERE keep detect-by-default
      default -> TailscaleAccess.IF_DETECTED;
    };
  }
}
