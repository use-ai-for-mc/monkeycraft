package com.chenweikeng.monkeycraft.utils;

import com.chenweikeng.monkeycraft.config.NetworkScope;
import com.chenweikeng.monkeycraft.config.TailscaleAccess;
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
    List<String> ips = getLocalIpAddresses();
    boolean tailscaleRunning = isTailscaleRunning();
    List<String> result = new ArrayList<>();
    for (String ip : ips) {
      String entry = ip + ":" + port;
      if (isTailscaleLikeIpv4(ip)) {
        entry += tailscaleRunning ? " (Tailscale)" : " (possibly Tailscale)";
      }
      result.add(entry);
    }
    return result;
  }

  // IPv4 in 100.64.0.0/10 (RFC 6598 shared address space, the range Tailscale
  // assigns to tailnet nodes). Not Tailscale-exclusive — ISP CGNAT uses the
  // same range — so the label alone is a hint, not an assertion.
  private static boolean isTailscaleLikeIpv4(String ip) {
    String[] parts = ip.split("\\.");
    if (parts.length != 4) return false;
    try {
      int first = Integer.parseInt(parts[0]);
      int second = Integer.parseInt(parts[1]);
      return first == 100 && second >= 64 && second <= 127;
    } catch (NumberFormatException e) {
      return false;
    }
  }

  // Best-effort check for whether a local Tailscale daemon is running.
  // Linux:   literal "tailscale0" interface name.
  // Windows: Wintun adapter whose display name contains "Tailscale".
  // macOS:   any utun* interface holding an IPv4 address in 100.64.0.0/10
  //          (the utun name varies per boot, so the IP is the signal).
  public static boolean isTailscaleRunning() {
    try {
      Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
      if (interfaces == null) return false;
      while (interfaces.hasMoreElements()) {
        NetworkInterface iface = interfaces.nextElement();
        if (!iface.isUp()) continue;

        String name = iface.getName();
        String displayName = iface.getDisplayName();

        if ("tailscale0".equals(name)) return true;

        if (displayName != null && displayName.toLowerCase().contains("tailscale")) {
          return true;
        }

        if (name != null && name.startsWith("utun")) {
          Enumeration<InetAddress> addrs = iface.getInetAddresses();
          while (addrs.hasMoreElements()) {
            InetAddress addr = addrs.nextElement();
            if (addr instanceof Inet4Address) {
              byte[] b = addr.getAddress();
              if ((b[0] & 0xFF) == 100 && (b[1] & 0xFF) >= 64 && (b[1] & 0xFF) <= 127) {
                return true;
              }
            }
          }
        }
      }
    } catch (Exception e) {
      // fail closed
    }
    return false;
  }

  /**
   * Pure access decision shared by the live server and tests. The Tailscale {@code 100.64.0.0/10}
   * range is governed by {@code tailscale} independently of (and additively to) {@code scope};
   * everything else is governed by {@code scope}.
   */
  public static boolean isConnectionAllowed(
      NetworkScope scope, TailscaleAccess tailscale, boolean tailscaleRunning, InetAddress addr) {
    if (addr == null) {
      return false;
    }
    if (isTailscaleRangeAddr(addr)) {
      if (tailscale == TailscaleAccess.ALWAYS) {
        return true;
      }
      if (tailscale == TailscaleAccess.IF_DETECTED && tailscaleRunning) {
        return true;
      }
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
    // scope == LOCAL_NETWORK
    if (addr.isLinkLocalAddress() || addr.isSiteLocalAddress()) {
      return true;
    }
    byte[] bytes = addr.getAddress();
    if (bytes.length == 4) {
      if (bytes[0] == 10) {
        return true;
      }
      if ((bytes[0] & 0xFF) == 172 && (bytes[1] & 0xFF) >= 16 && (bytes[1] & 0xFF) <= 31) {
        return true;
      }
      if ((bytes[0] & 0xFF) == 192 && (bytes[1] & 0xFF) == 168) {
        return true;
      }
    }
    return false;
  }

  private static boolean isTailscaleRangeAddr(InetAddress addr) {
    byte[] b = addr.getAddress();
    return b.length == 4 && (b[0] & 0xFF) == 100 && (b[1] & 0xFF) >= 64 && (b[1] & 0xFF) <= 127;
  }
}
