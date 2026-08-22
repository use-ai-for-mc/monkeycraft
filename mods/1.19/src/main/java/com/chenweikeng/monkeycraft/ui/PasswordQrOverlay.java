package com.chenweikeng.monkeycraft.ui;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.PoseStack;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;
import net.fabricmc.fabric.api.client.screen.v1.ScreenEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiComponent;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.texture.DynamicTexture;
import net.minecraft.resources.ResourceLocation;

public final class PasswordQrOverlay {
  private static final int QR_SIZE_PX = 128;
  private static final int MARGIN_PX = 20;
  private static final Gson GSON = new Gson();
  private static final ResourceLocation TEXTURE_ID =
      new ResourceLocation(MonkeycraftClient.MOD_ID, "password_qr");

  private static boolean registered = false;
  private static DynamicTexture texture;
  private static String lastPayload;

  private PasswordQrOverlay() {}

  public static void register() {
    if (registered) return;
    registered = true;

    HudRenderCallback.EVENT.register((poseStack, tickDelta) -> render(poseStack));

    ScreenEvents.AFTER_INIT.register(
        (client, screen, scaledWidth, scaledHeight) -> {
          if (screen instanceof TitleScreen) {
            ScreenEvents.afterRender(screen).register(PasswordQrOverlay::renderTitleScreen);
          }
        });
  }

  private static void render(PoseStack poseStack) {
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

    String payload = pairingPayload(password.trim(), handler.getCertificateSha256());
    if (payload == null || !ensureTexture(payload)) {
      return;
    }

    int screenWidth = mc.getWindow().getGuiScaledWidth();
    int screenHeight = mc.getWindow().getGuiScaledHeight();
    int x = screenWidth - QR_SIZE_PX - MARGIN_PX;
    int y = screenHeight - QR_SIZE_PX - MARGIN_PX;

    RenderSystem.setShader(GameRenderer::getPositionTexShader);
    RenderSystem.setShaderColor(1.0f, 1.0f, 1.0f, 1.0f);
    RenderSystem.setShaderTexture(0, TEXTURE_ID);
    GuiComponent.blit(poseStack, x, y, 0, 0, QR_SIZE_PX, QR_SIZE_PX, QR_SIZE_PX, QR_SIZE_PX);
  }

  /**
   * Renders the connection QR and local addresses on the title screen, so the app can be paired
   * before joining a world. Shown whenever the server is running and no client is connected.
   */
  private static void renderTitleScreen(
      Screen screen, PoseStack poseStack, int mouseX, int mouseY, float tickDelta) {
    Minecraft mc = Minecraft.getInstance();
    if (mc == null || mc.getWindow() == null) return;

    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isRunning() || handler.isClientConnected()) {
      return;
    }

    String password = ModConfig.getInstance().getPassword();
    if (password == null || password.isBlank()) {
      return;
    }
    String payload = pairingPayload(password.trim(), handler.getCertificateSha256());
    if (payload == null || !ensureTexture(payload)) {
      return;
    }

    int screenWidth = mc.getWindow().getGuiScaledWidth();
    int screenHeight = mc.getWindow().getGuiScaledHeight();
    int x = screenWidth - QR_SIZE_PX - MARGIN_PX;
    int y = screenHeight - QR_SIZE_PX - MARGIN_PX;

    java.util.List<String> ips = NetworkUtils.getLocalIpAddressesWithPort(handler.getCurrentPort());
    int lineHeight = mc.font.lineHeight + 1;
    int rightX = x + QR_SIZE_PX;
    int textY = y - 4 - lineHeight * (ips.size() + 1);
    drawRightAligned(poseStack, mc, "MonkeyCraft - scan to pair", rightX, textY);
    textY += lineHeight;
    for (String ip : ips) {
      drawRightAligned(poseStack, mc, ip, rightX, textY);
      textY += lineHeight;
    }

    RenderSystem.setShader(GameRenderer::getPositionTexShader);
    RenderSystem.setShaderColor(1.0f, 1.0f, 1.0f, 1.0f);
    RenderSystem.setShaderTexture(0, TEXTURE_ID);
    GuiComponent.blit(poseStack, x, y, 0, 0, QR_SIZE_PX, QR_SIZE_PX, QR_SIZE_PX, QR_SIZE_PX);
  }

  private static void drawRightAligned(
      PoseStack poseStack, Minecraft mc, String text, int rightX, int y) {
    int width = mc.font.width(text);
    mc.font.drawShadow(poseStack, text, rightX - width, y, 0xFFFFFFFF);
  }

  private static String pairingPayload(String password, String certificateSha256) {
    if (certificateSha256 == null || certificateSha256.isBlank()) return null;
    JsonObject payload = new JsonObject();
    payload.addProperty("v", 2);
    payload.addProperty("pw", password);
    payload.addProperty("fp", certificateSha256);
    return GSON.toJson(payload);
  }

  private static boolean ensureTexture(String payload) {
    if (texture != null && payload.equals(lastPayload)) {
      return true;
    }

    clearTexture();

    NativeImage image;
    try {
      image = generateQrNativeImage(payload, QR_SIZE_PX);
    } catch (Exception e) {
      MonkeycraftClient.LOGGER.warn("Failed to generate password QR", e);
      return false;
    }

    texture = new DynamicTexture(image);
    Minecraft.getInstance().getTextureManager().register(TEXTURE_ID, texture);
    lastPayload = payload;
    return true;
  }

  private static void clearTexture() {
    if (texture != null) {
      texture.close();
      texture = null;
    }
    lastPayload = null;
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
                EncodeHintType.MARGIN,
                1,
                EncodeHintType.ERROR_CORRECTION,
                ErrorCorrectionLevel.H,
                EncodeHintType.CHARACTER_SET,
                StandardCharsets.UTF_8.name()));
    if (matrix.getWidth() != size || matrix.getHeight() != size) {
      throw new WriterException("Pairing QR payload is too large");
    }

    NativeImage image = new NativeImage(size, size, true);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int color = matrix.get(x, y) ? 0xFF000000 : 0xFFFFFFFF;
        image.setPixelRGBA(x, y, color);
      }
    }
    return image;
  }
}
