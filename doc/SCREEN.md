# Screen Projection Feature Design

This document outlines the design for projecting mouse-focused screens (inventory, containers, crafting tables, etc.) separately from normal gameplay on the mobile app.

## Current Implementation Status

### Completed (Phase 1)
- ✅ Server-side screen detection via polling `Minecraft.screen`
- ✅ `SCREEN_STATE` message sent when screen opens/closes
- ✅ Video crop to GUI bounds when screen is open
- ✅ IDR keyframe forced on screen state change
- ✅ Flutter hides joystick/jump/shift buttons when screen is open
- ✅ Simple touch handler for screen mode (sends normalized coordinates)

### Completed (Phase 2)
- ✅ `SCREEN_KEY` protocol message for key input (ESC)
- ✅ `SCREEN_CLICK` protocol message for mouse clicks with left/right button
- ✅ `SCREEN_MODIFIER` protocol message for shift modifier state
- ✅ Draggable `_ScreenControlToggle` widget (gear icon)
- ✅ `_ScreenControlPalette` with ESC, Shift toggle, L/R click mode buttons
- ✅ Screen tap sends click with current button mode and shift modifier

### Pending
- ⬜ Handle drag for item distribution
- ⬜ Handle keyboard input (search, rename)
- ⬜ Send screen type information to client
- ⬜ Handle scroll gestures

## Problem Statement

Currently, MonkeyCraft handles two modes:
1. **Streaming Mode** - Uses joystick for movement, look pad for camera, tap for clicking
2. **Chat Mode** - Dedicated chat interface

However, **inventory/container screens** require different handling:
- Mouse cursor position matters (which slot/button is being clicked)
- No joystick or movement controls needed
- Direct touch-to-coordinate mapping required
- Right-click equivalent for item interactions (drag, split stacks)

## Detection: Screen Open vs Normal Gameplay

### Server-Side Detection (Java Mod)

```java
// In Minecraft.getInstance()
Minecraft mc = Minecraft.getInstance();
if (mc.screen != null) {
    // A screen is open
    if (mc.screen instanceof AbstractContainerScreen) {
        // Container screen (chest, inventory, crafting, etc.)
    }
}

// Check specific screen types
if (mc.screen instanceof InventoryScreen) { }      // Player inventory (E key)
if (mc.screen instanceof ChestScreen) { }          // Chest container
if (mc.screen instanceof CraftingScreen) { }       // Crafting table
if (mc.screen instanceof AnvilScreen) { }          // Anvil
if (mc.screen instanceof FurnaceScreen) { }        // Furnace/smoker/blast furnace
if (mc.screen instanceof MerchantScreen) { }       // Villager trading
if (mc.screen instanceof SmithingScreen) { }       // Smithing table
if (mc.screen instanceof LoomScreen) { }           // Loom
if (mc.screen instanceof GrindstoneScreen) { }    // Grindstone
if (mc.screen instanceof StonecutterScreen) { }   // Stonecutter
if (mc.screen instanceof BrewingStandScreen) { }  // Brewing stand
if (mc.screen instanceof BeaconScreen) { }         // Beacon
if (mc.screen instanceof HopperScreen) { }         // Hopper
if (mc.screen instanceof ShulkerBoxScreen) { }    // Shulker box
```

### Key Classes

| Class | Purpose | Side |
|-------|---------|------|
| `Minecraft.screen` | Current open screen (null if none) | Client |
| `Screen` | Base class for all GUIs | Client |
| `AbstractContainerScreen<T>` | Container GUIs with slots | Client |
| `ScreenHandler` / `Menu` | Container logic, slots | Both |
| `Slot` | Inventory slot definition | Both |
| `MouseHandler` | Raw mouse input | Client |

### Mixin Hook for Screen Detection

```java
@Mixin(Minecraft.class)
public class MinecraftMixin {
    @Inject(method = "setScreen", at = @At("RETURN"))
    private void onSetScreen(Screen screen, CallbackInfo ci) {
        WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
        if (handler.isClientConnected()) {
            handler.sendScreenState(screen);
        }
    }
}
```

## WebSocket Protocol Extensions

### Server → Client: Screen State

```json
{
    "type": "SCREEN_OPENED",
    "screenType": "chest",
    "screenClass": "net.minecraft.client.gui.screens.inventory.ChestScreen",
    "containerId": 1,
    "width": 176,
    "height": 166,
    "slotCount": 27,
    "playerInventorySlots": true
}
```

```json
{
    "type": "SCREEN_CLOSED"
}
```

### Client → Server: Touch Events

```json
{
    "type": "SCREEN_TOUCH",
    "normalizedX": 0.5,
    "normalizedY": 0.3,
    "action": "tap"
}
```

```json
{
    "type": "SCREEN_TOUCH",
    "normalizedX": 0.5,
    "normalizedY": 0.3,
    "action": "long_press"
}
```

```json
{
    "type": "SCREEN_TOUCH",
    "normalizedX": 0.5,
    "normalizedY": 0.3,
    "action": "drag_start"
}
```

```json
{
    "type": "SCREEN_TOUCH",
    "normalizedX": 0.6,
    "normalizedY": 0.4,
    "action": "drag_move"
}
```

```json
{
    "type": "SCREEN_TOUCH",
    "normalizedX": 0.6,
    "normalizedY": 0.4,
    "action": "drag_end"
}
```

### Client → Server: Scroll

```json
{
    "type": "SCREEN_SCROLL",
    "normalizedX": 0.5,
    "normalizedY": 0.3,
    "delta": 1.0
}
```

### Client → Server: Keyboard

```json
{
    "type": "SCREEN_KEY",
    "key": "E",
    "action": "press"
}
```

```json
{
    "type": "SCREEN_KEY",
    "key": "SHIFT",
    "action": "hold"
}
```

### Client → Server: Screen Control (Phase 2)

#### SCREEN_KEY
```json
{
    "type": "SCREEN_KEY",
    "key": "ESCAPE",
    "pressed": true
}
```
Sends key press to Minecraft screen. Currently supports ESCAPE (closes screen).

#### SCREEN_CLICK
```json
{
    "type": "SCREEN_CLICK",
    "button": 0,
    "normalizedX": 0.5,
    "normalizedY": 0.3
}
```
Clicks at position. Button: 0=left, 1=right.

#### SCREEN_MODIFIER
```json
{
    "type": "SCREEN_MODIFIER",
    "modifier": "SHIFT",
    "active": true
}
```
Sets modifier state for subsequent clicks.

## Coordinate Mapping

### Screen Layout

```
┌────────────────────────────────────┐
│                                    │
│     Minecraft Screen               │
│     (width x height)               │
│                                    │
│  ┌──────────────────────────┐      │
│  │                          │      │
│  │   GUI Background         │      │
│  │   (imageWidth x imageHeight)    │
│  │   at (leftPos, topPos)   │      │
│  │                          │      │
│  └──────────────────────────┘      │
│                                    │
└────────────────────────────────────┘
```

### Conversion Formula

```java
// Mobile sends normalized coordinates (0-1)
// Server converts to screen coordinates

int screenX = (int)(normalizedX * screen.width);
int screenY = (int)(normalizedY * screen.height);

// For container screens, get GUI-relative coordinates
int guiRelativeX = screenX - containerScreen.leftPos;
int guiRelativeY = screenY - containerScreen.topPos;

// Find slot at position
for (Slot slot : containerScreen.getMenu().slots) {
    if (guiRelativeX >= slot.x && guiRelativeX < slot.x + 16 &&
        guiRelativeY >= slot.y && guiRelativeY < slot.y + 16) {
        // Found slot
    }
}
```

### Slot Dimensions
- Slot size: 16x16 pixels
- Standard spacing: 18 pixels between slot centers
- Player inventory: 9 columns × 3 rows + hotbar (9)
- Small chest: 9 columns × 3 rows (27 slots)
- Large chest: 9 columns × 6 rows (54 slots)

## Server-Side Implementation

### New Message Handlers in WebSocketServerHandler.java

```java
private void handleScreenTouch(JsonObject json) {
    if (!json.has("normalizedX") || !json.has("normalizedY") || !json.has("action")) return;
    
    float normX = json.get("normalizedX").getAsFloat();
    float normY = json.get("normalizedY").getAsFloat();
    String action = json.get("action").getAsString();
    
    Minecraft mc = Minecraft.getInstance();
    mc.execute(() -> {
        Screen screen = mc.screen;
        if (screen == null) return;
        
        int screenX = (int)(normX * screen.width);
        int screenY = (int)(normY * screen.height);
        
        switch (action) {
            case "tap":
                screen.mouseClicked(screenX, screenY, 0);
                screen.mouseReleased(screenX, screenY, 0);
                break;
            case "long_press":
                screen.mouseClicked(screenX, screenY, 1);
                screen.mouseReleased(screenX, screenY, 1);
                break;
            // ... handle other actions
        }
    });
}

private void sendScreenState(Screen screen) {
    if (screen == null) {
        sendScreenClosed();
        return;
    }
    
    JsonObject msg = new JsonObject();
    msg.addProperty("type", "SCREEN_OPENED");
    
    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
        msg.addProperty("screenType", getScreenType(screen));
        msg.addProperty("width", screen.width);
        msg.addProperty("height", screen.height);
        msg.addProperty("guiWidth", containerScreen.imageWidth);
        msg.addProperty("guiHeight", containerScreen.imageHeight);
        msg.addProperty("slotCount", containerScreen.getMenu().slots.size());
    } else {
        // Non-container screen (pause menu, etc.)
        msg.addProperty("screenType", "other");
        msg.addProperty("width", screen.width);
        msg.addProperty("height", screen.height);
    }
    
    send(msg);
}
```

## Flutter Client Implementation

### New Screen Mode

```dart
enum ClientMode { streaming, chat, screen }
```

### Screen Touch Widget

```dart
class ScreenTouchHandler extends StatefulWidget {
  final StreamProxy proxy;
  final int screenWidth;
  final int screenHeight;
  
  @override
  State<ScreenTouchHandler> createState() => _ScreenTouchHandlerState();
}

class _ScreenTouchHandlerState extends State<ScreenTouchHandler> {
  Offset? _dragStart;
  
  void _sendTouch(double normX, double normY, String action) {
    widget.proxy.sendCommand({
      'type': 'SCREEN_TOUCH',
      'normalizedX': normX.clamp(0.0, 1.0),
      'normalizedY': normY.clamp(0.0, 1.0),
      'action': action,
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        _sendTouch(
          local.dx / box.size.width,
          local.dy / box.size.height,
          'tap',
        );
      },
      onLongPressStart: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        _sendTouch(
          local.dx / box.size.width,
          local.dy / box.size.height,
          'long_press',
        );
      },
      onPanStart: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        _dragStart = local;
        _sendTouch(
          local.dx / box.size.width,
          local.dy / box.size.height,
          'drag_start',
        );
      },
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        _sendTouch(
          local.dx / box.size.width,
          local.dy / box.size.height,
          'drag_move',
        );
      },
      onPanEnd: (details) {
        if (_dragStart != null) {
          final box = context.findRenderObject() as RenderBox;
          _sendTouch(
            _dragStart!.dx / box.size.width,
            _dragStart!.dy / box.size.height,
            'drag_end',
          );
        }
        _dragStart = null;
      },
      child: SizedBox.expand(
        child: Texture(textureId: _textureId),
      ),
    );
  }
}
```

### UI Modifications

When in screen mode:
1. **Hide** joystick, jump button, shift button, look pad
2. **Show** full-screen touch overlay for direct interaction
3. **Add** virtual keyboard button for item search/text input
4. **Add** ESC button to close screen
5. **Add** shift toggle for item transfer modifiers

### Screen Overlay Controls

```
┌────────────────────────────────────┐
│  [ESC]                    [Keyboard]│
│                                    │
│                                    │
│        Full Screen Touch           │
│        (Direct coordinate          │
│         mapping)                   │
│                                    │
│                                    │
│  [Shift]                           │
│  (Toggle modifier for              │
│   item transfer)                   │
└────────────────────────────────────┘
```

## Interactions Reference

### Slot Click Types

| Action | Mouse Button | Shift | Result |
|--------|--------------|-------|--------|
| Tap slot | Left | No | Pick up / place item |
| Long press slot | Right | No | Split stack / interact |
| Tap + drag | Left + drag | No | Distribute items |
| Shift + tap | Left | Yes | Quick move to other inventory |
| Double tap | Left x2 | No | Stack all matching items |

### Common Actions

| Screen | Action | Implementation |
|--------|--------|----------------|
| Any | Close screen | ESC key or click outside GUI |
| Chest | Move item | Tap slot |
| Chest | Quick move | Shift + tap |
| Crafting | Place recipe | Tap grid slots |
| Anvil | Rename | Keyboard input + tap output |
| Furnace | Add fuel/input | Tap slots |

## Implementation Checklist

### Java Mod
- [x] Add mixin for `setScreen()` detection
- [x] Add `SCREEN_STATE` messages
- [x] Add `handleScreenKey()` message handler
- [x] Add `handleScreenClick()` message handler
- [x] Add `handleScreenModifier()` message handler
- [x] Implement coordinate conversion
- [ ] Handle scroll operations
- [ ] Handle drag operations for item distribution

### Flutter App
- [x] Parse `SCREEN_STATE` messages
- [x] Create `_ScreenTouchHandler` widget
- [x] Create `_ScreenControlToggle` widget (draggable)
- [x] Create `_ScreenControlPalette` widget (ESC, Shift, L/R)
- [x] Add protocol methods: sendScreenKey, sendScreenClick, sendScreenModifier
- [ ] Handle scroll gestures
- [ ] Add virtual keyboard for text input
- [ ] Test coordinate mapping accuracy

## Testing Strategy

1. **Unit tests** for coordinate conversion
2. **Integration tests** with actual Minecraft screens:
   - Player inventory (E)
   - Chest (small and large)
   - Crafting table
   - Furnace
   - Anvil
   - Villager trading
3. **Edge cases**:
   - Screen resize / orientation change
   - Drag across multiple slots
   - Scroll in creative inventory search
   - Text input in anvil/search

## Future Considerations

- **Creative inventory search**: Virtual keyboard integration
- **Recipe book**: Touch-friendly recipe selection
- **Custom modded screens**: Generic handler for unknown screen types
- **Cursor visibility**: Show touch point indicator on video stream
