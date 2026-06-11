package com.chenweikeng.monkeycraft.utils;

import java.util.List;

public final class CommandPatterns {
  private CommandPatterns() {}

  public static boolean matches(String command, List<String> patterns) {
    if (patterns == null || patterns.isEmpty()) {
      return false;
    }
    String cmd = command.startsWith("/") ? command.substring(1) : command;
    cmd = cmd.trim();
    String cmdLower = cmd.toLowerCase();
    int colon = cmdLower.indexOf(':');
    int firstSpace = cmdLower.indexOf(' ');
    if (colon >= 0 && (firstSpace < 0 || colon < firstSpace)) {
      cmdLower = cmdLower.substring(colon + 1);
    }
    for (String pattern : patterns) {
      if (pattern == null || pattern.isEmpty()) continue;
      String patternLower = pattern.toLowerCase().trim();
      if (patternLower.equals("*")) {
        return true;
      }
      if (patternLower.endsWith(" *")) {
        String prefix = patternLower.substring(0, patternLower.length() - 2);
        if (cmdLower.equals(prefix) || cmdLower.startsWith(prefix + " ")) {
          return true;
        }
      } else {
        if (cmdLower.equals(patternLower)) {
          return true;
        }
      }
    }
    return false;
  }
}
