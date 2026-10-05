package com.chenweikeng.monkeycraft.tailscale;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import net.fabricmc.loader.api.FabricLoader;

public final class EmbeddedTailscaleService {
  private static final String BACKEND = selectedBackend();
  private static final TailscaleBackend INSTANCE =
      BACKEND.equals("java")
          ? new JavaTailscaleService(
              () -> FabricLoader.getInstance().getConfigDir().resolve("monkeycraft/tailscale-java"))
          : HelperTailscaleService.get();

  private EmbeddedTailscaleService() {}

  public static TailscaleBackend get() {
    return INSTANCE;
  }

  public static String backendName() {
    return BACKEND.equals("java") ? "Java (test)" : "Native";
  }

  private static String selectedBackend() {
    String selected = System.getProperty("monkeycraft.tailscale.backend", "").trim();
    if (selected.isEmpty()) {
      try (InputStream input =
          EmbeddedTailscaleService.class.getResourceAsStream(
              "/monkeycraft-tailscale-backend.txt")) {
        selected =
            input == null
                ? "helper"
                : new String(input.readAllBytes(), StandardCharsets.UTF_8).trim();
      } catch (Exception e) {
        throw new IllegalStateException("Cannot read embedded Tailscale backend", e);
      }
    }
    if (!selected.equals("java") && !selected.equals("helper")) {
      throw new IllegalArgumentException("monkeycraft.tailscale.backend must be java or helper");
    }
    return selected;
  }
}
