package com.chenweikeng.monkeycraft.integration;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Consumer;
import java.util.function.Function;

public final class FlawlessFrames {
  private static final List<Consumer<Boolean>> LISTENERS = new CopyOnWriteArrayList<>();

  private FlawlessFrames() {}

  public static void register(Function<String, Consumer<Boolean>> provider) {
    LISTENERS.add(provider.apply("monkeycraft"));
  }

  public static void setEnabled(boolean enabled) {
    for (Consumer<Boolean> listener : LISTENERS) {
      listener.accept(enabled);
    }
  }
}
