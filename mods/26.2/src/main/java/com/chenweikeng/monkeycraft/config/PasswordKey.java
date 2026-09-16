package com.chenweikeng.monkeycraft.config;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.Objects;

public final class PasswordKey {
  private static final int ID_BYTES = 12;

  private PasswordKey() {}

  public static String newId() {
    byte[] bytes = new byte[ID_BYTES];
    new SecureRandom().nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  public static String idAfterChange(
      String previousPassword, String nextPassword, String previousId) {
    if (Objects.equals(previousPassword, nextPassword)
        && previousId != null
        && !previousId.isBlank()) {
      return previousId;
    }
    return newId();
  }
}
