package com.chenweikeng.monkeycraft.utils;

import com.chenweikeng.monkeycraft.config.NetworkScope;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;

public class NetworkUtils {

  public static List<String> getLocalIpAddresses() {
    List<String> ips = new ArrayList<>();
    try {
      Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
      if (interfaces == null) return ips;

      while (interfaces.hasMoreElements()) {
        NetworkInterface iface = interfaces.nextElement();

        if (iface.isLoopback() || !iface.isUp() || iface.isVirtual()) {
          continue;
        }

        Enumeration<InetAddress> addresses = iface.getInetAddresses();
        while (addresses.hasMoreElements()) {
          InetAddress addr = addresses.nextElement();

          if (addr.isLoopbackAddress()) continue;
          if (addr.isLinkLocalAddress()) continue;
          if (!(addr instanceof Inet4Address)) continue;

          ips.add(addr.getHostAddress());
        }
      }
    } catch (Exception e) {
      ips.clear();
    }
    return ips;
  }

  public static List<String> getLocalIpAddressesWithPort(int port) {
    List<String> result = new ArrayList<>();
    for (String ip : getLocalIpAddresses()) {
      result.add(ip + ":" + port);
    }
    return result;
  }

  public static boolean isConnectionAllowed(NetworkScope scope, InetAddress addr) {
    if (addr == null) {
      return false;
    }
    if (scope == NetworkScope.ANYONE) {
      return true;
    }
    if (addr.isLoopbackAddress()) {
      return true;
    }
    if (scope == NetworkScope.THIS_COMPUTER) {
      return false;
    }
    if (addr.isLinkLocalAddress() || addr.isSiteLocalAddress() || isRfc1918OrCgnat(addr)) {
      return true;
    }
    return false;
  }

  public static boolean isPairingAllowed(InetAddress addr) {
    if (addr == null) {
      return false;
    }
    if (addr.isLoopbackAddress() || addr.isLinkLocalAddress() || addr.isSiteLocalAddress()) {
      return true;
    }
    return isRfc1918OrCgnat(addr);
  }

  private static boolean isRfc1918OrCgnat(InetAddress addr) {
    byte[] bytes = addr.getAddress();
    if (bytes.length != 4) {
      return false;
    }
    int first = bytes[0] & 0xFF;
    int second = bytes[1] & 0xFF;
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    if (first == 192 && second == 168) {
      return true;
    }
    return first == 100 && second >= 64 && second <= 127;
  }
}
