# Minecraft Screens Coverage (1.21.11)

This document describes how MonkeyCraft handles Minecraft screens.

## Summary

| Screen Type | Handling |
|-------------|----------|
| `ChatScreen` | Blocked (3-second grace period after "/" key) |
| All other screens | Allowed with appropriate cropping |

---

## ChatScreen Handling

`ChatScreen` is the **only blocked screen** because chat functionality is handled separately in the Flutter app.

A 3-second grace period allows `ChatScreen` to stay open when the player presses "/" locally (for command input).

---

## Dimension Handling

MonkeyCrop captures screen content with appropriate cropping based on screen type:

### Fixed-Dimension Screens (Crop to GUI bounds)

These screens have known dimensions and are cropped tightly around the GUI:

| Screen Type | Dimensions | Notes |
|-------------|------------|-------|
| `AbstractContainerScreen` subclasses | Variable (via `imageWidth`/`imageHeight`) | Chest, furnace, anvil, inventory, etc. |
| `BookViewScreen` | 192x192 | Written book viewer |
| `BookEditScreen` | 192x192 | Writable book editor |
| `BookSignScreen` | 192x192 | Book signing |

### Full-Screen Screens (Letterboxing)

All other screens use full screen dimensions with letterboxing to maintain aspect ratio:

- `PauseScreen`, `OptionsScreen`, and all settings sub-screens
- `AdvancementsScreen`, `StatsScreen`, `SocialInteractionsScreen`
- `AbstractReportScreen` and subclasses
- `AbstractSignEditScreen` and subclasses
- `AbstractCommandBlockEditScreen` and subclasses
- `DeathScreen`, `WinScreen`, `InBedChatScreen`
- `StructureBlockEditScreen`, `JigsawBlockEditScreen`, etc.
- All other `Screen` subclasses

---

## Excluded Screens

The following screen categories are **not applicable** to in-game use:

- World selection/creation screens
- Multiplayer server connection screens
- Realms screens
- Title screen and main menu

These are never shown during active gameplay.

---

## Implementation Notes

1. **Simplified Whitelist**: Only `ChatScreen` is blocked. All other screens are allowed.

2. **Special Cropping**: 
   - `AbstractContainerScreen`: Uses accessor mixin to get `leftPos`, `topPos`, `imageWidth`, `imageHeight`
   - Book screens: Fixed 192x192 dimensions
   - All others: Full screen with letterboxing

3. **Letterboxing**: Full-screen overlays use `ImageUtils.resizeWithLetterbox()` to maintain aspect ratio.

4. **Grace Period**: When the player presses "/" locally, a 3-second grace period starts via `ScreenHelper.startChatGracePeriod()`.
