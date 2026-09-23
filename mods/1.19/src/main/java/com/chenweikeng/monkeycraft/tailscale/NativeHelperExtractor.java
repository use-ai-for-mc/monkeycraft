package com.chenweikeng.monkeycraft.tailscale;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public final class NativeHelperExtractor {
  private NativeHelperExtractor() {}

  public static Path findOrExtract(
      Class<?> owner, String resource, Path target, boolean executable) {
    String expected;
    try (InputStream in = owner.getResourceAsStream(resource)) {
      if (in == null) {
        return null;
      }
      expected = sha256(in);
    } catch (IOException e) {
      MonkeycraftClient.LOGGER.warn("Unable to read bundled Tailscale helper: {}", e.getMessage());
      return null;
    }
    Path sidecar = target.resolveSibling(target.getFileName() + ".sha256");
    try {
      if (Files.isRegularFile(target)
          && (!executable || Files.isExecutable(target))
          && Files.isRegularFile(sidecar)
          && expected.equals(Files.readString(sidecar, StandardCharsets.UTF_8).trim())
          && expected.equals(sha256(target))) {
        return target;
      }
      Files.createDirectories(target.getParent());
      Path temporary =
          target.resolveSibling(target.getFileName() + ".tmp" + Thread.currentThread().getId());
      try (InputStream in = owner.getResourceAsStream(resource)) {
        if (in == null) {
          return null;
        }
        Files.copy(in, temporary, StandardCopyOption.REPLACE_EXISTING);
        if (executable) {
          temporary.toFile().setExecutable(true, true);
        }
        Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING);
        Files.writeString(sidecar, expected, StandardCharsets.UTF_8);
        return target;
      } finally {
        Files.deleteIfExists(temporary);
      }
    } catch (IOException e) {
      MonkeycraftClient.LOGGER.warn(
          "Unable to extract bundled Tailscale helper: {}", e.getMessage());
      return null;
    }
  }

  private static String sha256(InputStream in) throws IOException {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] buffer = new byte[8192];
      for (int read; (read = in.read(buffer)) > 0; ) {
        digest.update(buffer, 0, read);
      }
      return java.util.HexFormat.of().formatHex(digest.digest());
    } catch (NoSuchAlgorithmException e) {
      throw new IOException("SHA-256 unavailable", e);
    }
  }

  private static String sha256(Path path) throws IOException {
    try (InputStream in = Files.newInputStream(path)) {
      return sha256(in);
    }
  }
}
