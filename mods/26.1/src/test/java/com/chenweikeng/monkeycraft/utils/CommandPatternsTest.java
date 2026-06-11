package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import org.junit.jupiter.api.Test;

class CommandPatternsTest {

  @Test
  void namespacedCommandCannotBypassDenylist() {
    List<String> denylist = List.of("op *", "deop *");
    assertTrue(CommandPatterns.matches("/minecraft:op griefer", denylist));
    assertTrue(CommandPatterns.matches("minecraft:op griefer", denylist));
    assertTrue(CommandPatterns.matches("/MINECRAFT:OP griefer", denylist));
    assertTrue(CommandPatterns.matches("/minecraft:deop victim", denylist));
  }

  @Test
  void wildcardPatternMatchesRootAndArguments() {
    List<String> patterns = List.of("op *");
    assertTrue(CommandPatterns.matches("/op player", patterns));
    assertTrue(CommandPatterns.matches("/op", patterns));
    assertTrue(CommandPatterns.matches("/OP Player", patterns));
  }

  @Test
  void wildcardPatternDoesNotMatchUnrelatedPrefix() {
    List<String> patterns = List.of("op *");
    assertFalse(CommandPatterns.matches("/opera house", patterns));
    assertFalse(CommandPatterns.matches("/opera", patterns));
  }

  @Test
  void starMatchesEverything() {
    List<String> patterns = List.of("*");
    assertTrue(CommandPatterns.matches("/anything at all", patterns));
    assertTrue(CommandPatterns.matches("x", patterns));
  }

  @Test
  void exactPatternRequiresFullCommand() {
    List<String> patterns = List.of("spawn");
    assertTrue(CommandPatterns.matches("/spawn", patterns));
    assertTrue(CommandPatterns.matches("/minecraft:spawn", patterns));
    assertFalse(CommandPatterns.matches("/spawn here", patterns));
    assertFalse(CommandPatterns.matches("/spawnpoint", patterns));
  }

  @Test
  void colonInsideArgumentsIsNotANamespace() {
    List<String> patterns = List.of("msg *");
    assertTrue(CommandPatterns.matches("/msg a:b hello", patterns));
    assertFalse(CommandPatterns.matches("/tell a:msg hi", patterns));
  }

  @Test
  void emptyInputs() {
    assertFalse(CommandPatterns.matches("/op x", List.of()));
    assertFalse(CommandPatterns.matches("/op x", null));
  }
}
