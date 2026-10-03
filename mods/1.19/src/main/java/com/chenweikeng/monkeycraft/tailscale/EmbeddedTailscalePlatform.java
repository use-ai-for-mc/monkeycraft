package com.chenweikeng.monkeycraft.tailscale;

import java.util.Locale;

public final class EmbeddedTailscalePlatform {
  public static final String UNSUPPORTED_MESSAGE =
      "Built-in Tailscale is supported only on Windows x64 and Apple Silicon Macs."
          + " Use LAN or the system Tailscale app on this computer.";

  private EmbeddedTailscalePlatform() {}

  public static String current() {
    return select(System.getProperty("os.name", ""), System.getProperty("os.arch", ""));
  }

  public static boolean isSupported() {
    return current() != null;
  }

  static String select(String os, String arch) {
    os = os.toLowerCase(Locale.ROOT);
    arch = arch.toLowerCase(Locale.ROOT);
    if ((os.equals("mac os x") || os.equals("macos") || os.equals("darwin"))
        && (arch.equals("aarch64") || arch.equals("arm64"))) {
      return "darwin-arm64";
    }
    if (os.startsWith("windows") && (arch.equals("amd64") || arch.equals("x86_64"))) {
      return "windows-amd64";
    }
    return null;
  }
}
