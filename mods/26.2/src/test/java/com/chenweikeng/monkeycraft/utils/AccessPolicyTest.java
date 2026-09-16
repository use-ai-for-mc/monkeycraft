package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.*;

import com.chenweikeng.monkeycraft.config.AllowConnectionsFrom;
import com.chenweikeng.monkeycraft.config.NetworkScope;
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

  @Test
  void legacyMigrationMappings() {
    assertEquals(NetworkScope.THIS_COMPUTER, AllowConnectionsFrom.ONLY_LOCALHOST.toNetworkScope());
    assertEquals(
        NetworkScope.LOCAL_NETWORK, AllowConnectionsFrom.ONLY_LOCAL_NETWORK.toNetworkScope());
    assertEquals(
        NetworkScope.LOCAL_NETWORK,
        AllowConnectionsFrom.LOCAL_NETWORK_AND_TAILSCALE_RANGE.toNetworkScope());
    assertEquals(NetworkScope.ANYONE, AllowConnectionsFrom.ANYWHERE.toNetworkScope());
  }

  @Test
  void localNetworkAcceptsLanAndCgnatRejectsPublic() {
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.LOCAL_NETWORK, ip("192.168.1.5")));
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.LOCAL_NETWORK, ip("10.0.0.4")));
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.LOCAL_NETWORK, ip("100.64.0.1")));
    assertFalse(NetworkUtils.isConnectionAllowed(NetworkScope.LOCAL_NETWORK, ip("8.8.8.8")));
  }

  @Test
  void thisComputerOnlyAllowsLoopback() {
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.THIS_COMPUTER, ip("127.0.0.1")));
    assertFalse(NetworkUtils.isConnectionAllowed(NetworkScope.THIS_COMPUTER, ip("192.168.1.5")));
    assertFalse(NetworkUtils.isConnectionAllowed(NetworkScope.THIS_COMPUTER, ip("100.64.0.1")));
  }

  @Test
  void anyoneAllowsEverything() {
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.ANYONE, ip("8.8.8.8")));
    assertTrue(NetworkUtils.isConnectionAllowed(NetworkScope.ANYONE, ip("100.64.0.1")));
  }

  @Test
  void nullAddressIsRejected() {
    assertFalse(NetworkUtils.isConnectionAllowed(NetworkScope.ANYONE, null));
  }

  @Test
  void pairingAllowsLocalLanAndCgnatOnly() {
    assertTrue(NetworkUtils.isPairingAllowed(ip("127.0.0.1")));
    assertTrue(NetworkUtils.isPairingAllowed(ip("192.168.1.5")));
    assertTrue(NetworkUtils.isPairingAllowed(ip("10.0.0.4")));
    assertTrue(NetworkUtils.isPairingAllowed(ip("172.16.1.2")));
    assertTrue(NetworkUtils.isPairingAllowed(ip("100.64.0.1")));
    assertFalse(NetworkUtils.isPairingAllowed(ip("8.8.8.8")));
    assertFalse(NetworkUtils.isPairingAllowed(null));
  }
}
