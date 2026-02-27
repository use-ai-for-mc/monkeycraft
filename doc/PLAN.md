# Screen Control Palette Implementation Plan

## Overview

Add a draggable floating control panel when screen mode is active (inventory, container screens).

---

## Features

| Feature | Behavior |
|---------|----------|
| **Toggle Button** | Draggable floating button, default top-right, icon-based |
| **ESC Button** | Closes palette, sends ESC key to Minecraft |
| **Shift Toggle** | Tap to toggle on/off, visual indicator for state |
| **L/R Click Buttons** | Separate buttons, visual indicator for active mode |
| **Tap Handler** | Sends click with current L/R mode and shift modifier |

---

## Visual Design

### Collapsed State
```
┌────────────────────────────────────┐
│ [X][⚙][≡][↻][💬]              [⚙] │  ← Toggle button (draggable)
│                                    │
│    ┌─────────────────────────┐    │
│    │                         │    │
│    │   Inventory GUI         │    │
│    │   (video area)          │    │
│    │                         │    │
│    └─────────────────────────┘    │
│                                    │
└────────────────────────────────────┘
```

### Expanded State
```
┌────────────────────────────────────┐
│ [X][⚙][≡][↻][💬]        ┌───────┐ │
│                         │  ESC  │ │
│    ┌─────────────────┐  ├───────┤ │
│    │                 │  │ ■⇧   │ │  ← Shift ON (filled)
│    │  Inventory GUI  │  ├───────┤ │
│    │  (video area)   │  │●L●│R │ │  ← Left active (border)
│    │                 │  └───────┘ │
│    └─────────────────┘            │
│                                    │
└────────────────────────────────────┘
```

---

## Flutter Implementation

### 1. New Widget: `_ScreenControlToggle`
**File**: `widgets/screen_control_toggle.dart`

**Features**:
- Floating button, draggable anywhere on screen
- Default position: top-right (below existing top bar)
- Icon: settings/gear icon when collapsed
- Tap: toggle expanded/collapsed
- Drag: reposition on screen
- Semi-transparent background with rounded corners

**State**:
```dart
class _ScreenControlToggleState extends State<_ScreenControlToggle> {
  Offset _position = const Offset(double.infinity, double.infinity);
  bool _dragging = false;
  
  Offset get _defaultPosition => Offset(
    screenWidth - 56 - safeAreaRight - 20,
    safeAreaTop + 80,
  );
}
```

### 2. New Widget: `_ScreenControlPalette`
**File**: `widgets/screen_control_palette.dart`

**Layout**:
```
┌─────────────┐
│    ESC      │  ← TextButton, red/danger color
├─────────────┤
│   ■⇧ Shift  │  ← Toggle, accent color when ON
├─────────────┤
│  [●L●] [R]  │  ← Row, border on active button
└─────────────┘
```

**Styling**:
- Background: `Colors.black.withOpacity(0.7)`
- Border radius: 12px
- Padding: 8px
- Button spacing: 4px

### 3. Enhanced `_ScreenTouchHandler`
**File**: `screens/stream_screen.dart`

**Changes**:
- Accept `clickMode` and `shiftActive` parameters
- Send `SCREEN_CLICK` with button number (0=left, 1=right)
- Include shift modifier state

### 4. State Changes in `stream_screen.dart`

```dart
// New state variables
bool _screenControlsExpanded = false;
Offset _screenControlPosition = const Offset(double.infinity, double.infinity);
enum _ClickMode { left, right }
_ClickMode _clickMode = _ClickMode.left;
bool _shiftActive = false;
```

---

## Protocol

### Client → Server Messages

#### SCREEN_KEY
```json
{
  "type": "SCREEN_KEY",
  "key": "ESCAPE",
  "pressed": true
}
```
Send key press/release to Minecraft screen.

#### SCREEN_CLICK
```json
{
  "type": "SCREEN_CLICK",
  "button": 0,
  "normalizedX": 0.5,
  "normalizedY": 0.3
}
```
Click at position with specified button (0=left, 1=right).

#### SCREEN_MODIFIER
```json
{
  "type": "SCREEN_MODIFIER",
  "modifier": "SHIFT",
  "active": true
}
```
Set modifier state for subsequent clicks.

---

## Java Implementation

### WebSocketServerHandler.java

#### New Message Handlers

```java
// Add to onMessage() switch:
} else if ("SCREEN_KEY".equals(type)) {
    handleScreenKey(json);
} else if ("SCREEN_CLICK".equals(type)) {
    handleScreenClick(json);
} else if ("SCREEN_MODIFIER".equals(type)) {
    handleScreenModifier(json);
}
```

#### handleScreenKey
```java
private void handleScreenKey(JsonObject json) {
    if (!json.has("key") || !json.has("pressed")) return;
    String key = json.get("key").getAsString();
    boolean pressed = json.get("pressed").getAsBoolean();
    
    Minecraft mc = Minecraft.getInstance();
    mc.execute(() -> {
        Screen screen = mc.screen;
        if (screen == null) return;
        
        int keyCode = switch (key) {
            case "ESCAPE" -> 256;   // GLFW_KEY_ESCAPE
            default -> -1;
        };
        
        if (keyCode >= 0) {
            if (pressed) {
                screen.keyPressed(keyCode, 0, 0);
            } else {
                screen.keyReleased(keyCode, 0, 0);
            }
        }
    });
}
```

#### handleScreenClick
```java
private void handleScreenClick(JsonObject json) {
    if (!json.has("button") || !json.has("normalizedX") || !json.has("normalizedY")) return;
    
    int button = json.get("button").getAsInt();
    double normX = json.get("normalizedX").getAsDouble();
    double normY = json.get("normalizedY").getAsDouble();
    
    Minecraft mc = Minecraft.getInstance();
    mc.execute(() -> {
        Screen screen = mc.screen;
        if (screen == null) return;
        
        int screenX = (int)(normX * screen.width);
        int screenY = (int)(normY * screen.height);
        
        screen.mouseClicked(screenX, screenY, button);
        screen.mouseReleased(screenX, screenY, button);
    });
}
```

#### handleScreenModifier
```java
private boolean screenShiftActive = false;

private void handleScreenModifier(JsonObject json) {
    if (!json.has("modifier") || !json.has("active")) return;
    String modifier = json.get("modifier").getAsString();
    boolean active = json.get("active").getAsBoolean();
    
    if ("SHIFT".equals(modifier)) {
        screenShiftActive = active;
    }
}
```

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `flutter/.../widgets/screen_control_toggle.dart` | **New** | Draggable toggle button widget |
| `flutter/.../screens/stream_screen.dart` | **Modify** | Add state, integrate new widgets |
| `flutter/.../services/stream_proxy.dart` | **Modify** | Add sendScreenKey(), sendScreenClick(), sendScreenModifier() |
| `WebSocketServerHandler.java` | **Modify** | Add SCREEN_KEY, SCREEN_CLICK, SCREEN_MODIFIER handlers |
| `doc/SCREEN.md` | **Update** | Document implemented features |

---

## Button Behavior Details

### ESC Button
1. User taps ESC
2. Palette collapses immediately
3. Send `SCREEN_KEY { key: "ESCAPE", pressed: true }`
4. Server calls `screen.keyPressed(256, 0, 0)`
5. Minecraft closes screen
6. Server sends `SCREEN_STATE { isOpen: false }`
7. Flutter returns to gameplay mode

### Shift Toggle
1. User taps Shift
2. Toggle state flips
3. Visual updates (filled = ON, outline = OFF)
4. Send `SCREEN_MODIFIER { modifier: "SHIFT", active: true/false }`
5. Server stores modifier state for future clicks

### L/R Click Mode
1. User taps L or R button
2. Click mode updates
3. Visual updates (border on active button)
4. No server message needed (client-side state only)
5. Subsequent taps use selected button

### Screen Tap
1. User taps video area
2. Get normalized coordinates
3. Send `SCREEN_CLICK { button: currentClickMode, normalizedX, normalizedY }`
4. Server converts to screen coordinates
5. Server calls `screen.mouseClicked()` and `screen.mouseReleased()`

---

## Styling Constants

```dart
// Colors
const kPaletteBackground = Color(0xB3000000);  // 70% black
const kButtonActive = Color(0xFF2196F3);       // Blue accent
const kButtonInactive = Color(0xFF757575);     // Grey
const kEscButtonColor = Color(0xFFE53935);     // Red

// Sizes
const kToggleSize = 48.0;
const kButtonHeight = 44.0;
const kButtonMinWidth = 60.0;
const kPalettePadding = 8.0;
const kPaletteBorderRadius = 12.0;
```

---

## Implementation Order

1. Add Java message handlers (SCREEN_KEY, SCREEN_CLICK, SCREEN_MODIFIER)
2. Add Flutter protocol methods in stream_proxy.dart
3. Create _ScreenControlToggle widget
4. Create _ScreenControlPalette buttons
5. Integrate into stream_screen.dart
6. Update SCREEN.md documentation
7. Test with inventory, chest, crafting table screens
