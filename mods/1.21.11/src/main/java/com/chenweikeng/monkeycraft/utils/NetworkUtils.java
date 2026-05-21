package com.chenweikeng.monkeycraft.utils;

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
    List<String> result = new ArrayList<>();
    for (String ip : ips) {
      String entry = ip + ":" + port;
      if (isTailscaleLikeIpv4(ip)) {
        entry += " (tailscale like)";
      }
      result.add(entry);
    }
    return result;
  }

  // IPv4 in 100.64.0.0/10 (RFC 6598 shared address space, the range Tailscale
  // assigns to tailnet nodes). Not Tailscale-exclusive — ISP CGNAT uses the
  // same range — so the label is a hint, not an assertion.
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
}
