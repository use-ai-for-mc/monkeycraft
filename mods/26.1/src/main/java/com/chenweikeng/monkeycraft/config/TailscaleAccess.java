package com.chenweikeng.monkeycraft.config;

/** Governs the Tailscale 100.64.0.0/10 range independently of {@link NetworkScope}. */
public enum TailscaleAccess {
  IF_DETECTED,
  ALWAYS,
  NEVER
}
