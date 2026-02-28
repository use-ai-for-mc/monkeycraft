# Ghost-Skilled Player Joystick Assist

## Overview

This feature improves mobile joystick control by letting a "ghost skilled player" interpret joystick input to avoid collisions, slide along walls, and navigate curves naturally. The algorithm runs on the Minecraft mod (not Flutter) and modifies the effective movement direction before it's applied.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Flutter App                                     │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────────────┐ │
│  │ VirtualJoystick │ --> │ GameInputControl │ --> │ sendClientStatus()   │ │
│  │   (W/A/S/D)     │     │   (key events)   │     │ steerAssist: bool    │ │
│  └─────────────────┘     └──────────────────┘     └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ WebSocket (INPUT messages + CLIENT_STATUS)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Minecraft Mod                                     │
│  ┌──────────────────────┐     ┌────────────────────┐     ┌───────────────┐ │
│  │ WebSocketHandler     │ --> | SteerAssistEngine  | --> | Tick Handler  │ │
│  │ - handleInput()      │     | - evaluateClearance│     | - apply move  │ │
│  │ - steerAssist flag   │     | - scoreCandidates  │     | - auto-face   │ │
│  └──────────────────────┘     └────────────────────┘     └───────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Insight: Input Hook Location

We don't need Mixin magic. The input flow is:

1. **Flutter sends INPUT messages** (`W`, `A`, `S`, `D` key press/release) via WebSocket
2. **WebSocketServerHandler.handleInput()** applies these to Minecraft's `KeyMapping`
3. **Minecraft's input system** updates `client.player.input.getMoveVector()` automatically
4. **MonkeycraftClient tick** reads `getMoveVector()` and applies movement

The steer assist hooks at **step 4**: instead of using the raw `getMoveVector()`, we compute a modified direction that accounts for collisions.

## Algorithm

### Step 1: Capture User Intent

```java
Vec2 rawInput = client.player.input.getMoveVector();
// rawInput.x = strafe (-1 to 1), rawInput.y = forward (-1 to 1)

if (rawInput.lengthSquared() < 0.01f) {
    return; // No input, no assist
}

// Convert to world-space movement direction
float inputAngle = (float) Math.atan2(-rawInput.x, rawInput.y);
float worldYaw = client.player.getYRot() + inputAngle;
```

### Step 2: Generate Candidate Directions

Sample angles around the intended direction:

```java
float[] angleOffsets = {-30, -15, 0, 15, 30}; // degrees
List<Candidate> candidates = new ArrayList<>();

for (float offset : angleOffsets) {
    float testYaw = worldYaw + offset;
    candidates.add(new Candidate(testYaw, offset));
}
```

### Step 3: Evaluate Clearance

For each candidate, raycast/sweep forward to check how far the player can move:

```java
double checkClearance(LocalPlayer player, float yawRadians) {
    double dx = -Math.sin(yawRadians);
    double dz = Math.cos(yawRadians);
    
    AABB bb = player.getBoundingBox();
    double step = 0.25; // blocks per sample
    double maxDist = 4.0; // max look-ahead distance
    
    for (double dist = step; dist <= maxDist; dist += step) {
        // "Fat ghost": inflate box slightly to avoid scraping walls
        AABB testBox = bb.move(dx * dist, 0, dz * dist).inflate(0.1, 0, 0.1);
        
        if (!player.level().noCollision(player, testBox)) {
            return dist; // Hit wall at this distance
        }
    }
    return maxDist; // Clear for full distance
}
```

**Key API:** `Level.noCollision(Entity entity, AABB box)` returns `true` if no collision.

### Step 4: Score Candidates

```java
float scoreCandidate(Candidate c, float targetYaw, double clearance) {
    // Alignment: how close to intended direction (1.0 = perfect, 0.5 = 60° off)
    float alignment = (float) Math.cos(Math.toRadians(c.angleOffset));
    
    // Clearance: normalized (1.0 = max clear, 0.0 = blocked immediately)
    double clearanceScore = clearance / 4.0;
    
    // Weighted combination
    return alignment * 0.6f + (float) clearanceScore * 0.4f;
}
```

### Step 5: Smooth Direction Changes

Avoid sudden snapping by interpolating:

```java
float smoothFactor = 0.3f; // 0 = no change, 1 = instant
float modifiedYaw = lerp(previousYaw, bestCandidateYaw, smoothFactor);
previousYaw = modifiedYaw;
```

### Step 6: Convert to Modified Input

Convert the smoothed world yaw back to input space:

```java
float modifiedInputAngle = modifiedYaw - client.player.getYRot();
float modifiedStrafe = -Math.sin(modifiedInputAngle);
float modifiedForward = Math.cos(modifiedInputAngle);

// Use this modified vector for:
// 1. Movement (Minecraft handles via key presses)
// 2. Auto-face movement direction
```

## Integration with Auto-Face Movement

The existing auto-face feature rotates the player to face their movement direction:

```java
// Current implementation (MonkeycraftClient.java:129-144)
if (handler.isAutoFaceMovement() && !isManualLookInput()) {
    Vec2 moveVec = client.player.input.getMoveVector();
    float targetYawOffset = (float) Math.atan2(-moveVec.x, moveVec.y) * (180/PI);
    float targetYaw = client.player.getYRot() + targetYawOffset;
    // ... smooth turn toward targetYaw
}
```

**With steer assist enabled**, we use the *modified* movement direction instead:

```java
Vec2 effectiveMoveVec = handler.isSteerAssist() 
    ? handler.getModifiedMoveVector()  // From steer assist algorithm
    : client.player.input.getMoveVector();  // Raw input

if (handler.isAutoFaceMovement() && !isManualLookInput()) {
    float targetYawOffset = (float) Math.atan2(-effectiveMoveVec.x, effectiveMoveVec.y) * (180/PI);
    float targetYaw = client.player.getYRot() + targetYawOffset;
    // ... smooth turn toward targetYaw
}
```

This creates a coherent experience: the player faces where they're *actually* moving, not where the raw joystick points.

## Flutter Settings UI

### StreamSettings (stream_settings.dart)

Add new field:

```dart
class StreamSettings {
  final bool steerAssist;
  // ... existing fields
  
  static const defaults = StreamSettings(
    steerAssist: false,  // Off by default
    // ...
  );
}
```

### StreamSettingsScreen (screens/stream_settings_screen.dart)

Add toggle:

```dart
SwitchListTile(
  title: Text('Steer Assist'),
  subtitle: Text('Automatically avoid walls and obstacles'),
  value: settings.steerAssist,
  onChanged: (value) => updateSettings(settings.copyWith(steerAssist: value)),
),
```

### Protocol Sync (stream_proxy.dart)

The `sendClientStatus()` method already supports passing settings. Add:

```dart
bool sendClientStatus(ClientMode mode, {
  // ... existing params
  bool? steerAssist,
}) {
  final cmd = <String, dynamic>{...};
  if (steerAssist != null) {
    cmd['steerAssist'] = steerAssist;
  }
  return trySendCommand(cmd);
}
```

## Java Implementation

### WebSocketServerHandler.java

Add field and getter:

```java
private boolean steerAssist = false;

public boolean isSteerAssist() {
    return steerAssist;
}

public Vec2 getModifiedMoveVector() {
    return modifiedMoveVector; // Updated each tick by SteerAssistEngine
}
```

Update `handleClientStatus()`:

```java
if (json.has("steerAssist")) {
    steerAssist = json.get("steerAssist").getAsBoolean();
}
```

### New Class: SteerAssistEngine.java

```java
package com.chenweikeng.monkeycraft.server;

import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec2;
import java.util.ArrayList;
import java.util.List;

public class SteerAssistEngine {
    private static final float[] ANGLE_OFFSETS = {-30, -15, 0, 15, 30};
    private static final double STEP_SIZE = 0.25;
    private static final double MAX_DISTANCE = 4.0;
    private static final double INFLATE_AMOUNT = 0.1;
    private static final float ALIGNMENT_WEIGHT = 0.6f;
    private static final float CLEARANCE_WEIGHT = 0.4f;
    private static final float SMOOTH_FACTOR = 0.3f;
    
    private float previousYaw;
    private Vec2 modifiedVector = Vec2.ZERO;
    
    public Vec2 compute(LocalPlayer player, Vec2 rawInput) {
        if (rawInput.lengthSquared() < 0.01f) {
            modifiedVector = Vec2.ZERO;
            return modifiedVector;
        }
        
        float inputAngle = (float) Math.atan2(-rawInput.x, rawInput.y);
        float worldYaw = player.getYRot() + inputAngle;
        
        Candidate best = null;
        float bestScore = Float.NEGATIVE_INFINITY;
        
        for (float offset : ANGLE_OFFSETS) {
            float testYaw = worldYaw + offset;
            float testYawRad = (float) Math.toRadians(testYaw);
            double clearance = checkClearance(player, testYawRad);
            float score = scoreCandidate(offset, clearance);
            
            if (score > bestScore) {
                bestScore = score;
                best = new Candidate(testYaw, offset, clearance);
            }
        }
        
        if (best != null) {
            float smoothedYaw = lerp(previousYaw, best.yaw, SMOOTH_FACTOR);
            previousYaw = smoothedYaw;
            
            float modifiedInputAngle = smoothedYaw - player.getYRot();
            modifiedVector = new Vec2(
                (float) -Math.sin(modifiedInputAngle),
                (float) Math.cos(modifiedInputAngle)
            );
        }
        
        return modifiedVector;
    }
    
    private double checkClearance(LocalPlayer player, float yawRad) {
        double dx = -Math.sin(yawRad);
        double dz = Math.cos(yawRad);
        AABB bb = player.getBoundingBox();
        
        for (double dist = STEP_SIZE; dist <= MAX_DISTANCE; dist += STEP_SIZE) {
            AABB testBox = bb.move(dx * dist, 0, dz * dist)
                           .inflate(INFLATE_AMOUNT, 0, INFLATE_AMOUNT);
            if (!player.level().noCollision(player, testBox)) {
                return dist;
            }
        }
        return MAX_DISTANCE;
    }
    
    private float scoreCandidate(float angleOffset, double clearance) {
        float alignment = (float) Math.cos(Math.toRadians(angleOffset));
        float clearanceScore = (float) (clearance / MAX_DISTANCE);
        return alignment * ALIGNMENT_WEIGHT + clearanceScore * CLEARANCE_WEIGHT;
    }
    
    private float lerp(float a, float b, float t) {
        return a + (b - a) * t;
    }
    
    private static class Candidate {
        final float yaw;
        final float angleOffset;
        final double clearance;
        
        Candidate(float yaw, float angleOffset, double clearance) {
            this.yaw = yaw;
            this.angleOffset = angleOffset;
            this.clearance = clearance;
        }
    }
}
```

### MonkeycraftClient.java Integration

```java
private final SteerAssistEngine steerAssistEngine = new SteerAssistEngine();

// In tick handler:
if (handler.isStreaming() && client.player != null) {
    Vec2 effectiveMoveVec;
    
    if (handler.isSteerAssist()) {
        Vec2 rawInput = client.player.input.getMoveVector();
        effectiveMoveVec = steerAssistEngine.compute(client.player, rawInput);
        handler.setModifiedMoveVector(effectiveMoveVec);
    } else {
        effectiveMoveVec = client.player.input.getMoveVector();
    }
    
    // Auto-face movement uses effectiveMoveVec
    if (handler.isAutoFaceMovement() && !isManualLookInput()) {
        if (effectiveMoveVec.lengthSquared() > 0.01f) {
            float targetYawOffset = (float) (Math.atan2(-effectiveMoveVec.x, effectiveMoveVec.y) * (180.0 / Math.PI));
            // ... apply rotation
        }
    }
}
```

## Optional Enhancements

1. **Fat Ghost Factor** - Make the "ghost" wider (1.1-1.2x player width) to avoid scraping
2. **Forward Bias** - Slightly favor forward movement when forward is partially blocked
3. **Latency Compensation** - Start collision check from predicted position
4. **Adaptive Smoothing** - Faster response when collision is imminent

## Testing Checklist

- [ ] Narrow corridors (1-block wide)
- [ ] Diagonal walls (45° corners)
- [ ] Curved paths (village roads)
- [ ] Long straight hallways (smoothing feels natural)
- [ ] Doorways (don't get stuck on door frames)
- [ ] Combined with auto-face movement
- [ ] Toggle on/off mid-movement
- [ ] Performance (should be < 0.5ms per tick)

## Performance Notes

- 5 candidate directions × 16 steps × 0.25 blocks = 80 collision checks per tick
- `Level.noCollision()` is fast (uses spatial partitioning)
- Total expected overhead: < 0.5ms per tick (negligible)
