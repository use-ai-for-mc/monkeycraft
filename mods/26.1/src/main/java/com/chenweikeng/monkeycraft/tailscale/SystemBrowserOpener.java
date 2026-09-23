package com.chenweikeng.monkeycraft.tailscale;

import java.io.IOException;
import java.net.URI;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

final class SystemBrowserOpener {
  private SystemBrowserOpener() {}

  static void open(String url) throws IOException {
    URI uri;
    try {
      uri = URI.create(url);
    } catch (IllegalArgumentException e) {
      throw new IOException("Invalid Tailscale login URL");
    }
    if (!"https".equalsIgnoreCase(uri.getScheme())
        || uri.getHost() == null
        || uri.getUserInfo() != null) {
      throw new IOException("Invalid Tailscale login URL");
    }
    String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
    List<String> command;
    if (os.contains("mac") || os.contains("darwin")) {
      command = List.of("/usr/bin/open", uri.toASCIIString());
    } else if (os.contains("win")) {
      command = List.of("rundll32", "url.dll,FileProtocolHandler", uri.toASCIIString());
    } else if (os.contains("linux")) {
      command = List.of("xdg-open", uri.toASCIIString());
    } else {
      throw new IOException("No supported system browser launcher");
    }
    Process launcher =
        new ProcessBuilder(command)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
    launcher.getOutputStream().close();
    try {
      if (launcher.waitFor(3, TimeUnit.SECONDS) && launcher.exitValue() != 0) {
        throw new IOException("System browser launcher failed");
      }
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IOException("System browser launch interrupted");
    }
  }
}
