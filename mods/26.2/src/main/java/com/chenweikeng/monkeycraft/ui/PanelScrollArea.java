package com.chenweikeng.monkeycraft.ui;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.AbstractContainerWidget;
import net.minecraft.client.gui.components.AbstractScrollArea;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.network.chat.Component;

class PanelScrollArea extends AbstractContainerWidget {
  private final List<Placement> placements = new ArrayList<>();
  private final List<AbstractWidget> ordered = new ArrayList<>();
  private Consumer<GuiGraphicsExtractor> painter = graphics -> {};
  private int contentHeight;

  PanelScrollArea(int x, int y, int width, int height) {
    super(x, y, width, height, Component.empty(), AbstractScrollArea.defaultSettings(14));
  }

  void reset() {
    placements.clear();
    ordered.clear();
    painter = graphics -> {};
    contentHeight = 0;
    setFocused(null);
  }

  void setPainter(Consumer<GuiGraphicsExtractor> painter) {
    this.painter = painter;
  }

  void place(AbstractWidget widget, int x, int y) {
    placements.add(new Placement(widget, x, y));
    ordered.add(widget);
    contentHeight = Math.max(contentHeight, y + widget.getHeight());
  }

  void reserve(int height) {
    contentHeight = Math.max(contentHeight, height);
  }

  @Override
  public List<? extends GuiEventListener> children() {
    return ordered;
  }

  @Override
  protected int contentHeight() {
    return contentHeight;
  }

  @Override
  public void setScrollAmount(double amount) {
    super.setScrollAmount(amount);
    reposition();
  }

  @Override
  public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick) {
    if (!isMouseOver(event.x(), event.y())) {
      return false;
    }
    return super.mouseClicked(event, doubleClick);
  }

  @Override
  protected void extractWidgetRenderState(
      GuiGraphicsExtractor graphics, int mouseX, int mouseY, float delta) {
    reposition();
    graphics.enableScissor(getX(), getY(), getX() + getWidth(), getY() + getHeight());
    painter.accept(graphics);
    for (AbstractWidget widget : ordered) {
      widget.extractRenderState(graphics, mouseX, mouseY, delta);
    }
    graphics.disableScissor();
    extractScrollbar(graphics, mouseX, mouseY);
  }

  @Override
  protected void updateWidgetNarration(NarrationElementOutput output) {}

  private void reposition() {
    int scroll = (int) scrollAmount();
    for (Placement placement : placements) {
      placement.widget().setX(getX() + placement.x());
      placement.widget().setY(getY() + placement.y() - scroll);
    }
  }

  private record Placement(AbstractWidget widget, int x, int y) {}
}
