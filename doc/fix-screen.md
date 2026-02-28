# Screen Click Coordinate Mapping

This document describes the algorithms for mapping touch events on the Flutter client to Minecraft screen coordinates.

---

## Overview

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Flutter Touch  │  ───►   │  Normalized     │  ───►   │  Minecraft      │
│  (screen pixel) │         │  (0.0 - 1.0)    │         │  Screen Coord   │
└─────────────────┘         └─────────────────┘         └─────────────────┘
        │                           │                           │
   videoDisplayRect            protocol msg              getClickableBounds
```

---

## 1. Video Capture Cropping (Java Server)

**File:** `ScreenHelper.getCropBounds()` + `MonkeycraftClient.java`

**Purpose:** Crop the full Minecraft framebuffer to show only the GUI area.

### Algorithm for AbstractContainerScreen

```
Input:
  - imageWidth, imageHeight: Full framebuffer dimensions
  - targetWidth, targetHeight: Desired stream resolution
  - scaleFactor: GUI scale (e.g., 2.0 for 200% scale)

GUI Bounds (from accessor):
  - leftPos: X position of GUI top-left
  - topPos: Y position of GUI top-left
  - imageWidth: GUI width in pixels
  - imageHeight: GUI height in pixels

Calculation:
  guiCenterX = leftPos + imageWidth/2
  guiCenterY = topPos + imageHeight/2
  padding = 16

  paddedWidth = imageWidth + 32
  paddedHeight = imageHeight + 32

  scale = max(paddedWidth/targetWidth, paddedHeight/targetHeight)

  cropWidth = ceil(targetWidth * scale * scaleFactor)
  cropHeight = ceil(targetHeight * scale * scaleFactor)

  cropX = (guiCenterX - cropWidth/scaleFactor/2) * scaleFactor
  cropY = (guiCenterY - cropHeight/scaleFactor/2) * scaleFactor

Output:
  - cropX, cropY: Top-left of crop region in framebuffer
  - cropWidth, cropHeight: Size of crop region

Final: Crop region is resized to (targetWidth, targetHeight) for streaming.
```

---

## 2. Flutter Touch to Normalized Coordinates

**File:** `stream_screen.dart` - `_ScreenTouchHandler`

**Purpose:** Convert screen touch to normalized coordinates (0.0-1.0).

```
Input:
  - globalPosition: Touch position in screen coordinates
  - videoDisplayRect: Rect where video is displayed

Calculation:
  localX = globalPosition.dx - videoDisplayRect.left
  localY = globalPosition.dy - videoDisplayRect.top

  // Bounds check
  if (localX < 0 || localX > videoDisplayRect.width) return
  if (localY < 0 || localY > videoDisplayRect.height) return

  normX = (localX / videoDisplayRect.width).clamp(0.0, 1.0)
  normY = (localY / videoDisplayRect.height).clamp(0.0, 1.0)

Output:
  - normX, normY: Normalized position (0.0 = left/top, 1.0 = right/bottom)
```

---

## 3. Clickable Bounds Calculation (Java Server)

**File:** `ScreenHelper.getClickableBounds()`

**Purpose:** Define the clickable region in Minecraft screen coordinates.

### Algorithm for AbstractContainerScreen

```
Input:
  - screen: Current Minecraft screen
  - padding: Extra space around GUI (typically 16)

GUI Bounds:
  - x = leftPos
  - y = topPos
  - width = imageWidth
  - height = imageHeight

Calculation:
  cropX = max(0, x - padding)
  cropY = max(0, y - padding)
  cropWidth = min(screen.width - cropX, width + 2*padding)
  cropHeight = min(screen.height - cropY, height + 2*padding)

Output:
  - [cropX, cropY, cropWidth, cropHeight]: Clickable region bounds
```

---

## 4. Normalized to Minecraft Screen Coordinates (Java Server)

**File:** `WebSocketServerHandler.handleScreenClick()`

**Purpose:** Convert normalized coordinates to Minecraft screen coordinates.

```
Input:
  - normX, normY: Normalized position (0.0-1.0)
  - button: 0 = left, 1 = right

Calculation:
  bounds = getCropBoundsScreenCoords(screen, targetWidth, targetHeight)
  // bounds = [cropX, cropY, cropWidth, cropHeight] in screen coordinates
  // IMPORTANT: These are the SAME bounds used for video cropping

  screenX = cropX + normX * cropWidth
  screenY = cropY + normY * cropHeight

  // Optional: Update GLFW cursor position
  framebufferX = screenX * guiScale
  framebufferY = screenY * guiScale
  glfwSetCursorPos(windowHandle, framebufferX, framebufferY)

  // Create mouse event
  mouseEvent = MouseButtonEvent(screenX, screenY, button, modifiers)

  // Handle based on whether player is carrying an item
  if (player is carrying item):
    screen.mouseReleased(mouseEvent)
  else:
    screen.mouseClicked(mouseEvent, false)

Output:
  - Click/Release event at (screenX, screenY)
```

---

## Coordinate System Summary

| Stage | Coordinate System | Origin | Range |
|-------|-------------------|--------|-------|
| Minecraft Framebuffer | Pixels | Top-left of window | 0 to framebuffer size |
| GUI Position | Screen coords | Top-left of window | 0 to screen.width/height |
| Video Crop | Framebuffer pixels | Top-left of crop | crop region size |
| Stream Video | Display pixels | Top-left of video rect | targetWidth x targetHeight |
| Normalized | Unit coords | Top-left of video | 0.0 to 1.0 |
| Click Position | Screen coords | Top-left of window | 0 to screen.width/height |

---

## Key Relationships

```
Framebuffer coords = Screen coords × GUI scale
Video pixel = Normalized × videoDisplayRect.size
Screen click = cropOrigin + Normalized × cropSize
```

**Important:** `cropOrigin` and `cropSize` are the SAME values used for video cropping (`getCropBoundsScreenCoords`), ensuring click coordinates align with what the user sees.

---

## Potential Issues

### 1. Resize Transformation

Video is cropped then **resized** to target dimensions. The normalized coordinates assume the video shows the crop region exactly, but scaling artifacts may cause slight misalignment.

---

## Future Improvements

1. **Aspect ratio handling in Flutter:** When video is letterboxed on the client side, ensure touch coordinates account for black bars.

2. **Debug overlay:** Add visual feedback showing where clicks land on the server side.
