package com.chenweikeng.monkeycraft.config;

/** Base network access scope: who (besides Tailscale) may reach the server. */
public enum NetworkScope {
  THIS_COMPUTER,
  LOCAL_NETWORK,
  ANYONE
}
