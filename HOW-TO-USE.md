# Monkeycraft v1 API — How to Use (External Mod)

This repo exposes a small public API for other **client-side Fabric mods** to integrate with Monkeycraft.

API package (versioned):

- `com.chenweikeng.monkeycraft.api.v1`

## What the API Provides

- Connection lifecycle events (phone client authenticated / disconnected)
- Command execution interception (custom allowlist/denylist logic)
- Chat message filtering (incoming from server, outgoing to server)
  - Inspect, modify, or block chat messages
- Notifications
  - Timed notification (overwrites the existing scheduled notification)
  - Immediate notification (only meaningful while the phone app is active/connected)
- Hibernation control (pause/resume remote streaming while keeping the WS connection)

## Files / Entry Points (Monkeycraft side)

- API: `src/main/java/com/chenweikeng/monkeycraft/api/v1/MonkeycraftApi.java`
- Events: `MonkeycraftApi.CONNECTION` and `MonkeycraftApi.DISCONNECTION`
- Command interception: `MonkeycraftApi.COMMAND_EXECUTION`
- Chat filtering:
  - `MonkeycraftApi.INCOMING_CHAT` (messages from server → phone app)
  - `MonkeycraftApi.OUTGOING_CHAT` (messages from phone app → server)
- Notification methods:
  - `MonkeycraftApi.setTimedNotification(...)`
  - `MonkeycraftApi.cancelTimedNotification()`
  - `MonkeycraftApi.sendImmediateNotification(...)`
- Hibernation methods:
  - `MonkeycraftApi.startHibernation(message)`
  - `MonkeycraftApi.setHibernationMessage(message)`
  - `MonkeycraftApi.endHibernation()`
- State queries:
  - `MonkeycraftApi.isClientConnected()`
  - `MonkeycraftApi.isHibernating()`

## Using the API From Another Mod (Optional Dependency)

Goal: your mod should work even if Monkeycraft is not installed.

### 1) Using JitPack (Remote Dependency)

Use JitPack to pull directly from GitHub releases:

```gradle
repositories {
  mavenCentral()
	maven { url = "https://jitpack.io" }
}

dependencies {
  compileOnly('com.github.weikengchen:monkeycraft:1.0.0') {
    transitive = false
  }
}
```

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

  public static void setHibernationMessage(String message) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.setHibernationMessage(message);
  }

  public static void endHibernation() {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.endHibernation();
  }

  public static void registerIncomingChatFilter(MonkeycraftChatFilter filter) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.registerIncomingChatFilter(filter);
  }

  public static void registerOutgoingChatFilter(MonkeycraftChatFilter filter) {
    if (!isAvailable()) return;
    MonkeycraftCompatImpl.registerOutgoingChatFilter(filter);
  }

  // Functional interface for chat filtering (avoids direct API type exposure)
  @FunctionalInterface
  public interface MonkeycraftChatFilter {
    ChatFilterResult onChat(String message, String senderName, String senderUuid, boolean outgoing);

    enum ChatFilterResult {
      ALLOW, MODIFY, DENY, PASS
    }
  }
}
```

### MonkeycraftCompatImpl (only loaded when Monkeycraft is present)

```java
import com.chenweikeng.monkeycraft.api.v1.ChatMessageContext;
import com.chenweikeng.monkeycraft.api.v1.ChatMessageResult;
import com.chenweikeng.monkeycraft.api.v1.CommandExecutionResult;
import com.chenweikeng.monkeycraft.api.v1.MonkeycraftApi;

final class MonkeycraftCompatImpl {
  static void init() {
    MonkeycraftApi.CONNECTION.register(remoteAddr -> {
      // e.g. prepare projection-related state in your mod
    });

    MonkeycraftApi.DISCONNECTION.register(() -> {
      // e.g. restore normal rendering/input state
    });

    MonkeycraftApi.COMMAND_EXECUTION.register(command -> {
      // Implement custom allowlist/denylist logic
      if (command.startsWith("/op ") || command.startsWith("/deop ")) {
        return CommandExecutionResult.DENY;
      }
      return CommandExecutionResult.PASS; // Fall back to Monkeycraft's config
    });

    // Example: filter incoming chat messages
    MonkeycraftApi.INCOMING_CHAT.register(context -> {
      if (context.getMessage().toLowerCase().contains("spoiler")) {
        return ChatMessageResult.DENY;
      }
      return ChatMessageResult.PASS;
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

  static void setHibernationMessage(String message) {
    MonkeycraftApi.setHibernationMessage(message);
  }

  static void endHibernation() {
    MonkeycraftApi.endHibernation();
  }

  static void registerIncomingChatFilter(MonkeycraftCompat.MonkeycraftChatFilter filter) {
    MonkeycraftApi.INCOMING_CHAT.register(context -> {
      MonkeycraftCompat.MonkeycraftChatFilter.ChatFilterResult result =
          filter.onChat(context.getMessage(), context.getSenderName(), context.getSenderUuid(), context.isOutgoing());
      return mapResult(result, context);
    });
  }

  static void registerOutgoingChatFilter(MonkeycraftCompat.MonkeycraftChatFilter filter) {
    MonkeycraftApi.OUTGOING_CHAT.register(context -> {
      MonkeycraftCompat.MonkeycraftChatFilter.ChatFilterResult result =
          filter.onChat(context.getMessage(), context.getSenderName(), context.getSenderUuid(), context.isOutgoing());
      return mapResult(result, context);
    });
  }

  private static ChatMessageResult mapResult(
      MonkeycraftCompat.MonkeycraftChatFilter.ChatFilterResult result, ChatMessageContext context) {
    switch (result) {
      case ALLOW:
        return ChatMessageResult.ALLOW;
      case MODIFY:
        return ChatMessageResult.MODIFY;
      case DENY:
        return ChatMessageResult.DENY;
      default:
        return ChatMessageResult.PASS;
    }
  }
}
```

## How to Register Listeners

- Connected:
  - `MonkeycraftApi.CONNECTION.register(remoteAddr -> { ... })`
- Disconnected:
  - `MonkeycraftApi.DISCONNECTION.register(() -> { ... })`

Register these during your mod init (after checking Monkeycraft is loaded), typically in `onInitializeClient()`.

## Command Execution Interception (Custom Allowlist/Denylist)

You can intercept commands sent from the phone app and implement custom allowlist/denylist logic.

### CommandExecutionResult Enum

- `ALLOW` - Immediately allow the command, bypassing Monkeycraft's built-in allowlist/denylist checks
- `DENY` - Immediately deny the command
- `PASS` - Continue to the next listener, or fall back to Monkeycraft's built-in allowlist/denylist

### Registration Pattern

```java
MonkeycraftApi.COMMAND_EXECUTION.register(command -> {
    // command includes the leading "/" (e.g., "/gamemode survival")
    if (command.startsWith("/op ") || command.startsWith("/deop ")) {
        return CommandExecutionResult.DENY;
    }
    if (command.equals("/home") || command.equals("/spawn")) {
        return CommandExecutionResult.ALLOW;
    }
    return CommandExecutionResult.PASS; // Let Monkeycraft's config decide
});
```

### Evaluation Order

1. All registered `COMMAND_EXECUTION` listeners are invoked in order
2. If any listener returns `ALLOW` or `DENY`, that result is used immediately
3. If all listeners return `PASS`, Monkeycraft's built-in allowlist/denylist config is applied
4. The denylist is checked first, then the allowlist, then the default behavior

## Chat Message Filtering

You can intercept and filter chat messages in both directions:
- **INCOMING_CHAT**: Messages received from the server (to be displayed on the phone app)
- **OUTGOING_CHAT**: Messages sent from the phone app (to the server)

### ChatMessageContext

| Field | Description |
|-------|-------------|
| `message` | The chat message content (modifiable via `setMessage()`) |
| `senderUuid` | UUID of the message sender |
| `senderName` | Display name of the sender |
| `outgoing` | `true` if outgoing (phone→server), `false` if incoming (server→phone) |

### ChatMessageResult Enum

- `ALLOW` - Allow the message as-is
- `MODIFY` - Allow but use the modified message (set via `context.setMessage()`)
- `DENY` - Block the message entirely
- `PASS` - Continue to next listener

### Registration Pattern

```java
// Filter incoming messages (server → phone)
MonkeycraftApi.INCOMING_CHAT.register(context -> {
    // Block messages containing certain words
    if (context.getMessage().toLowerCase().contains("spoiler")) {
        return ChatMessageResult.DENY;
    }
    // Censor/modify message content
    if (context.getMessage().contains("badword")) {
        context.setMessage(context.getMessage().replace("badword", "****"));
        return ChatMessageResult.MODIFY;
    }
    return ChatMessageResult.PASS;
});

// Filter outgoing messages (phone → server)
MonkeycraftApi.OUTGOING_CHAT.register(context -> {
    // Log outgoing messages
    System.out.println("Outgoing from " + context.getSenderName() + ": " + context.getMessage());
    // Block empty messages
    if (context.getMessage().trim().isEmpty()) {
        return ChatMessageResult.DENY;
    }
    return ChatMessageResult.PASS;
});
```

### Evaluation Order

1. All registered chat listeners are invoked in order
2. If any listener returns `ALLOW`, `MODIFY`, or `DENY`, that result is used immediately
3. If all listeners return `PASS`, the message is allowed through unchanged

## Notes / Behavior Guarantees

- Timed notifications overwrite: calling `MonkeycraftApi.setTimedNotification(...)` replaces the previously set one.
- Timed notifications are automatically cancelled when the client disconnects from the server.
- Immediate notifications are best-effort: if the phone app is not active/connected, nothing happens.
- Hibernation is independent of streaming start/stop; it is controlled by explicit start/end calls and client polling.
- `setHibernationMessage(message)` only works while hibernating; it updates the message displayed on the phone app without ending/restarting hibernation.

## Flutter App Location (This Repo)

- The Flutter client lives at: `flutter/monkeycraft/`
