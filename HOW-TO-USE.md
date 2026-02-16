# Monkeycraft v1 API — How to Use (External Mod)

This repo exposes a small public API for other **client-side Fabric mods** to integrate with Monkeycraft.

API package (versioned):

- `com.chenweikeng.monkeycraft.api.v1`

## What the API Provides

- Connection lifecycle events (phone client authenticated / disconnected)
- Notifications
  - Timed notification (overwrites the existing scheduled notification)
  - Immediate notification (only meaningful while the phone app is active/connected)
- Hibernation control (pause/resume remote streaming while keeping the WS connection)

## Files / Entry Points (Monkeycraft side)

- API: `src/main/java/com/chenweikeng/monkeycraft/api/v1/MonkeycraftApi.java`
- Events: `MonkeycraftApi.CONNECTION` and `MonkeycraftApi.DISCONNECTION`
- Notification methods:
  - `MonkeycraftApi.setTimedNotification(...)`
  - `MonkeycraftApi.cancelTimedNotification()`
  - `MonkeycraftApi.sendImmediateNotification(...)`
- Hibernation methods:
  - `MonkeycraftApi.startHibernation(message)`
  - `MonkeycraftApi.endHibernation()`
- State queries:
  - `MonkeycraftApi.isClientConnected()`
  - `MonkeycraftApi.isHibernating()`

## Using the API From Another Mod (Optional Dependency)

Goal: your mod should work even if Monkeycraft is not installed.

### 1) Compile Against Monkeycraft Locally

Use Maven Local (recommended).

Current coordinates (this repo):

- groupId: `com.chenweikeng.monkeycraft`
- artifactId: `monkeycraft`
- version: `1.0.0`

1. In the Monkeycraft repo, publish to your local Maven cache:
   - `./gradlew publishToMavenLocal`
2. In your other mod, add `mavenLocal()` and a dependency on Monkeycraft:

```gradle
repositories {
  mavenLocal()
  mavenCentral()
}

dependencies {
  modCompileOnly "com.chenweikeng.monkeycraft:monkeycraft:1.0.0"
}
```

This avoids copying jars and makes it easy to reuse Monkeycraft across many projects on your machine.

### 2) Mark It Optional in fabric.mod.json

Do not add Monkeycraft to `depends`.

Instead, use `suggests` (or `recommends`) so your mod still loads without it:

```json
{
  "suggests": {
    "monkeycraft": "*"
  }
}
```

### 3) Avoid Classloading When Monkeycraft Is Missing

Java will throw `ClassNotFoundException`/`NoClassDefFoundError` if your classes directly reference Monkeycraft API types and Monkeycraft is not installed.

Use a two-class “compat gate” pattern:

- `MonkeycraftCompat`:
  - must not import any `com.chenweikeng.monkeycraft.api.v1.*`
  - checks `FabricLoader.isModLoaded("monkeycraft")`
  - only then delegates to `MonkeycraftCompatImpl`
- `MonkeycraftCompatImpl`:
  - imports `MonkeycraftApi`
  - registers events and calls API methods

## Recommended Compat Pattern (Copy/Paste Template)

### MonkeycraftCompat (safe gatekeeper)

```java
import net.fabricmc.loader.api.FabricLoader;

public final class MonkeycraftCompat {
  private MonkeycraftCompat() {}

  public static boolean isAvailable() {
    return FabricLoader.getInstance().isModLoaded("monkeycraft");
  }

  public static void init() {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.init();
  }

  public static void setTimedNotification(Long fireAtEpochMs, String title, String body, boolean sound) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.setTimedNotification(fireAtEpochMs, title, body, sound);
  }

  public static void sendImmediateNotification(String title, String body, boolean sound) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.sendImmediateNotification(title, body, sound);
  }

  public static void startHibernation(String message) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.startHibernation(message);
  }

  public static void endHibernation() {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.endHibernation();
  }
}
```

### MonkeycraftCompatImpl (only loaded when Monkeycraft is present)

```java
import com.chenweikeng.monkeycraft.api.v1.MonkeycraftApi;

final class MonkeycraftCompatImpl {
  static void init() {
    MonkeycraftApi.CONNECTION.register(remoteAddr -> {
      // e.g. prepare projection-related state in your mod
    });

    MonkeycraftApi.DISCONNECTION.register(() -> {
      // e.g. restore normal rendering/input state
    });
  }

  static void setTimedNotification(Long fireAtEpochMs, String title, String body, boolean sound) {
    MonkeycraftApi.setTimedNotification(fireAtEpochMs, title, body, sound);
  }

  static void sendImmediateNotification(String title, String body, boolean sound) {
    MonkeycraftApi.sendImmediateNotification(title, body, sound);
  }

  static void startHibernation(String message) {
    MonkeycraftApi.startHibernation(message);
  }

  static void endHibernation() {
    MonkeycraftApi.endHibernation();
  }
}
```

## How to Register Listeners

- Connected:
  - `MonkeycraftApi.CONNECTION.register(remoteAddr -> { ... })`
- Disconnected:
  - `MonkeycraftApi.DISCONNECTION.register(() -> { ... })`

Register these during your mod init (after checking Monkeycraft is loaded), typically in `onInitializeClient()`.

## Notes / Behavior Guarantees

- Timed notifications overwrite: calling `MonkeycraftApi.setTimedNotification(...)` replaces the previously set one.
- Immediate notifications are best-effort: if the phone app is not active/connected, nothing happens.
- Hibernation is independent of streaming start/stop; it is controlled by explicit start/end calls and client polling.

## Flutter App Location (This Repo)

- The Flutter client lives at: `flutter/monkeycraft/`
