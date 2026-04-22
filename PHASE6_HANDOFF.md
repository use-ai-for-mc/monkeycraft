# Fabric 1.19.2 back-port — Phase 6 handoff

Branch: `claude/check-fabric-1.19-Rnn82`
Target: back-port MonkeyCraft from Minecraft 1.21.11 (Fabric) to 1.19.2 (Fabric).
Scaffold lives at `mods/1.19.2/` alongside the existing `mods/1.21.11/` and `mods/26.1/` trees.

## What's done (Phases 0–5)

| Phase | Commit | Scope |
|---|---|---|
| 0 | `c88c5d1` | Copy `mods/1.21.11/` → `mods/1.19.2/`; update `gradle.properties`, `build.gradle`, `fabric.mod.json`, `gradle-wrapper.properties`, `monkeycraft.mixins.json` |
| 1 | `014c765` | `ImageUtils` — `NativeImage.format()` → `getFormat()`, `setPixel` → `setPixelRGBA` |
| 2 | `e317fdc` | `MonkeycraftClient`, `CameraController`, `MouseHandlerAccessor` — enum-form `ClickEvent`/`HoverEvent`, `Input.leftImpulse`/`forwardImpulse`, add `isRightPressed` accessor |
| 3 | `e1f3472` | `ChatSegment`, `InputHandler`, `ScreenInteractionHandler` — enum-form events, `Inventory.selected` field, raw-primitive `Screen.keyPressed`/`mouseClicked`, `Window.getWindow()` handle getter |
| 4 | `2ce2d12` | `PasswordQrOverlay`, `FrameCaptureManager` — `HudRenderCallback` + `PoseStack` + `GuiComponent.blit`, `ResourceLocation` (not `Identifier`), sync `Screenshot.takeScreenshot` |
| 5 | `02c98d7` | Mixins — delete `GameRendererAccessor`/`GuiRendererAccessor`/`NativeImageAccessor`, rewrite `KeyboardMixin`/`ChatListenerMixin`, direct `NativeImage.getPixelRGBA` call in `H264Streamer` |

## Toolchain pinned in Phase 0

- `minecraft_version=1.19.2`, Mojmap mappings, Java 17
- `loader_version=0.14.22`, `loom_version=1.1-SNAPSHOT`
- `fabric_api_version=0.76.1+1.19.2`
- `cloth_config_version=8.3.115`, `modmenu_version=4.2.0-beta.2`
- Gradle wrapper 7.5.1, `compatibilityLevel: JAVA_17` in mixins.json

## Run Phase 6

```bash
git checkout claude/check-fabric-1.19-Rnn82
cd mods/1.19.2
./gradlew --refresh-dependencies build
```

Then `./gradlew runClient` to smoke-test.

## Likely breakages (in rough descending probability)

All flagged during Phases 2–5 but unverifiable without the Loom-imported 1.19.2 Mojmap jar.

1. **`com.github.weikengchen:monkeycraft-api:2026-02-27` is incompatible.** If its public surface exposes 1.21+ record-style `ClickEvent.OpenUrl(URI)` / `HoverEvent.ShowText(Component)`, `MonkeycraftApiRegistration` and the `*Context` classes won't compile here.
   - Source: `build.gradle:54-57`
   - Fix: rebuild the API artifact against 1.19.2 APIs, or stub the API-related code paths.

2. **`ChatListener` method name/param order guess.** Assumed `handleChatMessage(PlayerChatMessage, ChatSender, ChatType.Bound)`. Mixin throws `InvalidInjectionException` at apply-time if wrong.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/mixin/ChatListenerMixin.java:17`
   - Fix: `./gradlew genSources` and decompile `net/minecraft/client/multiplayer/chat/ChatListener.java` from the 1.19.2 jar. Candidates: name might be `handlePlayerChatMessage`; param order might be `(ChatSender, PlayerChatMessage, ChatType.Bound)`.

3. **`KeyMapping.matches(int, int)` may be `matchesKey(int, int)` in 1.19.2 Mojmap.** Compile error `cannot find symbol`.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/mixin/KeyboardMixin.java:27`
   - Fix: rename to `matchesKey`.

4. **`CommandBuildContext` may not exist in 1.19.2 Mojmap.** The class was added in 1.19 per my research, but if the Fabric API V2 callback actually uses `CommandRegistryAccess`, the registrar param is wrong.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/MonkeycraftClient.java:149`
   - Fix: change the param type to `net.minecraft.commands.CommandRegistryAccess`.

5. **`Window.getWindow()` returning the `long` GLFW handle.** Expected in 1.19.2 Mojmap, but some builds expose `handle()`. Surfaces as compile error.
   - Sources: `mixin/KeyboardMixin.java:22`, `server/handler/ScreenInteractionHandler.java:98`, `:149`.
   - Fix: try `handle()`.

6. **`net.minecraft.network.chat.ChatSender` may live elsewhere.** Alternate locations: `net.minecraft.client.multiplayer.chat.ChatSender`, or nested as `ChatType.SenderInfo`.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/mixin/ChatListenerMixin.java:6`

7. **`GuiComponent.blit` parameter order oddity.** 1.19.2 signature is `(PoseStack, x, y, u, v, w, h, textureHeight, textureWidth)` — height before width. QR is 64×64 square so order doesn't matter here.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/ui/PasswordQrOverlay.java:71`

8. **`HudRenderCallback` callback signature.** Assumed `(PoseStack, float tickDelta)`. If Fabric API 0.76.1 uses a different shape, the lambda won't type-check.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/ui/PasswordQrOverlay.java:39`

9. **Color inversion on the video stream.** Runtime-only, not a compile failure. `getPixelRGBA` returns RGBA-LE (byte 0 = R); existing shifts in `convertNativeImageToYuv` expect that layout. If the phone shows red and blue swapped, flip `r` and `b`.
   - Source: `mods/1.19.2/src/main/java/com/chenweikeng/monkeycraft/server/H264Streamer.java:194-197`

10. **Gradle wrapper jar mismatch.** The bootstrap jar is from the original Gradle-9 copy. If `./gradlew` fails to bootstrap 7.5.1, regenerate with the system Gradle: `gradle wrapper --gradle-version 7.5.1`.

## Smoke-test checklist

Once `./gradlew runClient` launches:

- [ ] Client reaches main menu without mixin apply errors in the log.
- [ ] Create world → `/monkey start` → QR overlay appears bottom-right (validates `PasswordQrOverlay` rewrite).
- [ ] `/monkey config` opens ModMenu-style screen (validates Cloth 8.x + ModMenu 4.x).
- [ ] Hotbar slot select from phone (validates `inventory.selected = slot`).
- [ ] Phone video stream shows correct colors — if red/blue swapped, flip in `H264Streamer` (item 9).
- [ ] Incoming chat on a multiplayer server reaches the phone with sender name + UUID (validates `ChatListenerMixin`, item 2).
- [ ] Outgoing chat from phone appears in game (validates `ChatHandler.sendChat`).
- [ ] Inventory clicks, shift-clicks, carry-item — exercises `ScreenInteractionHandler` raw-primitive calls.
- [ ] Right-press-hold mouse for ~8 ticks releases cursor (validates the `isRightPressed` accessor added in Phase 2).
- [ ] `/monkey` chat help prints with clickable/hoverable styling (validates `ChatSegment` rewrite).

## Notes

- `mods/26.1/` and `mods/1.21.11/` must remain untouched.
- All phase commits have detailed messages explaining what changed and why.
- If a compile error maps cleanly to one of the items above, apply the suggested fix directly. If it's something new, decompile-and-inspect is almost always faster than guessing.
