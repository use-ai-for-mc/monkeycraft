package com.chenweikeng.monkeycraft.ui;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.chenweikeng.monkeycraft.utils.TailnetHttps;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.function.Consumer;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.FormattedText;

public class SetupWizardScreen extends Screen {
  private static final int HEADER_HEIGHT = 40;
  private static final int FOOTER_HEIGHT = 40;
  private static final int PADDING = 20;
  private static final int CONTROL_HEIGHT = 20;
  private static final int BUTTON_WIDTH = 80;
  private static final long FLASH_MS = 1400L;

  private static final int WHITE = 0xFFFFFFFF;
  private static final int MUTED = 0xFFAAAAAA;
  private static final int GREEN = 0xFF55FF55;
  private static final int GOLD = 0xFFFFAA00;
  private static final int RED = 0xFFFF5555;
  private static final int AQUA = 0xFF55FFFF;
  private static final int RULE = 0x2AFFFFFF;

  private enum Page {
    LOCAL,
    PHONE
  }

  private final Screen parent;
  private final List<Consumer<GuiGraphicsExtractor>> paintSteps = new ArrayList<>();
  private final List<Flash> flashes = new ArrayList<>();

  private Page page = Page.LOCAL;
  private boolean localServerStarted = true;
  private int tickCounter;

  private boolean serverRunning;
  private boolean phoneConnected;
  private int currentPort = -1;
  private List<String> addresses = List.of();
  private String httpsUrl = "";
  private String pairingCodeValue = "";

  public SetupWizardScreen(Screen parent) {
    super(Component.literal("MonkeyCraft setup"));
    this.parent = parent;
  }

  @Override
  protected void init() {
    super.init();
    paintSteps.clear();

    int left = PADDING;
    int right = width - PADDING;

    if (page == Page.LOCAL) {
      ensureServerStarted();
      buildLocalPage();
    } else {
      buildPhonePage();
    }

    int footerY = height - FOOTER_HEIGHT + 10;
    if (page == Page.PHONE) {
      addRenderableWidget(
          Button.builder(Component.literal("< Back"), button -> goToPage(Page.LOCAL))
              .bounds(left, footerY, BUTTON_WIDTH, CONTROL_HEIGHT)
              .build());
    }

    boolean lastPage = page == Page.PHONE;
    Button next =
        Button.builder(
                Component.literal(lastPage ? "Finish" : "Next >"),
                button -> {
                  if (lastPage) {
                    finish();
                  } else {
                    goToPage(Page.PHONE);
                  }
                })
            .bounds(width / 2 - BUTTON_WIDTH / 2, footerY, BUTTON_WIDTH, CONTROL_HEIGHT)
            .build();
    addRenderableWidget(next);

    addRenderableWidget(
        Button.builder(
                Component.literal(lastPage ? "Skip for now" : "Close"),
                button -> {
                  if (lastPage) {
                    finish();
                  } else {
                    onClose();
                  }
                })
            .bounds(right - BUTTON_WIDTH, footerY, BUTTON_WIDTH, CONTROL_HEIGHT)
            .build());

    refreshLiveState();
  }

  private void buildLocalPage() {
    int left = PADDING;
    int right = width - PADDING;

    paintSteps.add(
        graphics ->
            graphics.text(
                font,
                "Start the server. Phones on the same Wi-Fi can find this computer.",
                left,
                52,
                WHITE,
                false));

    String status;
    int statusColor;
    if (serverRunning) {
      status = "Running · port " + currentPort;
      statusColor = GREEN;
    } else if (localServerStarted) {
      status = "Starting...";
      statusColor = AQUA;
    } else {
      status = "Could not start the server (no free port 9600-9700).";
      statusColor = RED;
    }
    paintSteps.add(
        graphics -> {
          graphics.fill(left, 74, left + 4, 78, statusColor);
          graphics.text(font, status, left + 9, 70, statusColor, false);
        });

    if (!addresses.isEmpty()) {
      String address = "http://" + addresses.get(0);
      paintSteps.add(
          graphics -> graphics.text(font, "Address on this network", left, 92, MUTED, false));
      paintSteps.add(
          graphics ->
              graphics.text(
                  font,
                  font.plainSubstrByWidth(address, width - PADDING * 2 - 52),
                  left,
                  104,
                  WHITE,
                  false));
      addRenderableWidget(
          Button.builder(
                  Component.literal("Copy"),
                  button -> {
                    copyToClipboard(address);
                    flash(button, "Copy");
                  })
              .bounds(right - 46, 100, 46, CONTROL_HEIGHT)
              .build());
    } else if (serverRunning) {
      paintSteps.add(
          graphics ->
              graphics.text(font, "Addresses appear here shortly.", left, 92, MUTED, false));
    }

    if (!httpsUrl.isEmpty()) {
      String url = httpsUrl;
      paintSteps.add(graphics -> graphics.text(font, "HTTPS address", left, 128, MUTED, false));
      paintSteps.add(
          graphics ->
              graphics.text(
                  font,
                  font.plainSubstrByWidth(url, width - PADDING * 2 - 52),
                  left,
                  140,
                  WHITE,
                  false));
      addRenderableWidget(
          Button.builder(
                  Component.literal("Copy"),
                  button -> {
                    copyToClipboard(url);
                    flash(button, "Copy");
                  })
              .bounds(right - 46, 136, 46, CONTROL_HEIGHT)
              .build());
    }
  }

  private void buildPhonePage() {
    int left = PADDING;

    if (phoneConnected) {
      paintSteps.add(
          graphics -> {
            graphics.fill(left, 48, width - PADDING, 78, 0x3322AA22);
            graphics.fill(left, 48, left + 4, 78, GREEN);
            graphics.text(font, "Phone connected", left + 12, 52, GREEN, false);
            graphics.text(font, "Port " + currentPort, left + 12, 64, WHITE, false);
          });
    } else if (serverRunning) {
      paintSteps.add(
          graphics -> {
            graphics.fill(left, 52, left + 6, 58, GOLD);
            graphics.text(
                font, "Waiting for phone · port " + currentPort, left + 12, 50, GOLD, false);
          });
    } else {
      paintSteps.add(
          graphics -> {
            graphics.fill(left, 52, left + 6, 58, GOLD);
            graphics.text(font, "Server not running", left + 12, 50, GOLD, false);
          });
    }

    paintSteps.add(
        graphics ->
            graphics.text(font, "1. Open MonkeyCraft on your phone.", left, 86, WHITE, false));
    paintSteps.add(
        graphics ->
            graphics.text(
                font, "2. Type the address from the previous page.", left, 100, WHITE, false));
    paintSteps.add(
        graphics ->
            graphics.text(
                font,
                "3. Tap Pair on the phone, then choose Allow this phone here.",
                left,
                114,
                WHITE,
                false));
    int y = paragraph("The pairing request pops up in game — no passwords to type.", 136, MUTED);

    y = paragraph("If the popup is gone, type the code from the phone:", y, MUTED);
    int codeWidth = Math.min(140, width - PADDING * 2 - 72);
    EditBox codeBox =
        new EditBox(font, left, y, codeWidth, CONTROL_HEIGHT, Component.literal("Pairing code"));
    codeBox.setMaxLength(9);
    codeBox.setValue(pairingCodeValue);
    codeBox.setHint(Component.literal("ABCD-2345"));
    codeBox.setResponder(value -> pairingCodeValue = value);
    addRenderableWidget(codeBox);
    addRenderableWidget(
        Button.builder(Component.literal("Allow"), button -> onAllowTypedCode())
            .bounds(left + codeWidth + 6, y, 60, CONTROL_HEIGHT)
            .build());
    y += CONTROL_HEIGHT + 8;
    paragraph("You can finish now and pair later.", y, MUTED);
  }

  private void onAllowTypedCode() {
    String typed = pairingCodeValue == null ? "" : pairingCodeValue.trim();
    if (typed.isEmpty()) {
      return;
    }
    if (WebSocketServerHandler.getInstance().acceptPairing(typed)) {
      pairingCodeValue = "";
    }
    rebuildWidgets();
  }

  private void goToPage(Page next) {
    if (next == page) {
      return;
    }
    page = next;
    rebuildWidgets();
  }

  private void ensureServerStarted() {
    ModConfig config = ModConfig.getInstance();
    config.setEnabled(true);
    config.save();
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isRunning()) {
      int port = MonkeycraftClient.startServerWithPortRange(config.getPort());
      localServerStarted = port > 0;
    }
  }

  private void finish() {
    ModConfig config = ModConfig.getInstance();
    config.setWizardDone(true);
    config.save();
    onClose();
  }

  @Override
  public void tick() {
    super.tick();
    tickCounter++;
    long now = System.currentTimeMillis();
    Iterator<Flash> iterator = flashes.iterator();
    while (iterator.hasNext()) {
      Flash flash = iterator.next();
      if (now >= flash.until()) {
        flash.button().setMessage(Component.literal(flash.label()));
        iterator.remove();
      }
    }
    if (tickCounter % 10 == 0) {
      refreshLiveState();
    }
  }

  private void refreshLiveState() {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    boolean running = handler.isRunning();
    boolean connected = handler.isClientConnected();
    int port = handler.getCurrentPort();
    List<String> nextAddresses =
        running ? NetworkUtils.getLocalIpAddressesWithPort(port) : List.of();
    String nextHttps = running ? TailnetHttps.probeUrl() : "";

    if (running != serverRunning
        || connected != phoneConnected
        || port != currentPort
        || !nextAddresses.equals(addresses)
        || !nextHttps.equals(httpsUrl)) {
      serverRunning = running;
      phoneConnected = connected;
      currentPort = port;
      addresses = nextAddresses;
      httpsUrl = nextHttps;
      rebuildWidgets();
    }
  }

  @Override
  public void extractRenderState(
      GuiGraphicsExtractor graphics, int mouseX, int mouseY, float delta) {
    graphics.fill(0, 0, width, height, 0xF0000000);
    graphics.fill(0, 0, width, HEADER_HEIGHT, 0xDD000000);
    graphics.centeredText(font, pageTitle(), width / 2, (HEADER_HEIGHT - 8) / 2, WHITE);
    graphics.fill(0, HEADER_HEIGHT, width, HEADER_HEIGHT + 1, RULE);
    int footerY = height - FOOTER_HEIGHT;
    graphics.fill(0, footerY, width, height, 0xDD000000);
    graphics.fill(0, footerY, width, footerY + 1, RULE);
    paintSteps.forEach(step -> step.accept(graphics));
    super.extractRenderState(graphics, mouseX, mouseY, delta);
  }

  private String pageTitle() {
    return page == Page.PHONE ? "Connect your phone" : "Local network";
  }

  private int paragraph(String text, int y, int color) {
    int left = PADDING;
    int textWidth = Math.max(20, width - PADDING * 2);
    FormattedText wrapped = Component.literal(text);
    paintSteps.add(graphics -> graphics.textWithWordWrap(font, wrapped, left, y, textWidth, color));
    return y + font.wordWrapHeight(wrapped, textWidth) + 4;
  }

  private void copyToClipboard(String value) {
    if (minecraft != null) {
      minecraft.keyboardHandler.setClipboard(value);
    }
  }

  private void flash(Button button, String label) {
    button.setMessage(Component.literal("Copied!"));
    flashes.add(new Flash(button, label, System.currentTimeMillis() + FLASH_MS));
  }

  @Override
  public boolean shouldCloseOnEsc() {
    return true;
  }

  @Override
  public void onClose() {
    if (minecraft != null) {
      minecraft.setScreenAndShow(parent);
    }
  }

  private record Flash(Button button, String label, long until) {}
}
