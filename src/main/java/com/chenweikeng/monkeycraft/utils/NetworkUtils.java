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
      result.add(ip + ":" + port);
    }
    return result;
  }
}
