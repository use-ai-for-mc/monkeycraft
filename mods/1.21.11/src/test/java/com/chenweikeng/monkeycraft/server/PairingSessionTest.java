package com.chenweikeng.monkeycraft.server;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class PairingSessionTest {

  @Test
  void generateCodeIsEightCrockfordChars() {
    String code = PairingSession.generateCode();
    assertEquals(8, code.length());
    assertTrue(code.matches("[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}"));
  }

  @Test
  void displayCodeInsertsHyphen() {
    assertEquals("ABCD-2345", PairingSession.displayCode("ABCD2345"));
  }

  @Test
  void codesAreUnique() {
    assertNotEquals(PairingSession.generateCode(), PairingSession.generateCode());
  }
}
