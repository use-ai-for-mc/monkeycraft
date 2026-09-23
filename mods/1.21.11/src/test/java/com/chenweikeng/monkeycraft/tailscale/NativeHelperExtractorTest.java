package com.chenweikeng.monkeycraft.tailscale;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

class NativeHelperExtractorTest {
  @Test
  void extractsAndRepairsAStaleCachedHelper() throws Exception {
    Path directory = Files.createTempDirectory("monkeycraft-helper-test");
    Path target = directory.resolve("helper");
    Files.writeString(target, "stale");
    Files.writeString(target.resolveSibling("helper.sha256"), "wrong");

    Path extracted =
        NativeHelperExtractor.findOrExtract(
            NativeHelperExtractorTest.class, "/tailscale-test-helper.bin", target, false);

    assertNotNull(extracted);
    assertEquals("bundled-helper", Files.readString(extracted).trim());
    assertEquals(64, Files.readString(target.resolveSibling("helper.sha256")).trim().length());

    Files.writeString(target, "tampered");
    Path repaired =
        NativeHelperExtractor.findOrExtract(
            NativeHelperExtractorTest.class, "/tailscale-test-helper.bin", target, false);
    assertEquals("bundled-helper", Files.readString(repaired).trim());
  }
}
