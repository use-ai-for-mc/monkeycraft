package com.chenweikeng.monkeycraft.utils;

import com.chenweikeng.monkeycraft.mixin.AbstractContainerScreenAccessor;
import java.util.HashSet;
import java.util.Set;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.achievement.StatsScreen;
import net.minecraft.client.gui.screens.advancements.AdvancementsScreen;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.minecraft.client.gui.screens.options.AccessibilityOptionsScreen;
import net.minecraft.client.gui.screens.options.ChatOptionsScreen;
import net.minecraft.client.gui.screens.options.FontOptionsScreen;
import net.minecraft.client.gui.screens.options.LanguageSelectScreen;
import net.minecraft.client.gui.screens.options.OnlineOptionsScreen;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import net.minecraft.client.gui.screens.options.SkinCustomizationScreen;
import net.minecraft.client.gui.screens.options.SoundOptionsScreen;
import net.minecraft.client.gui.screens.options.VideoSettingsScreen;
import net.minecraft.client.gui.screens.options.controls.ControlsScreen;
import net.minecraft.client.gui.screens.packs.PackSelectionScreen;
import net.minecraft.client.gui.screens.social.SocialInteractionsScreen;
import net.minecraft.client.gui.screens.telemetry.TelemetryInfoScreen;

public final class ScreenHelper {

  private ScreenHelper() {}

  private static final Set<Class<? extends Screen>> WHITELISTED_SCREENS = new HashSet<>();

  static {
    WHITELISTED_SCREENS.add(PauseScreen.class);
    WHITELISTED_SCREENS.add(OptionsScreen.class);
    WHITELISTED_SCREENS.add(VideoSettingsScreen.class);
    WHITELISTED_SCREENS.add(ControlsScreen.class);
    WHITELISTED_SCREENS.add(LanguageSelectScreen.class);
    WHITELISTED_SCREENS.add(ChatOptionsScreen.class);
    WHITELISTED_SCREENS.add(SoundOptionsScreen.class);
    WHITELISTED_SCREENS.add(AccessibilityOptionsScreen.class);
    WHITELISTED_SCREENS.add(SkinCustomizationScreen.class);
    WHITELISTED_SCREENS.add(OnlineOptionsScreen.class);
    WHITELISTED_SCREENS.add(FontOptionsScreen.class);
    WHITELISTED_SCREENS.add(PackSelectionScreen.class);
    WHITELISTED_SCREENS.add(TelemetryInfoScreen.class);
    WHITELISTED_SCREENS.add(AdvancementsScreen.class);
    WHITELISTED_SCREENS.add(StatsScreen.class);
    WHITELISTED_SCREENS.add(SocialInteractionsScreen.class);
  }

  public static boolean shouldKeepScreen(Screen screen) {
    if (screen == null) return false;
    if (screen instanceof ChatScreen) return false;
    if (screen instanceof AbstractContainerScreen<?>) return true;
    return WHITELISTED_SCREENS.contains(screen.getClass());
  }

  public static boolean hasSpecialCropping(Screen screen) {
    if (screen == null) return false;
    return screen instanceof AbstractContainerScreen<?> || isWhitelistedButtonScreen(screen);
  }

  public static boolean isWhitelistedButtonScreen(Screen screen) {
    return screen != null && WHITELISTED_SCREENS.contains(screen.getClass());
  }

  public static int[] getCropBounds(
      Screen screen,
      int imageWidth,
      int imageHeight,
      int targetWidth,
      int targetHeight,
      double scaleFactor) {
    if (screen == null) {
      return null;
    }

    int padding;
    int guiCenterX, guiCenterY, guiWidth, guiHeight;

    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
      AbstractContainerScreenAccessor accessor = (AbstractContainerScreenAccessor) containerScreen;
      guiCenterX = accessor.monkeycraft$getLeftPos() + accessor.monkeycraft$getImageWidth() / 2;
      guiCenterY = accessor.monkeycraft$getTopPos() + accessor.monkeycraft$getImageHeight() / 2;
      guiWidth = accessor.monkeycraft$getImageWidth();
      guiHeight = accessor.monkeycraft$getImageHeight();
      padding = 16;
    } else if (isWhitelistedButtonScreen(screen)) {
      guiCenterX = screen.width / 2;
      guiCenterY = screen.height / 2;
      guiWidth = screen.width;
      guiHeight = screen.height;
      padding = 8;
    } else {
      return null;
    }

    int paddedWidth = (guiWidth + padding * 2);
    int paddedHeight = (guiHeight + padding * 2);

    double scaleX = (double) paddedWidth / targetWidth;
    double scaleY = (double) paddedHeight / targetHeight;
    double scale = Math.max(scaleX, scaleY);

    int cropWidth = (int) Math.ceil(targetWidth * scale * scaleFactor);
    int cropHeight = (int) Math.ceil(targetHeight * scale * scaleFactor);

    int cropX = (int) ((guiCenterX - cropWidth / scaleFactor / 2) * scaleFactor);
    int cropY = (int) ((guiCenterY - cropHeight / scaleFactor / 2) * scaleFactor);

    cropX = Math.max(0, cropX);
    cropY = Math.max(0, cropY);
    if (cropX + cropWidth > imageWidth) {
      cropWidth = imageWidth - cropX;
    }
    if (cropY + cropHeight > imageHeight) {
      cropHeight = imageHeight - cropY;
    }

    return new int[] {cropX, cropY, cropWidth, cropHeight};
  }

  public static int[] getClickableBounds(Screen screen, int padding) {
    if (screen == null) {
      return null;
    }

    int x, y, width, height;

    if (screen instanceof AbstractContainerScreen<?> containerScreen) {
      AbstractContainerScreenAccessor accessor = (AbstractContainerScreenAccessor) containerScreen;
      x = accessor.monkeycraft$getLeftPos();
      y = accessor.monkeycraft$getTopPos();
      width = accessor.monkeycraft$getImageWidth();
      height = accessor.monkeycraft$getImageHeight();
    } else if (isWhitelistedButtonScreen(screen)) {
      x = 0;
      y = 0;
      width = screen.width;
      height = screen.height;
    } else {
      return null;
    }

    int cropX = Math.max(0, x - padding);
    int cropY = Math.max(0, y - padding);
    int cropWidth = Math.min(screen.width - cropX, width + 2 * padding);
    int cropHeight = Math.min(screen.height - cropY, height + 2 * padding);

    return new int[] {cropX, cropY, cropWidth, cropHeight};
  }
}
