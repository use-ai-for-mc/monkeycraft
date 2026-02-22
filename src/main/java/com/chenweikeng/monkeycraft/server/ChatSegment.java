package com.chenweikeng.monkeycraft.server;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.Style;
import net.minecraft.network.chat.TextColor;
import net.minecraft.util.StringDecomposer;

public class ChatSegment {

  public static List<JsonObject> fromComponent(Component component) {
    return fromComponent(component, true);
  }

  public static List<JsonObject> fromComponent(Component component, boolean canHaveHover) {
    List<JsonObject> segments = new ArrayList<>();

    MutableComponent legacyParsed = Component.empty();

    component.visit(
        (style, text) -> {
          if (text.isEmpty()) {
            return Optional.empty();
          }

          parseLegacy(style, text, legacyParsed);
          return Optional.empty();
        },
        Style.EMPTY);

    legacyParsed.visit(
        (style, text) -> {
          if (text.isEmpty()) {
            return Optional.empty();
          }

          JsonObject seg = new JsonObject();
          seg.addProperty("text", text);

          TextColor textColor = style.getColor();
          if (textColor != null) {
            String hexColor = String.format("#%06X", textColor.getValue() & 0xFFFFFF);
            seg.addProperty("color", hexColor);
          }

          if (style.isBold()) seg.addProperty("bold", true);
          if (style.isItalic()) seg.addProperty("italic", true);
          if (style.isUnderlined()) seg.addProperty("underlined", true);
          if (style.isStrikethrough()) seg.addProperty("strikethrough", true);
          if (style.isObfuscated()) seg.addProperty("obfuscated", true);

          ClickEvent clickEvent = style.getClickEvent();
          if (clickEvent != null) {
            if (clickEvent.action() == ClickEvent.Action.OPEN_URL) {
              ClickEvent.OpenUrl clickEventOpenUrl = (ClickEvent.OpenUrl) clickEvent;

              JsonObject clickEventJson = new JsonObject();
              clickEventJson.addProperty("action", clickEvent.action().name().toLowerCase());
              clickEventJson.addProperty("value", clickEventOpenUrl.uri().toString());
              seg.add("clickEvent", clickEventJson);
            } else if (clickEvent.action() == ClickEvent.Action.RUN_COMMAND) {
              ClickEvent.RunCommand clickEventRunCommand = (ClickEvent.RunCommand) clickEvent;

              JsonObject clickEventJson = new JsonObject();
              clickEventJson.addProperty("action", clickEvent.action().name().toLowerCase());
              clickEventJson.addProperty("value", clickEventRunCommand.command());
              seg.add("clickEvent", clickEventJson);
            } else if (clickEvent.action() == ClickEvent.Action.SUGGEST_COMMAND) {
              ClickEvent.SuggestCommand clickEventSuggestCommand =
                  (ClickEvent.SuggestCommand) clickEvent;

              JsonObject clickEventJson = new JsonObject();
              clickEventJson.addProperty("action", clickEvent.action().name().toLowerCase());
              clickEventJson.addProperty("value", clickEventSuggestCommand.command());
              seg.add("clickEvent", clickEventJson);
            } else if (clickEvent.action() == ClickEvent.Action.COPY_TO_CLIPBOARD) {
              ClickEvent.CopyToClipboard clickEventCopy = (ClickEvent.CopyToClipboard) clickEvent;

              JsonObject clickEventJson = new JsonObject();
              clickEventJson.addProperty("action", clickEvent.action().name().toLowerCase());
              clickEventJson.addProperty("value", clickEventCopy.value());
              seg.add("clickEvent", clickEventJson);
            }
          }

          if (canHaveHover) {
            HoverEvent hoverEvent = style.getHoverEvent();
            if (hoverEvent != null && hoverEvent.action() == HoverEvent.Action.SHOW_TEXT) {
              HoverEvent.ShowText showText = (HoverEvent.ShowText) hoverEvent;
              Component hoverComponent = showText.value();

              JsonObject hoverEventJson = new JsonObject();
              hoverEventJson.addProperty("action", "show_text");
              hoverEventJson.add(
                  "value",
                  ChatSegment.toJsonArray(ChatSegment.fromComponent(hoverComponent, false)));
              seg.add("hoverEvent", hoverEventJson);
            }
          }

          segments.add(seg);
          return Optional.empty();
        },
        Style.EMPTY);

    if (segments.isEmpty()) {
      JsonObject fallback = new JsonObject();
      fallback.addProperty("text", component.getString());
      segments.add(fallback);
    }

    return segments;
  }

  public static JsonArray toJsonArray(List<JsonObject> segments) {
    JsonArray arr = new JsonArray();
    for (JsonObject seg : segments) {
      arr.add(seg);
    }
    return arr;
  }

  private static void parseLegacy(Style baseStyle, String text, MutableComponent output) {

    StringBuilder buffer = new StringBuilder();
    AtomicReference<Style> lastStyle = new AtomicReference<>(null);

    StringDecomposer.iterateFormatted(
        text,
        baseStyle,
        (index, style, codepoint) -> {
          Style prev = lastStyle.get();

          if (prev == null) {
            lastStyle.set(style);
          }

          // style changed → flush
          if (!style.equals(prev)) {

            flush(buffer, prev, output);

            buffer.setLength(0);
            lastStyle.set(style);
          }

          buffer.appendCodePoint(codepoint);

          return true;
        });

    flush(buffer, lastStyle.get(), output);
  }

  private static void flush(StringBuilder buffer, Style style, MutableComponent output) {

    if (buffer.length() == 0) return;

    output.append(Component.literal(buffer.toString()).setStyle(style));
  }
}
