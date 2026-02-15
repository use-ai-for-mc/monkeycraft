package com.chenweikeng.monkeycraft.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import net.fabricmc.loader.api.FabricLoader;

public class ModConfig {
  private static final String BASE58_CHARS =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  private static final int DEFAULT_PASSWORD_LENGTH = 12;
  private static final int MIN_PORT = 1;
  private static final int MAX_PORT = 65535;
  private static final Path CONFIG_PATH =
      FabricLoader.getInstance().getConfigDir().resolve("monkeycraft.json");
  private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

  private static ModConfig INSTANCE;

  private boolean enabled = true;
  private boolean autoLaunch = false;
  private int port = 9600;
  private String password;

  public static ModConfig getInstance() {
    if (INSTANCE == null) {
      INSTANCE = load();
    }
    return INSTANCE;
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public boolean isAutoLaunch() {
    return autoLaunch;
  }

  public void setAutoLaunch(boolean autoLaunch) {
    this.autoLaunch = autoLaunch;
  }

  public int getPort() {
    return port;
  }

  public void setPort(int port) {
    this.port = Math.max(MIN_PORT, Math.min(MAX_PORT, port));
  }

  public String getPassword() {
    return password;
  }

  public void setPassword(String password) {
    this.password = password;
  }

  public void save() {
    try {
      Files.writeString(CONFIG_PATH, GSON.toJson(this));
    } catch (IOException e) {
      throw new RuntimeException("Failed to save config", e);
    }
  }

  private static ModConfig load() {
    if (Files.exists(CONFIG_PATH)) {
      try {
        String json = Files.readString(CONFIG_PATH);
        ModConfig config = GSON.fromJson(json, ModConfig.class);
        if (config.password == null || config.password.isEmpty()) {
          config.password = generateRandomPassword();
          config.save();
        }
        return config;
      } catch (IOException e) {
        throw new RuntimeException("Failed to load config", e);
      }
    } else {
      ModConfig config = new ModConfig();
      config.password = generateRandomPassword();
      config.save();
      return config;
    }
  }

  private static String generateRandomPassword() {
    SecureRandom random = new SecureRandom();
    StringBuilder sb = new StringBuilder(DEFAULT_PASSWORD_LENGTH);
    for (int i = 0; i < DEFAULT_PASSWORD_LENGTH; i++) {
      int index = random.nextInt(BASE58_CHARS.length());
      sb.append(BASE58_CHARS.charAt(index));
    }
    return sb.toString();
  }
}
