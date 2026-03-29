package com.chenweikeng.monkeycraft.ui;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import com.mojang.blaze3d.platform.NativeImage;
import java.util.Map;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.hud.VanillaHudElements;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.renderer.texture.DynamicTexture;
import net.minecraft.resources.Identifier;

public final class PasswordQrOverlay {
  private static final int QR_SIZE_PX = 64;
  private static final int MARGIN_PX = 20;
  private static final Identifier TEXTURE_ID =
      Identifier.fromNamespaceAndPath(MonkeycraftClient.MOD_ID, "password_qr");

  private static boolean registered = false;
  private static DynamicTexture texture;
  private static String lastPassword;

  private PasswordQrOverlay() {}

  public static void register() {
    if (registered) return;
    registered = true;

    Identifier beforeChatId =
        Identifier.fromNamespaceAndPath(MonkeycraftClient.MOD_ID, "before_chat");
    if (beforeChatId != null) {
      HudElementRegistry.attachElementBefore(
          VanillaHudElements.CHAT, beforeChatId, PasswordQrOverlay::render);
    }
  }

  private static void render(GuiGraphicsExtractor graphics, DeltaTracker deltaTracker) {
    Minecraft mc = Minecraft.getInstance();
    if (mc == null || mc.getWindow() == null) return;

    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isQrVisible()) {
      return;
    }

    String password = ModConfig.getInstance().getPassword();
    if (password == null || password.isBlank()) {
      return;
    }

    if (!ensureTexture(password.trim())) {
      return;
    }

    int screenWidth = mc.getWindow().getGuiScaledWidth();
    int screenHeight = mc.getWindow().getGuiScaledHeight();
    int x = screenWidth - QR_SIZE_PX - MARGIN_PX;
    int y = screenHeight - QR_SIZE_PX - MARGIN_PX;
    graphics.blit(TEXTURE_ID, x, y, x + QR_SIZE_PX, y + QR_SIZE_PX, 0f, 1.0f, 0f, 1.0f);
  }

  private static boolean ensureTexture(String password) {
    if (texture != null && password.equals(lastPassword)) {
      return true;
    }

    clearTexture();

    NativeImage image;
    try {
      image = generateQrNativeImage(password, QR_SIZE_PX);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Failed to generate password QR", e);
      return false;
    }

    texture = new DynamicTexture(TEXTURE_ID::toString, image);
    Minecraft.getInstance().getTextureManager().register(TEXTURE_ID, texture);
    lastPassword = password;
    return true;
  }

  private static void clearTexture() {
    if (texture != null) {
      texture.close();
      texture = null;
    }
    lastPassword = null;
  }

  private static NativeImage generateQrNativeImage(String data, int size) throws WriterException {
    QRCodeWriter writer = new QRCodeWriter();
    BitMatrix matrix =
        writer.encode(
            data,
            BarcodeFormat.QR_CODE,
            size,
            size,
            Map.of(
                EncodeHintType.MARGIN, 1, EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.H));

    NativeImage image = new NativeImage(size, size, true);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int color = matrix.get(x, y) ? 0xFF000000 : 0xFFFFFFFF;
        image.setPixel(x, y, color);
      }
    }
    return image;
  }
}
