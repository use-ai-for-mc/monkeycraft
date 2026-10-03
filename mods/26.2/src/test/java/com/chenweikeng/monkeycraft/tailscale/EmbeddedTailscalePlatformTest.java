package com.chenweikeng.monkeycraft.tailscale;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

class EmbeddedTailscalePlatformTest {
  @Test
  void supportsOnlyWindowsX64AndAppleSilicon() {
    assertEquals("windows-amd64", EmbeddedTailscalePlatform.select("Windows 11", "amd64"));
    assertEquals("windows-amd64", EmbeddedTailscalePlatform.select("Windows 10", "x86_64"));
    assertEquals("darwin-arm64", EmbeddedTailscalePlatform.select("Mac OS X", "aarch64"));
    assertEquals("darwin-arm64", EmbeddedTailscalePlatform.select("Darwin", "arm64"));
    assertNull(EmbeddedTailscalePlatform.select("Mac OS X", "x86_64"));
    assertNull(EmbeddedTailscalePlatform.select("Darwin", "amd64"));
    assertNull(EmbeddedTailscalePlatform.select("Linux", "amd64"));
    assertNull(EmbeddedTailscalePlatform.select("Linux", "aarch64"));
    assertNull(EmbeddedTailscalePlatform.select("Windows 11", "aarch64"));
    assertNull(EmbeddedTailscalePlatform.select("Windows 10", "x86"));
    assertNull(EmbeddedTailscalePlatform.select("Mac OS X", "unknown"));
  }

  @Test
  void unsupportedHostRejectsLoginWithoutStartingAHelper() {
    String os = System.getProperty("os.name");
    String arch = System.getProperty("os.arch");
    try {
      System.setProperty("os.name", "Linux");
      System.setProperty("os.arch", "amd64");
      HelperTailscaleService service = new HelperTailscaleService(null, null, null);
      assertEquals("UNSUPPORTED_PLATFORM", service.ensureRunning(9600).errorCode());
      assertEquals("UNSUPPORTED_PLATFORM", service.login(9600).errorCode());
      assertEquals("UNSUPPORTED_PLATFORM", service.status().errorCode());
      assertEquals("UNSUPPORTED_PLATFORM", service.snapshot().errorCode());
      assertFalse(service.snapshot().recoverable());
      assertFalse(service.isProcessAliveForTest());
    } finally {
      System.setProperty("os.name", os);
      System.setProperty("os.arch", arch);
    }
  }
}
