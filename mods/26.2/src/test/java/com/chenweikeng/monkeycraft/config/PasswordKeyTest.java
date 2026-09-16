package com.chenweikeng.monkeycraft.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class PasswordKeyTest {

  @Test
  void newIdIsUrlSafeAndUnique() {
    String id = PasswordKey.newId();
    assertTrue(id.matches("[A-Za-z0-9_-]{16}"));
    assertNotEquals(id, PasswordKey.newId());
  }

  @Test
  void idAfterChangeRotatesOnlyWhenPasswordChanges() {
    String id = PasswordKey.newId();
    assertEquals(id, PasswordKey.idAfterChange("same", "same", id));
    assertNotEquals(id, PasswordKey.idAfterChange("old", "new", id));
    assertNotEquals(id, PasswordKey.idAfterChange("old", "old", ""));
  }
}
