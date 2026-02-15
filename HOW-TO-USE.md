# RemoteCraft v1 API — How to Use (External Mod)

This repo exposes a small public API for other **client-side Fabric mods** to integrate with RemoteCraft.

API package (versioned):

- `com.chenweikeng.remotecraft.api.v1`

## What the API Provides

- Connection lifecycle events (phone client authenticated / disconnected)
- Notifications
  - Timed notification (overwrites the existing scheduled notification)
  - Immediate notification (only meaningful while the phone app is active/connected)
- Hibernation control (pause/resume remote streaming while keeping the WS connection)

## Files / Entry Points (RemoteCraft side)

- API: `src/main/java/com/chenweikeng/remotecraft/api/v1/RemoteCraftApi.java`
- Events: `RemoteCraftApi.CONNECTION` and `RemoteCraftApi.DISCONNECTION`
- Notification methods:
  - `RemoteCraftApi.setTimedNotification(...)`
  - `RemoteCraftApi.cancelTimedNotification()`
  - `RemoteCraftApi.sendImmediateNotification(...)`
- Hibernation methods:
  - `RemoteCraftApi.startHibernation(message)`
  - `RemoteCraftApi.endHibernation()`
- State queries:
  - `RemoteCraftApi.isClientConnected()`
  - `RemoteCraftApi.isHibernating()`

## Using the API From Another Mod (Optional Dependency)

Goal: your mod should work even if RemoteCraft is not installed.

### 1) Compile Against RemoteCraft Locally

Use Maven Local (recommended).

Current coordinates (this repo):

- groupId: `com.chenweikeng.remotecraft`
- artifactId: `remotecraft`
- version: `1.0.0`

1. In the RemoteCraft repo, publish to your local Maven cache:
   - `./gradlew publishToMavenLocal`
2. In your other mod, add `mavenLocal()` and a dependency on RemoteCraft:

```gradle
repositories {
  mavenLocal()
  mavenCentral()
}

dependencies {
  modCompileOnly "com.chenweikeng.remotecraft:remotecraft:1.0.0"
}
```

This avoids copying jars and makes it easy to reuse RemoteCraft across many projects on your machine.

### 2) Mark It Optional in fabric.mod.json

Do not add RemoteCraft to `depends`.

Instead, use `suggests` (or `recommends`) so your mod still loads without it:

```json
{
  "suggests": {
    "remotecraft": "*"
  }
}
```

### 3) Avoid Classloading When RemoteCraft Is Missing

Java will throw `ClassNotFoundException`/`NoClassDefFoundError` if your classes directly reference RemoteCraft API types and RemoteCraft is not installed.

Use a two-class “compat gate” pattern:

- `RemoteCraftCompat`:
  - must not import any `com.chenweikeng.remotecraft.api.v1.*`
  - checks `FabricLoader.isModLoaded("remotecraft")`
  - only then delegates to `RemoteCraftCompatImpl`
- `RemoteCraftCompatImpl`:
  - imports `RemoteCraftApi`
  - registers events and calls API methods

## Recommended Compat Pattern (Copy/Paste Template)

### RemoteCraftCompat (safe gatekeeper)

```java
import net.fabricmc.loader.api.FabricLoader;

public final class RemoteCraftCompat {
  private RemoteCraftCompat() {}

  public static boolean isAvailable() {
    return FabricLoader.getInstance().isModLoaded("remotecraft");
  }

  public static void init() {
    if (!isAvailable()) return;
    RemoteCraftCompatImpl.init();
  }

  public static void setTimedNotification(Long fireAtEpochMs, String title, String body, boolean sound) {
    if (!isAvailable()) return;
    RemoteCraftCompatImpl.setTimedNotification(fireAtEpochMs, title, body, sound);
  }

  public static void sendImmediateNotification(String title, String body, boolean sound) {
    if (!isAvailable()) return;
    RemoteCraftCompatImpl.sendImmediateNotification(title, body, sound);
  }

  public static void startHibernation(String message) {
    if (!isAvailable()) return;
    RemoteCraftCompatImpl.startHibernation(message);
  }

  public static void endHibernation() {
    if (!isAvailable()) return;
    RemoteCraftCompatImpl.endHibernation();
  }
}
```

### RemoteCraftCompatImpl (only loaded when RemoteCraft is present)

```java
import com.chenweikeng.remotecraft.api.v1.RemoteCraftApi;

final class RemoteCraftCompatImpl {
  static void init() {
    RemoteCraftApi.CONNECTION.register(remoteAddr -> {
      // e.g. prepare projection-related state in your mod
    });

    RemoteCraftApi.DISCONNECTION.register(() -> {
      // e.g. restore normal rendering/input state
    });
  }

  static void setTimedNotification(Long fireAtEpochMs, String title, String body, boolean sound) {
    RemoteCraftApi.setTimedNotification(fireAtEpochMs, title, body, sound);
  }

  static void sendImmediateNotification(String title, String body, boolean sound) {
    RemoteCraftApi.sendImmediateNotification(title, body, sound);
  }

  static void startHibernation(String message) {
    RemoteCraftApi.startHibernation(message);
  }

  static void endHibernation() {
    RemoteCraftApi.endHibernation();
  }
}
```

## How to Register Listeners

- Connected:
  - `RemoteCraftApi.CONNECTION.register(remoteAddr -> { ... })`
- Disconnected:
  - `RemoteCraftApi.DISCONNECTION.register(() -> { ... })`

Register these during your mod init (after checking RemoteCraft is loaded), typically in `onInitializeClient()`.

## Notes / Behavior Guarantees

- Timed notifications overwrite: calling `RemoteCraftApi.setTimedNotification(...)` replaces the previously set one.
- Immediate notifications are best-effort: if the phone app is not active/connected, nothing happens.
- Hibernation is independent of streaming start/stop; it is controlled by explicit start/end calls and client polling.
