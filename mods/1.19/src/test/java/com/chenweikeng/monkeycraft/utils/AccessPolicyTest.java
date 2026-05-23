package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.*;

import com.chenweikeng.monkeycraft.config.AllowConnectionsFrom;
import com.chenweikeng.monkeycraft.config.NetworkScope;
import com.chenweikeng.monkeycraft.config.TailscaleAccess;
import java.net.InetAddress;
import org.junit.jupiter.api.Test;

class AccessPolicyTest {

  private static InetAddress ip(String s) {
    try {
      return InetAddress.getByName(s);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }

  // --- legacy config migration mapping ---

  @Test
  void legacyMigrationMappings() {
    assertEquals(NetworkScope.THIS_COMPUTER, AllowConnectionsFrom.ONLY_LOCALHOST.toNetworkScope());
    assertEquals(TailscaleAccess.NEVER, AllowConnectionsFrom.ONLY_LOCALHOST.toTailscaleAccess());

    assertEquals(
        NetworkScope.LOCAL_NETWORK, AllowConnectionsFrom.ONLY_LOCAL_NETWORK.toNetworkScope());
    assertEquals(
        TailscaleAccess.IF_DETECTED, AllowConnectionsFrom.ONLY_LOCAL_NETWORK.toTailscaleAccess());

    assertEquals(
        NetworkScope.LOCAL_NETWORK,
        AllowConnectionsFrom.LOCAL_NETWORK_AND_TAILSCALE_RANGE.toNetworkScope());
    assertEquals(
        TailscaleAccess.ALWAYS,
        AllowConnectionsFrom.LOCAL_NETWORK_AND_TAILSCALE_RANGE.toTailscaleAccess());

    assertEquals(NetworkScope.ANYONE, AllowConnectionsFrom.ANYWHERE.toNetworkScope());
    assertEquals(TailscaleAccess.IF_DETECTED, AllowConnectionsFrom.ANYWHERE.toTailscaleAccess());
  }

  // --- IP allowlist matrix ---

  @Test
  void localNetworkAcceptsLanRejectsPublic() {
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.IF_DETECTED, false, ip("192.168.1.5")));
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.IF_DETECTED, false, ip("10.0.0.4")));
    assertFalse(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.IF_DETECTED, false, ip("8.8.8.8")));
  }

  @Test
  void tailscaleRangeFollowsTailscaleAccess() {
    InetAddress ts = ip("100.64.0.1");
    // IF_DETECTED: allowed only when a daemon is detected
    assertFalse(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.IF_DETECTED, false, ts));
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.IF_DETECTED, true, ts));
    // ALWAYS: allowed regardless of detection
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.ALWAYS, false, ts));
    // NEVER: blocked even when running
    assertFalse(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.LOCAL_NETWORK, TailscaleAccess.NEVER, true, ts));
  }

  @Test
  void thisComputerOnlyAllowsLoopbackAndAdditiveTailscale() {
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.THIS_COMPUTER, TailscaleAccess.NEVER, false, ip("127.0.0.1")));
    assertFalse(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.THIS_COMPUTER, TailscaleAccess.NEVER, false, ip("192.168.1.5")));
    // Tailscale access is additive even under THIS_COMPUTER
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.THIS_COMPUTER, TailscaleAccess.ALWAYS, false, ip("100.64.0.1")));
  }

  @Test
  void anyoneAllowsEverythingRegardlessOfTailscale() {
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.ANYONE, TailscaleAccess.NEVER, false, ip("8.8.8.8")));
    assertTrue(
        NetworkUtils.isConnectionAllowed(
            NetworkScope.ANYONE, TailscaleAccess.NEVER, false, ip("100.64.0.1")));
  }

  @Test
  void nullAddressIsRejected() {
    assertFalse(
        NetworkUtils.isConnectionAllowed(NetworkScope.ANYONE, TailscaleAccess.ALWAYS, true, null));
  }
}
