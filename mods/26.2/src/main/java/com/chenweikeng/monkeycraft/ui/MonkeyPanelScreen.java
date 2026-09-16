package com.chenweikeng.monkeycraft.ui;

import com.chenweikeng.monkeycraft.MonkeycraftClient;
import com.chenweikeng.monkeycraft.config.ModConfig;
import com.chenweikeng.monkeycraft.config.NetworkScope;
import com.chenweikeng.monkeycraft.config.ServerAutoStart;
import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import com.chenweikeng.monkeycraft.utils.TailnetHttps;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.function.Consumer;
import net.minecraft.ChatFormatting;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Checkbox;
import net.minecraft.client.gui.components.CycleButton;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.FormattedText;

public class MonkeyPanelScreen extends Screen {
  private static final int PADDING = 10;
  private static final int HEADER_HEIGHT = 14;
  private static final int TAB_HEIGHT = 20;
  private static final int TAB_GAP = 3;
  private static final int FOOTER_HEIGHT = 34;
  private static final int CONTROL_HEIGHT = 20;
  private static final int ROW_GAP = 4;
  private static final int SECTION_GAP = 10;

  private static final int WHITE = 0xFFFFFFFF;
  private static final int MUTED = 0xFFAAAAAA;
  private static final int FAINT = 0xFF6E6E6E;
  private static final int GREEN = 0xFF55FF55;
  private static final int GOLD = 0xFFFFAA00;
  private static final int RED = 0xFFFF5555;
  private static final int AQUA = 0xFF55FFFF;
  private static final int RULE = 0x2AFFFFFF;
  private static final int PANEL = 0xFF3F3F3F;
  private static final int BEVEL_LIGHT = 0x80FFFFFF;
  private static final int BEVEL_DARK = 0x99000000;
  private static final int DANGER = 0x1AFF5555;

  private static final long NOTICE_MS = 6000L;
  private static final long FLASH_MS = 1400L;

  private static final int PAGE_HOME = 0;
  private static final int PAGE_ADVANCED = 1;
  private static final int ADV_STARTUP = 0;
  private static final int ADV_COMMANDS = 1;
  private static final int ADV_NETWORK = 2;
  private static final int ADV_COMPAT = 3;
  private static final int ADV_COUNT = 4;
  private static final String[] ADV_LABELS = {"Startup", "Commands", "Network", "Compatibility"};
  private static final int NAV_WIDTH = 110;

  private final Screen parent;
  private final double[] advScroll = new double[ADV_COUNT];
  private final List<Consumer<GuiGraphicsExtractor>> bodySteps = new ArrayList<>();
  private final List<Flash> flashes = new ArrayList<>();

  private PanelScrollArea body;
  private int page = PAGE_HOME;
  private int advSection = ADV_STARTUP;
  private int cursor;
  private int tickCounter;

  private List<String> addresses = List.of();
  private boolean serverRunning;
  private boolean phoneConnected;
  private int actualPort = -1;

  private String notice = "";
  private int noticeColor = MUTED;
  private long noticeUntil;

  private String portValue;
  private String passwordValue;
  private String allowValue;
  private String denyValue;
  private String codeValue = "";

  public MonkeyPanelScreen(Screen parent) {
    super(Component.literal("MonkeyCraft"));
    this.parent = parent;
    ModConfig config = ModConfig.getInstance();
    this.portValue = Integer.toString(config.getPort());
    this.passwordValue = config.getPassword() == null ? "" : config.getPassword();
    this.allowValue = String.join(", ", config.getCommandAllowlist());
    this.denyValue = String.join(", ", config.getCommandDenylist());
  }

  @Override
  protected void init() {
    super.init();
    bodySteps.clear();
    flashes.clear();

    int left = PADDING;
    int right = width - PADDING;
    int span = right - left;

    int top = PADDING + HEADER_HEIGHT + 8;

    int bodyLeft = left;
    int bodyWidth = span;
    if (page == PAGE_ADVANCED) {
      int navY = top;
      for (int i = 0; i < ADV_COUNT; i++) {
        int index = i;
        Button nav =
            Button.builder(Component.literal(ADV_LABELS[i]), button -> selectAdv(index))
                .bounds(left, navY, NAV_WIDTH, TAB_HEIGHT)
                .build();
        addRenderableWidget(nav);
        navY += TAB_HEIGHT + TAB_GAP;
      }
      bodyLeft = left + NAV_WIDTH + 10;
      bodyWidth = Math.max(40, right - bodyLeft);
    }

    int bodyBottom = height - FOOTER_HEIGHT - 6;
    body = new PanelScrollArea(bodyLeft, top, bodyWidth, Math.max(20, bodyBottom - top));
    addRenderableWidget(body);

    cursor = 0;
    if (page == PAGE_ADVANCED) {
      buildAdvancedSection();
    } else {
      buildHomePage();
    }
    body.setPainter(graphics -> bodySteps.forEach(step -> step.accept(graphics)));
    body.reserve(cursor + 2);
    if (page == PAGE_ADVANCED) {
      body.setScrollAmount(advScroll[advSection]);
    }

    int footerY = height - FOOTER_HEIGHT + 8;
    if (page == PAGE_ADVANCED) {
      addRenderableWidget(
          Button.builder(Component.literal("Back"), button -> showHome())
              .bounds(left, footerY, 76, CONTROL_HEIGHT)
              .build());
    } else {
      int footerX = left;
      footerX = footerButton(footerX, footerY, "Settings", button -> selectAdv(ADV_STARTUP));
      footerX =
          footerButton(
              footerX,
              footerY,
              "Connect method",
              button -> {
                if (minecraft != null) {
                  minecraft.setScreenAndShow(new SetupWizardScreen(this));
                }
              });
      if (WebSocketServerHandler.getInstance().isRunning()) {
        footerButton(footerX, footerY, "Stop server", button -> onStop());
      }
    }
    addRenderableWidget(
        Button.builder(Component.literal("Close"), button -> onClose())
            .bounds(right - 60, footerY, 60, CONTROL_HEIGHT)
            .build());

    refreshLiveState();
  }

  private void selectAdv(int section) {
    if (section == advSection && page == PAGE_ADVANCED) {
      return;
    }
    if (page == PAGE_ADVANCED && body != null) {
      advScroll[advSection] = body.scrollAmount();
    }
    page = PAGE_ADVANCED;
    advSection = section;
    rebuildWidgets();
  }

  private void showHome() {
    if (page == PAGE_ADVANCED && body != null) {
      advScroll[advSection] = body.scrollAmount();
    }
    page = PAGE_HOME;
    rebuildWidgets();
  }

  private void buildHomePage() {
    ModConfig config = ModConfig.getInstance();
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    int span = contentWidth();

    statusBanner(span);

    if (!handler.isRunning()) {
      heroStart(span);
      return;
    }
    if (handler.isClientConnected()) {
      heroConnected(span);
      return;
    }
    buildLanWaiting(span);
  }

  private void statusBanner(int span) {
    ModConfig config = ModConfig.getInstance();
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    final String headline;
    final String detail;
    final int color;
    if (!handler.isRunning()) {
      headline = "Server stopped";
      detail =
          config.getServerAutoStart() == ServerAutoStart.OFF
              ? "Press Start server when you want a phone to connect"
              : "Starts automatically: " + autoStartLabel(config.getServerAutoStart()).getString();
      color = MUTED;
    } else if (handler.isClientConnected()) {
      String deviceName = handler.getConnectedDeviceName();
      headline = deviceName.isEmpty() ? "Phone connected" : deviceName + " connected";
      detail = "Streaming live";
      color = GREEN;
    } else {
      headline = "Waiting for a phone...";
      detail = portDetail(handler.getCurrentPort(), config.getPort());
      color = GOLD;
    }
    int blockHeight = font.lineHeight * 2 + 12;
    int blockY = cursor;
    framedPanel(blockY, span, blockHeight);
    bodySteps.add(
        graphics -> {
          int y = body.getY() + blockY - scroll();
          int dotX = body.getX() + 11;
          int dotY = y + 8;
          long t = System.currentTimeMillis() % 2000L;
          int alpha = 0x90 + (int) (0x6F * (0.5 + 0.5 * Math.sin(t / 2000.0 * 2.0 * Math.PI)));
          graphics.fill(dotX - 1, dotY - 1, dotX + 6, dotY + 6, 0xE6000000);
          graphics.fill(dotX, dotY, dotX + 5, dotY + 5, (alpha << 24) | (color & 0xFFFFFF));
          graphics.text(font, headline, body.getX() + 24, y + 5, color, false);
          graphics.text(font, detail, body.getX() + 24, y + 7 + font.lineHeight, MUTED, false);
        });
    cursor += blockHeight + 8;
  }

  private void heroStart(int span) {
    int panelHeight = 62;
    int panelY = cursor;
    framedPanel(panelY, span, panelHeight);
    Button start =
        Button.builder(Component.literal("Start server"), button -> onStart())
            .bounds(0, 0, 150, CONTROL_HEIGHT)
            .build();
    body.place(start, Math.max(0, (span - 150) / 2), panelY + 10);
    centeredText(HomeCopy.stoppedLine(), panelY + 40, span, MUTED);
    cursor += panelHeight + 8;
  }

  private void heroConnected(int span) {
    int panelHeight = 44;
    int panelY = cursor;
    framedPanel(panelY, span, panelHeight);
    String deviceName = WebSocketServerHandler.getInstance().getConnectedDeviceName();
    String title =
        deviceName.isEmpty() ? HomeCopy.HOME_CONNECTED_TITLE : deviceName + " — happy mining!";
    centeredComponent(
        Component.literal(title).withStyle(ChatFormatting.BOLD), panelY + 9, span, GREEN);
    centeredText(HomeCopy.HOME_CONNECTED_BODY, panelY + 26, span, MUTED);
    cursor += panelHeight + 8;
  }

  private void heroValue(String label, String value, String why, int span) {
    int panelHeight = 50;
    int panelY = cursor;
    framedPanel(panelY, span, panelHeight);
    centeredText(label, panelY + 7, span, MUTED);
    centeredComponent(
        Component.literal(value).withStyle(ChatFormatting.BOLD), panelY + 20, span, GOLD);
    centeredText(why, panelY + 37, span, MUTED);
    cursor += panelHeight + 8;
  }

  private void questPanel(String[] steps, int span) {
    ModConfig config = ModConfig.getInstance();
    if (config.isPhonePairedOnce()) {
      String collapsed = "New phone? Open the app and type an address above.";
      centeredText(collapsed, cursor + 4, span, FAINT);
      cursor += font.lineHeight + 6;
      String lastName = config.getLastPhoneName();
      if (!lastName.isEmpty() && config.getLastPhoneSeenAt() > 0) {
        centeredText(
            "Last phone: " + lastName + " · " + relativeTime(config.getLastPhoneSeenAt()),
            cursor + 2,
            span,
            FAINT);
        cursor += font.lineHeight + 6;
      }
      cursor += 6;
      return;
    }
    FormattedText note = Component.literal(HomeCopy.QUEST_NOTE);
    int noteWidth = Math.max(20, span - 20);
    int panelHeight =
        7
            + font.lineHeight
            + 5
            + steps.length * (font.lineHeight + 3)
            + 3
            + font.wordWrapHeight(note, noteWidth)
            + 4
            + font.lineHeight
            + 7;
    int panelY = cursor;
    framedPanel(panelY, span, panelHeight);
    int titleY = panelY + 7;
    bodySteps.add(
        graphics ->
            graphics.text(
                font,
                HomeCopy.QUEST_TITLE,
                body.getX() + 10,
                body.getY() + titleY - scroll(),
                GOLD,
                false));
    int stepY = titleY + font.lineHeight + 5;
    for (String step : steps) {
      int lineY = stepY;
      bodySteps.add(
          graphics ->
              graphics.text(
                  font, step, body.getX() + 12, body.getY() + lineY - scroll(), WHITE, false));
      stepY += font.lineHeight + 3;
    }
    int noteY = stepY + 3;
    bodySteps.add(
        graphics ->
            graphics.textWithWordWrap(
                font, note, body.getX() + 10, body.getY() + noteY - scroll(), noteWidth, MUTED));
    int footY = noteY + font.wordWrapHeight(note, noteWidth) + 4;
    bodySteps.add(
        graphics ->
            graphics.text(
                font,
                HomeCopy.QUEST_FOOTNOTE,
                body.getX() + 10,
                body.getY() + footY - scroll(),
                FAINT,
                false));
    cursor += panelHeight + 8;
  }

  private static String relativeTime(long epochMillis) {
    long minutes = (System.currentTimeMillis() - epochMillis) / 60000L;
    if (minutes < 1) {
      return "just now";
    }
    if (minutes < 60) {
      return minutes + " min ago";
    }
    long hours = minutes / 60;
    if (hours < 24) {
      return hours + (hours == 1 ? " hour ago" : " hours ago");
    }
    long days = hours / 24;
    if (days == 1) {
      return "yesterday";
    }
    if (days < 30) {
      return days + " days ago";
    }
    return "a while ago";
  }

  private void framedPanel(int y, int span, int panelHeight) {
    bodySteps.add(
        graphics -> {
          int x = body.getX();
          int yy = body.getY() + y - scroll();
          graphics.fill(x - 1, yy - 1, x + span + 1, yy + panelHeight + 1, 0xFF000000);
          graphics.fill(x, yy, x + span, yy + panelHeight, PANEL);
          graphics.fill(x, yy, x + span, yy + 1, BEVEL_LIGHT);
          graphics.fill(x, yy, x + 1, yy + panelHeight, BEVEL_LIGHT);
          graphics.fill(x, yy + panelHeight - 1, x + span, yy + panelHeight, BEVEL_DARK);
          graphics.fill(x + span - 1, yy, x + span, yy + panelHeight, BEVEL_DARK);
        });
  }

  private void centeredText(String text, int y, int span, int color) {
    bodySteps.add(
        graphics -> {
          String shown = font.plainSubstrByWidth(text, Math.max(10, span - 16));
          int textWidth = font.width(shown);
          int x = body.getX() + Math.max(8, (span - textWidth) / 2);
          graphics.text(font, shown, x, body.getY() + y - scroll(), color, false);
        });
  }

  private void centeredComponent(Component text, int y, int span, int color) {
    bodySteps.add(
        graphics -> {
          int textWidth = font.width(text);
          int x = body.getX() + Math.max(8, (span - textWidth) / 2);
          graphics.text(font, text, x, body.getY() + y - scroll(), color, false);
        });
  }

  private void buildLanWaiting(int span) {
    if (addresses.isEmpty()) {
      paragraph("Addresses appear here once the server is running.", span, MUTED);
    } else {
      heroValue(HomeCopy.HOME_HERO_LABEL_ADDRESS, addresses.get(0), HomeCopy.HOME_WHY_LAN, span);
      if (addresses.size() > 1) {
        section("Other addresses");
        for (int i = 1; i < addresses.size(); i++) {
          copyRow(addresses.get(i), span, WHITE);
        }
      }
    }
    questPanel(HomeCopy.QUEST_STEPS_LAN, span);
  }

  private void buildAdvancedSection() {
    switch (advSection) {
      case ADV_COMMANDS -> buildAdvCommands();
      case ADV_NETWORK -> buildAdvNetwork();
      case ADV_COMPAT -> buildAdvCompat();
      default -> buildAdvStartup();
    }
  }

  private void buildAdvStartup() {
    ModConfig config = ModConfig.getInstance();
    int span = contentWidth();
    int controlWidth = Math.min(span, 220);
    paragraph(
        "These options only change how MonkeyCraft starts with the game. They do not change how a"
            + " phone finds this computer.",
        span,
        MUTED);
    CycleButton<ServerAutoStart> autoStart =
        CycleButton.<ServerAutoStart>builder(
                MonkeyPanelScreen::autoStartLabel, config.getServerAutoStart())
            .withValues(ServerAutoStart.values())
            .create(
                0,
                0,
                controlWidth,
                CONTROL_HEIGHT,
                Component.literal("Auto-start server"),
                (button, value) -> {
                  config.setServerAutoStart(value);
                  config.save();
                });
    addControl(autoStart, 0, controlWidth);
    Checkbox remoteJoin =
        Checkbox.builder(Component.literal("Allow remote server join"), font)
            .pos(0, 0)
            .maxWidth(span - 8)
            .selected(config.isAllowRemoteServerJoin())
            .onValueChange(
                (box, value) -> {
                  config.setAllowRemoteServerJoin(value);
                  config.save();
                })
            .build();
    addControl(remoteJoin, 0, Math.min(span, remoteJoin.getWidth()));
    paragraph("Lets the phone join a multiplayer server while streaming.", span, FAINT);
    Checkbox autoJump =
        Checkbox.builder(Component.literal("Force auto-jump while streaming"), font)
            .pos(0, 0)
            .maxWidth(span - 8)
            .selected(config.isAlwaysAutoJump())
            .onValueChange(
                (box, value) -> {
                  config.setAlwaysAutoJump(value);
                  config.save();
                })
            .build();
    addControl(autoJump, 0, Math.min(span, autoJump.getWidth()));
  }

  private void buildAdvCommands() {
    ModConfig config = ModConfig.getInstance();
    int span = contentWidth();
    paragraph(
        "Commands the phone is allowed to run. Deny wins over allow. Comma-separated patterns.",
        span,
        MUTED);
    int listWidth = Math.max(90, span - 56);
    EditBox allowBox =
        new EditBox(font, 0, 0, listWidth, CONTROL_HEIGHT, Component.literal("Allowlist"));
    allowBox.setMaxLength(256);
    allowBox.setValue(allowValue);
    allowBox.setHint(Component.literal("Allowlist"));
    allowBox.setResponder(
        value -> {
          allowValue = value;
          config.setCommandAllowlist(splitList(value));
          config.save();
        });
    controlRow("Allow", allowBox, listWidth);
    EditBox denyBox =
        new EditBox(font, 0, 0, listWidth, CONTROL_HEIGHT, Component.literal("Denylist"));
    denyBox.setMaxLength(256);
    denyBox.setValue(denyValue);
    denyBox.setHint(Component.literal("Denylist"));
    denyBox.setResponder(
        value -> {
          denyValue = value;
          config.setCommandDenylist(splitList(value));
          config.save();
        });
    controlRow("Deny", denyBox, listWidth);
  }

  private void buildAdvNetwork() {
    ModConfig config = ModConfig.getInstance();
    int span = contentWidth();
    int controlWidth = Math.min(span, 220);
    paragraph("Who may reach this computer's listen port.", span, MUTED);
    CycleButton<NetworkScope> scope =
        CycleButton.<NetworkScope>builder(MonkeyPanelScreen::scopeLabel, config.getNetworkScope())
            .withValues(NetworkScope.values())
            .create(
                0,
                0,
                controlWidth,
                CONTROL_HEIGHT,
                Component.literal("Who can connect"),
                (button, value) -> {
                  config.setNetworkScope(value);
                  config.save();
                  rebuildWidgets();
                });
    addControl(scope, 0, controlWidth);
    paragraph(scopeDescription(config.getNetworkScope()), span, MUTED);
    if (config.getNetworkScope() == NetworkScope.ANYONE) {
      danger(
          span,
          "Warning: this port is open beyond your local network",
          "Anyone who can route to this computer can try to connect and control the game.");
    }
    EditBox portBox = new EditBox(font, 0, 0, 70, CONTROL_HEIGHT, Component.literal("Port"));
    portBox.setMaxLength(5);
    portBox.setValue(portValue);
    portBox.setHint(Component.literal("9600"));
    portBox.setResponder(
        value -> {
          portValue = value;
          if (value.isBlank()) {
            return;
          }
          try {
            config.setPort(Integer.parseInt(value.trim()));
            config.save();
          } catch (NumberFormatException ignored) {
            return;
          }
        });
    controlRow("Preferred port", portBox, 70);
    paragraph(
        "If the preferred port is busy, the server takes the next free port up to 9700.",
        span,
        FAINT);
  }

  private void buildAdvCompat() {
    ModConfig config = ModConfig.getInstance();
    int span = contentWidth();
    int copyWidth = 50;
    int regenerateWidth = 84;
    int fieldWidth = Math.max(60, span - copyWidth - regenerateWidth - 10);
    paragraph(
        "For older apps, or when pairing is not available. Everyday phones should tap Pair and use"
            + " Allow on this computer.",
        span,
        MUTED);

    section("Password and QR");
    paragraph(
        "For older apps, or phones that cannot pair. Everyday connections use Allow on this"
            + " computer.",
        span,
        MUTED);
    EditBox passwordBox =
        new EditBox(font, 0, 0, fieldWidth, CONTROL_HEIGHT, Component.literal("Password"));
    passwordBox.setMaxLength(64);
    passwordBox.setValue(passwordValue);
    passwordBox.setHint(Component.literal("Password"));
    passwordBox.setResponder(
        value -> {
          passwordValue = value;
          config.setPassword(value);
          config.save();
        });
    Button copyPassword =
        Button.builder(
                Component.literal("Copy"),
                button -> {
                  copyToClipboard(passwordValue);
                  flash(button, "Copy");
                })
            .bounds(0, 0, copyWidth, CONTROL_HEIGHT)
            .build();
    Button regenerate =
        Button.builder(Component.literal("Regenerate"), button -> onRegenerate())
            .bounds(0, 0, regenerateWidth, CONTROL_HEIGHT)
            .build();
    body.place(passwordBox, 0, cursor);
    body.place(copyPassword, span - copyWidth - regenerateWidth - 5, cursor);
    body.place(regenerate, span - regenerateWidth, cursor);
    cursor += CONTROL_HEIGHT + ROW_GAP;
    paragraph(
        "A new password signs out phones that already paired. They must pair again or type the new"
            + " password.",
        span,
        GOLD);

    int qr = PasswordQrOverlay.sizePx();
    int hintX = qr + 14;
    int hintWidth = Math.max(20, span - hintX);
    FormattedText hint =
        Component.literal("Scan this in the MonkeyCraft app to fill in the password.");
    int qrY = cursor;
    bodySteps.add(
        graphics -> {
          int x = body.getX();
          int y = body.getY() + qrY - scroll();
          graphics.fill(x, y, x + qr + 8, y + qr + 8, WHITE);
          PasswordQrOverlay.blitAt(graphics, ModConfig.getInstance().getPassword(), x + 4, y + 4);
        });
    bodySteps.add(
        graphics ->
            graphics.textWithWordWrap(
                font, hint, body.getX() + hintX, body.getY() + qrY - scroll(), hintWidth, MUTED));
    cursor += Math.max(qr + 8, font.wordWrapHeight(hint, hintWidth)) + 6;

    Checkbox showQr =
        Checkbox.builder(
                Component.literal("Show QR on the title screen when the server auto-starts"), font)
            .pos(0, 0)
            .maxWidth(span - 8)
            .selected(config.isShowQrCodeWhenAutoLaunch())
            .onValueChange(
                (box, value) -> {
                  config.setShowQrCodeWhenAutoLaunch(value);
                  config.save();
                })
            .build();
    addControl(showQr, 0, Math.min(span, showQr.getWidth()));

    section("Addresses");
    paragraph(
        "Type one of these plus the password in the app. Funnel and tunnel URLs are not listed here.",
        span,
        MUTED);
    if (addresses.isEmpty()) {
      paragraph("Addresses appear here once the server is running.", span, MUTED);
    } else {
      for (String address : addresses) {
        copyRow(address, span, WHITE);
      }
    }

    section("Allow a phone by code");
    paragraph(
        "Backup if the pairing popup was missed. Same as /monkey accept CODE in chat.",
        span,
        MUTED);
    int allowWidth = 60;
    int codeWidth = Math.max(60, span - allowWidth - 6);
    EditBox codeBox =
        new EditBox(font, 0, 0, codeWidth, CONTROL_HEIGHT, Component.literal("Pairing code"));
    codeBox.setMaxLength(9);
    codeBox.setValue(codeValue);
    codeBox.setHint(Component.literal("Pairing code"));
    codeBox.setResponder(value -> codeValue = value);
    Button allowCode =
        Button.builder(Component.literal("Allow"), button -> onAllowTypedCode())
            .bounds(0, 0, allowWidth, CONTROL_HEIGHT)
            .build();
    addRow(codeBox, allowCode, codeWidth, allowWidth);
  }

  private void onStart() {
    ModConfig config = ModConfig.getInstance();
    if (!config.isEnabled()) {
      config.setEnabled(true);
      config.save();
    }
    int port = MonkeycraftClient.startServerWithPortRange(config.getPort());
    if (port > 0) {
      WebSocketServerHandler.getInstance().resetQrTimer();
      setNotice("Server started on port " + port + ".", GREEN);
    } else {
      setNotice("No free port between 9600 and 9700.", RED);
    }
    rebuildWidgets();
  }

  private void onStop() {
    WebSocketServerHandler.getInstance().stopServer();
    setNotice("Server stopped.", MUTED);
    rebuildWidgets();
  }

  private void onAllowTypedCode() {
    String typed = codeValue == null ? "" : codeValue.trim();
    if (typed.isEmpty()) {
      setNotice("Type the code shown on the phone.", GOLD);
      return;
    }
    if (WebSocketServerHandler.getInstance().acceptPairing(typed)) {
      codeValue = "";
      setNotice("Phone paired. It now has the password.", GREEN);
    } else {
      setNotice("No pairing matches that code.", GOLD);
    }
    rebuildWidgets();
  }

  private void onRegenerate() {
    String next = ModConfig.generateRandomPassword();
    ModConfig.getInstance().setPassword(next);
    ModConfig.getInstance().save();
    passwordValue = next;
    setNotice("New password. Phones that already paired must pair again.", GOLD);
    rebuildWidgets();
  }

  @Override
  public void tick() {
    super.tick();
    tickCounter++;
    if (tickCounter % 10 == 0) {
      refreshLiveState();
    }
    long now = System.currentTimeMillis();
    Iterator<Flash> iterator = flashes.iterator();
    while (iterator.hasNext()) {
      Flash flash = iterator.next();
      if (now >= flash.until()) {
        flash.button().setMessage(Component.literal(flash.label()));
        iterator.remove();
      }
    }
    if (!notice.isEmpty() && now > noticeUntil) {
      notice = "";
    }
  }

  private void refreshLiveState() {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    boolean running = handler.isRunning();
    boolean connected = handler.isClientConnected();
    int port = handler.getCurrentPort();
    List<String> nextAddresses = connectionAddresses();

    if (running != serverRunning || connected != phoneConnected || port != actualPort) {
      serverRunning = running;
      phoneConnected = connected;
      actualPort = port;
      addresses = nextAddresses;
      rebuildWidgets();
      return;
    }
    if (!nextAddresses.equals(addresses)) {
      addresses = nextAddresses;
      rebuildWidgets();
    }
  }

  @Override
  public void extractRenderState(
      GuiGraphicsExtractor graphics, int mouseX, int mouseY, float delta) {
    graphics.fill(0, 0, width, height, 0xF0000000);
    drawHeader(graphics);
    drawFooter(graphics);
    if (page == PAGE_ADVANCED) {
      drawActiveAdv(graphics);
    }
    super.extractRenderState(graphics, mouseX, mouseY, delta);
  }

  private int footerButton(int x, int y, String label, Button.OnPress onPress) {
    int buttonWidth = font.width(label) + 16;
    addRenderableWidget(
        Button.builder(Component.literal(label), onPress)
            .bounds(x, y, buttonWidth, CONTROL_HEIGHT)
            .build());
    return x + buttonWidth + 4;
  }

  private void drawHeader(GuiGraphicsExtractor graphics) {
    int left = PADDING;
    int right = width - PADDING;
    Component heading =
        Component.literal("MonkeyCraft").withStyle(ChatFormatting.BOLD, ChatFormatting.GOLD);
    graphics.text(font, heading, left, PADDING + 2, GOLD, false);
    graphics.fill(left, PADDING + HEADER_HEIGHT + 2, right, PADDING + HEADER_HEIGHT + 3, RULE);
  }

  private void drawActiveAdv(GuiGraphicsExtractor graphics) {
    int left = PADDING;
    int top = PADDING + HEADER_HEIGHT + 8;
    int y = top;
    for (int i = 0; i < ADV_COUNT; i++) {
      if (i == advSection) {
        graphics.fill(left, y, left + 2, y + TAB_HEIGHT, GOLD);
      }
      y += TAB_HEIGHT + TAB_GAP;
    }
  }

  private void drawFooter(GuiGraphicsExtractor graphics) {
    int footerY = height - FOOTER_HEIGHT;
    graphics.fill(0, footerY, width, height, 0xDD000000);
    graphics.fill(0, footerY, width, footerY + 1, RULE);
    if (!notice.isEmpty()) {
      int available = width - PADDING * 2;
      graphics.text(
          font,
          font.plainSubstrByWidth(notice, Math.max(0, available)),
          PADDING,
          footerY - 12,
          noticeColor,
          false);
    }
  }

  private void danger(int span, String title, String detail) {
    FormattedText wrapped = Component.literal(detail);
    int textWidth = Math.max(20, span - 18);
    int blockHeight = font.lineHeight + font.wordWrapHeight(wrapped, textWidth) + 10;
    int blockY = cursor;
    bodySteps.add(
        graphics -> {
          int y = body.getY() + blockY - scroll();
          graphics.fill(body.getX(), y, body.getX() + span, y + blockHeight, DANGER);
          graphics.fill(body.getX(), y, body.getX() + 2, y + blockHeight, RED);
          graphics.text(font, title, body.getX() + 9, y + 5, RED, false);
          graphics.textWithWordWrap(
              font, wrapped, body.getX() + 9, y + 7 + font.lineHeight, textWidth, RED);
        });
    cursor += blockHeight + 6;
  }

  private void section(String title) {
    if (cursor > 0) {
      cursor += SECTION_GAP;
      int span = contentWidth();
      int ruleY = cursor;
      bodySteps.add(
          graphics -> {
            int y = body.getY() + ruleY - scroll();
            graphics.fill(body.getX(), y, body.getX() + span, y + 1, RULE);
          });
      cursor += 5;
    }
    int titleY = cursor;
    bodySteps.add(
        graphics ->
            graphics.text(font, title, body.getX(), body.getY() + titleY - scroll(), MUTED, false));
    cursor += font.lineHeight + 4;
  }

  private void heading(String text, int color) {
    int textY = cursor;
    bodySteps.add(
        graphics ->
            graphics.text(font, text, body.getX(), body.getY() + textY - scroll(), color, false));
    cursor += font.lineHeight + 6;
  }

  private void paragraph(String text, int width, int color) {
    FormattedText wrapped = Component.literal(text);
    int textWidth = Math.max(20, width);
    int textY = cursor;
    bodySteps.add(
        graphics ->
            graphics.textWithWordWrap(
                font, wrapped, body.getX(), body.getY() + textY - scroll(), textWidth, color));
    cursor += font.wordWrapHeight(wrapped, textWidth) + 4;
  }

  private void labelled(String label, String value, int color) {
    int span = contentWidth();
    int valueX = Math.min(font.width(label) + 12, span / 2);
    int rowY = cursor;
    bodySteps.add(
        graphics -> {
          int y = body.getY() + rowY - scroll();
          graphics.text(font, label, body.getX(), y, MUTED, false);
          graphics.text(
              font,
              font.plainSubstrByWidth(value, Math.max(0, span - valueX)),
              body.getX() + valueX,
              y,
              color,
              false);
        });
    cursor += font.lineHeight + 4;
  }

  private void copyRow(String value, int span, int color) {
    int copyWidth = 46;
    int textWidth = Math.max(20, span - copyWidth - 6);
    int rowY = cursor;
    bodySteps.add(
        graphics ->
            graphics.text(
                font,
                font.plainSubstrByWidth(value, textWidth),
                body.getX(),
                body.getY() + rowY - scroll() + 6,
                color,
                false));
    Button copy =
        Button.builder(
                Component.literal("Copy"),
                button -> {
                  copyToClipboard(value);
                  flash(button, "Copy");
                })
            .bounds(0, 0, copyWidth, CONTROL_HEIGHT)
            .build();
    body.place(copy, span - copyWidth, rowY);
    cursor += CONTROL_HEIGHT + ROW_GAP;
  }

  private void controlRow(String label, AbstractWidget control, int controlWidth) {
    int span = contentWidth();
    int rowY = cursor;
    bodySteps.add(
        graphics ->
            graphics.text(
                font,
                label,
                body.getX(),
                body.getY() + rowY - scroll() + (CONTROL_HEIGHT - font.lineHeight) / 2 + 1,
                MUTED,
                false));
    body.place(control, Math.max(0, span - controlWidth), rowY);
    cursor += CONTROL_HEIGHT + ROW_GAP;
  }

  private void addControl(AbstractWidget widget, int x, int width) {
    body.place(widget, x, cursor);
    cursor += widget.getHeight() + ROW_GAP;
  }

  private void addRow(
      AbstractWidget first, AbstractWidget second, int firstWidth, int secondWidth) {
    body.place(first, 0, cursor);
    body.place(second, firstWidth + 6, cursor);
    cursor += CONTROL_HEIGHT + ROW_GAP;
  }

  private void gap(int amount) {
    cursor += amount;
  }

  private int contentWidth() {
    return Math.max(40, body.getWidth() - body.scrollbarWidth() - 6);
  }

  private int scroll() {
    return (int) body.scrollAmount();
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

  private void setNotice(String text, int color) {
    notice = text;
    noticeColor = color;
    noticeUntil = System.currentTimeMillis() + NOTICE_MS;
  }

  private List<String> connectionAddresses() {
    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();
    if (!handler.isRunning()) {
      return List.of();
    }
    List<String> result =
        new ArrayList<>(NetworkUtils.getLocalIpAddressesWithPort(handler.getCurrentPort()));
    String httpsUrl = TailnetHttps.probeUrl();
    if (!httpsUrl.isEmpty()) {
      result.add(httpsUrl);
    }
    return result;
  }

  @Override
  public void rebuildWidgets() {
    if (body != null && page == PAGE_ADVANCED) {
      advScroll[advSection] = body.scrollAmount();
    }
    super.rebuildWidgets();
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

  private static String portDetail(int actual, int preferred) {
    return actual == preferred
        ? "port " + actual
        : "port " + actual + " (preferred " + preferred + " busy)";
  }

  private static String scopeDescription(NetworkScope scope) {
    switch (scope) {
      case THIS_COMPUTER:
        return "Only this computer can reach the server. Use this for testing.";
      case ANYONE:
        return "Any device that can route to this computer can reach it.";
      default:
        return "Phones on the same Wi-Fi can reach this computer.";
    }
  }

  private static List<String> splitList(String raw) {
    if (raw == null || raw.isBlank()) {
      return new ArrayList<>();
    }
    return Arrays.stream(raw.split(","))
        .map(String::trim)
        .filter(entry -> !entry.isEmpty())
        .toList();
  }

  private static Component autoStartLabel(ServerAutoStart value) {
    return switch (value) {
      case OFF -> Component.literal("Off");
      case AT_TITLE_SCREEN -> Component.literal("At title screen");
      case ON_WORLD_JOIN -> Component.literal("On world join");
    };
  }

  private static Component scopeLabel(NetworkScope value) {
    return switch (value) {
      case THIS_COMPUTER -> Component.literal("This computer only");
      case LOCAL_NETWORK -> Component.literal("My local network");
      case ANYONE -> Component.literal("Anyone (advanced)");
    };
  }

  private record Flash(Button button, String label, long until) {}
}
