package com.chenweikeng.monkeycraft.server;

import org.slf4j.Logger;

final class ShutdownSequence {
  @FunctionalInterface
  interface Action {
    void run() throws Exception;
  }

  record Step(String name, Action action) {}

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
