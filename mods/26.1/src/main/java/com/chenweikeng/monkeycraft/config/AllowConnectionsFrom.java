package com.chenweikeng.monkeycraft.config;

public enum AllowConnectionsFrom {
  ONLY_LOCALHOST,
  ONLY_LOCAL_NETWORK,
  LOCAL_NETWORK_AND_TAILSCALE_RANGE,
  ANYWHERE
}
