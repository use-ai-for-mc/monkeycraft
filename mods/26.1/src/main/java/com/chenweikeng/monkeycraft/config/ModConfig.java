package com.chenweikeng.monkeycraft.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonDeserializer;
import com.google.gson.JsonSerializer;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import net.fabricmc.loader.api.FabricLoader;

public class ModConfig {
  private static final String BASE58_CHARS =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  private static final int DEFAULT_PASSWORD_LENGTH = 12;
  private static final int MIN_PORT = 1;
  private static final int MAX_PORT = 65535;
  private static final Path CONFIG_PATH =
      FabricLoader.getInstance().getConfigDir().resolve("monkeycraft.json");
  private static final Gson GSON =
      new GsonBuilder()
          .setPrettyPrinting()
          // Legacy field, read only for one-time migration to the split model.
          .registerTypeAdapter(
              AllowConnectionsFrom.class,
              (JsonDeserializer<AllowConnectionsFrom>)
                  (json, type, context) -> {
                    try {
                      return AllowConnectionsFrom.valueOf(json.getAsString());
                    } catch (Exception e) {
                      return null;
                    }
                  })
          .registerTypeAdapter(
              NetworkScope.class,
              (JsonDeserializer<NetworkScope>)
                  (json, type, context) -> {
                    try {
                      return NetworkScope.valueOf(json.getAsString());
                    } catch (Exception e) {
                      return NetworkScope.LOCAL_NETWORK;
                    }
                  })
          .registerTypeAdapter(
              NetworkScope.class,
              (JsonSerializer<NetworkScope>)
                  (src, type, context) -> context.serialize(src.name()))
          .registerTypeAdapter(
              TailscaleAccess.class,
              (JsonDeserializer<TailscaleAccess>)
                  (json, type, context) -> {
                    try {
                      return TailscaleAccess.valueOf(json.getAsString());
                    } catch (Exception e) {
                      return TailscaleAccess.IF_DETECTED;
                    }
                  })
          .registerTypeAdapter(
              TailscaleAccess.class,
              (JsonSerializer<TailscaleAccess>)
                  (src, type, context) -> context.serialize(src.name()))
          .create();

  private static ModConfig INSTANCE;

  private boolean enabled = true;
  private boolean autoLaunch = false;
  private boolean showQrCodeWhenAutoLaunch = false;
  private int port = 9600;
  private String password;
  private AllowConnectionsFrom allowConnectionsFrom = null; // legacy; migrated on load
  private NetworkScope networkScope = NetworkScope.LOCAL_NETWORK;
  private TailscaleAccess tailscaleAccess = TailscaleAccess.IF_DETECTED;
  private List<String> commandAllowlist = new ArrayList<>(List.of("*"));
  private List<String> commandDenylist = new ArrayList<>(List.of("op *", "deop *"));
  private String defaultBehavior = "ALLOW";
  private boolean alwaysAutoJump = true;
  private boolean startServerAtLaunch = false;
  private boolean allowRemoteServerJoin = true;

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

  public boolean isShowQrCodeWhenAutoLaunch() {
    return showQrCodeWhenAutoLaunch;
  }

  public void setShowQrCodeWhenAutoLaunch(boolean showQrCodeWhenAutoLaunch) {
    this.showQrCodeWhenAutoLaunch = showQrCodeWhenAutoLaunch;
  }

  public int getPort() {
    return port;
  }

  public void setPort(int port) {
    this.port = Math.max(MIN_PORT, Math.min(MAX_PORT, port));
  }

  public NetworkScope getNetworkScope() {
    return networkScope != null ? networkScope : NetworkScope.LOCAL_NETWORK;
  }

  public void setNetworkScope(NetworkScope networkScope) {
    this.networkScope = networkScope != null ? networkScope : NetworkScope.LOCAL_NETWORK;
  }

  public TailscaleAccess getTailscaleAccess() {
    return tailscaleAccess != null ? tailscaleAccess : TailscaleAccess.IF_DETECTED;
  }

  public void setTailscaleAccess(TailscaleAccess tailscaleAccess) {
    this.tailscaleAccess =
        tailscaleAccess != null ? tailscaleAccess : TailscaleAccess.IF_DETECTED;
  }

  // One-time migration from the old single allowConnectionsFrom enum to the
  // split networkScope + tailscaleAccess model. Returns true if it migrated.
  private boolean migrateLegacyConnectionSetting() {
    if (allowConnectionsFrom == null) {
      return false;
    }
    switch (allowConnectionsFrom) {
      case ONLY_LOCALHOST -> {
        networkScope = NetworkScope.THIS_COMPUTER;
        tailscaleAccess = TailscaleAccess.NEVER;
      }
      case LOCAL_NETWORK_AND_TAILSCALE_RANGE -> {
        networkScope = NetworkScope.LOCAL_NETWORK;
        tailscaleAccess = TailscaleAccess.ALWAYS;
      }
      case ANYWHERE -> {
        networkScope = NetworkScope.ANYONE;
        tailscaleAccess = TailscaleAccess.IF_DETECTED;
      }
      default -> {
        networkScope = NetworkScope.LOCAL_NETWORK;
        tailscaleAccess = TailscaleAccess.IF_DETECTED;
      }
    }
    allowConnectionsFrom = null;
    return true;
  }

  public String getPassword() {
    return password;
  }

  public void setPassword(String password) {
    this.password = password;
  }

  public List<String> getCommandAllowlist() {
    if (commandAllowlist == null) {
      commandAllowlist = new ArrayList<>(List.of("*"));
    }
    return commandAllowlist;
  }

  public void setCommandAllowlist(List<String> allowlist) {
    this.commandAllowlist =
        allowlist != null ? new ArrayList<>(allowlist) : new ArrayList<>(List.of("*"));
  }

  public List<String> getCommandDenylist() {
    if (commandDenylist == null) {
      commandDenylist = new ArrayList<>(List.of("op *", "deop *"));
    }
    return commandDenylist;
  }

  public void setCommandDenylist(List<String> denylist) {
    this.commandDenylist =
        denylist != null ? new ArrayList<>(denylist) : new ArrayList<>(List.of("op *", "deop *"));
  }

  public String getDefaultBehavior() {
    if (defaultBehavior == null || defaultBehavior.isEmpty()) {
      defaultBehavior = "ALLOW";
    }
    return defaultBehavior;
  }

  public void setDefaultBehavior(String behavior) {
    if ("ALLOW".equalsIgnoreCase(behavior) || "DENY".equalsIgnoreCase(behavior)) {
      this.defaultBehavior = behavior.toUpperCase();
    } else {
      this.defaultBehavior = "ALLOW";
    }
  }

  private boolean matchesPattern(String command, List<String> patterns) {
    if (patterns == null || patterns.isEmpty()) {
      return false;
    }
    String cmd = command.startsWith("/") ? command.substring(1) : command;
    String cmdLower = cmd.toLowerCase();
    for (String pattern : patterns) {
      if (pattern == null || pattern.isEmpty()) continue;
      String patternLower = pattern.toLowerCase().trim();
      if (patternLower.equals("*")) {
        return true;
      }
      if (patternLower.endsWith(" *")) {
        String prefix = patternLower.substring(0, patternLower.length() - 2);
        if (cmdLower.startsWith(prefix)) {
          return true;
        }
      } else {
        if (cmdLower.equals(patternLower)) {
          return true;
        }
      }
    }
    return false;
  }

  public boolean isCommandDenied(String command) {
    return matchesPattern(command, getCommandDenylist());
  }

  public boolean isCommandAllowed(String command) {
    return matchesPattern(command, getCommandAllowlist());
  }

  public boolean isCommandPermittedByDefault() {
    return "ALLOW".equalsIgnoreCase(getDefaultBehavior());
  }

  public boolean isAlwaysAutoJump() {
    return alwaysAutoJump;
  }

  public void setAlwaysAutoJump(boolean alwaysAutoJump) {
    this.alwaysAutoJump = alwaysAutoJump;
  }

  public boolean isStartServerAtLaunch() {
    return startServerAtLaunch;
  }

  public void setStartServerAtLaunch(boolean startServerAtLaunch) {
    this.startServerAtLaunch = startServerAtLaunch;
  }

  public boolean isAllowRemoteServerJoin() {
    return allowRemoteServerJoin;
  }

  public void setAllowRemoteServerJoin(boolean allowRemoteServerJoin) {
    this.allowRemoteServerJoin = allowRemoteServerJoin;
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
        if (config.commandAllowlist == null) {
          config.commandAllowlist = new ArrayList<>(List.of("*"));
        }
        if (config.commandDenylist == null) {
          config.commandDenylist = new ArrayList<>(List.of("op *", "deop *"));
        }
        if (config.defaultBehavior == null || config.defaultBehavior.isEmpty()) {
          config.defaultBehavior = "ALLOW";
        }
        if (config.migrateLegacyConnectionSetting()) {
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

  public static String generateRandomPassword() {
    SecureRandom random = new SecureRandom();
    StringBuilder sb = new StringBuilder(DEFAULT_PASSWORD_LENGTH);
    for (int i = 0; i < DEFAULT_PASSWORD_LENGTH; i++) {
      int index = random.nextInt(BASE58_CHARS.length());
      sb.append(BASE58_CHARS.charAt(index));
    }
    return sb.toString();
  }
}
