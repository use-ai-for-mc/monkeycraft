package com.chenweikeng.monkeycraft.config;

import com.chenweikeng.monkeycraft.utils.CommandPatterns;
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
              (JsonSerializer<NetworkScope>) (src, type, context) -> context.serialize(src.name()))
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
          .registerTypeAdapter(
              ServerAutoStart.class,
              (JsonDeserializer<ServerAutoStart>)
                  (json, type, context) -> {
                    try {
                      return ServerAutoStart.valueOf(json.getAsString());
                    } catch (Exception e) {
                      return ServerAutoStart.OFF;
                    }
                  })
          .registerTypeAdapter(
              ServerAutoStart.class,
              (JsonSerializer<ServerAutoStart>)
                  (src, type, context) -> context.serialize(src.name()))
          .create();

  private static ModConfig INSTANCE;

  private boolean enabled = true;
  private Boolean autoLaunch; // legacy; migrated to serverAutoStart on load
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
  private Boolean startServerAtLaunch; // legacy; migrated to serverAutoStart on load
  private ServerAutoStart serverAutoStart; // null until set or migrated; getter falls back to OFF
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
    this.tailscaleAccess = tailscaleAccess != null ? tailscaleAccess : TailscaleAccess.IF_DETECTED;
  }

  // One-time migration from the old single allowConnectionsFrom enum to the
  // split networkScope + tailscaleAccess model. Returns true if it migrated.
  private boolean migrateLegacyConnectionSetting() {
    if (allowConnectionsFrom == null) {
      return false;
    }
    networkScope = allowConnectionsFrom.toNetworkScope();
    tailscaleAccess = allowConnectionsFrom.toTailscaleAccess();
    allowConnectionsFrom = null;
    return true;
  }

  // One-time migration from the legacy autoLaunch + startServerAtLaunch boolean pair
  // to the unified serverAutoStart enum. Returns true if it migrated.
  // Precedence: an explicit new-style serverAutoStart wins; otherwise
  //   startServerAtLaunch=true  -> AT_TITLE_SCREEN  (it was the persistent one)
  //   autoLaunch=true           -> ON_WORLD_JOIN
  //   both false / absent       -> OFF
  private boolean migrateLegacyAutoStartFlags() {
    if (autoLaunch == null && startServerAtLaunch == null) {
      return false;
    }
    if (serverAutoStart == null) {
      if (Boolean.TRUE.equals(startServerAtLaunch)) {
        serverAutoStart = ServerAutoStart.AT_TITLE_SCREEN;
      } else if (Boolean.TRUE.equals(autoLaunch)) {
        serverAutoStart = ServerAutoStart.ON_WORLD_JOIN;
      } else {
        serverAutoStart = ServerAutoStart.OFF;
      }
    }
    autoLaunch = null;
    startServerAtLaunch = null;
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

  public boolean isCommandDenied(String command) {
    return CommandPatterns.matches(command, getCommandDenylist());
  }

  public boolean isCommandAllowed(String command) {
    return CommandPatterns.matches(command, getCommandAllowlist());
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

  public ServerAutoStart getServerAutoStart() {
    return serverAutoStart != null ? serverAutoStart : ServerAutoStart.OFF;
  }

  public void setServerAutoStart(ServerAutoStart serverAutoStart) {
    this.serverAutoStart = serverAutoStart != null ? serverAutoStart : ServerAutoStart.OFF;
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
        boolean migrated = false;
        if (config.migrateLegacyConnectionSetting()) {
          migrated = true;
        }
        if (config.migrateLegacyAutoStartFlags()) {
          migrated = true;
        }
        if (migrated) {
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

  /** Generates a random 12-character Base58 password (URL / QR / shell-safe). */
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
