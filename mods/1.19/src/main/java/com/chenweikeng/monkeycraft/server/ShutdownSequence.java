package com.chenweikeng.monkeycraft.server;

import org.slf4j.Logger;

final class ShutdownSequence {
  @FunctionalInterface
  interface Action {
    void run() throws Exception;
  }

  static final class Step {
    private final String name;
    private final Action action;

    Step(String name, Action action) {
      this.name = name;
      this.action = action;
    }

    String name() {
      return name;
    }

    Action action() {
      return action;
    }
  }

  private ShutdownSequence() {}

  static void run(Logger logger, Step... steps) {
    for (Step step : steps) {
      try {
        step.action().run();
      } catch (Exception e) {
        logger.warn("Failed to stop {} during Monkeycraft shutdown", step.name(), e);
      }
    }
  }
}
