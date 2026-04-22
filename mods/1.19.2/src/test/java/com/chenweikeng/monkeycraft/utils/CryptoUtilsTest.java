package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class CryptoUtilsTest {

  @Test
  void generateSaltReturnsBase64() {
    String salt = CryptoUtils.generateSalt();
    assertNotNull(salt);
    assertFalse(salt.isEmpty());
    assertDoesNotThrow(() -> java.util.Base64.getDecoder().decode(salt));
  }

  @Test
  void generateSaltIsUnique() {
    String salt1 = CryptoUtils.generateSalt();
    String salt2 = CryptoUtils.generateSalt();
    assertNotEquals(salt1, salt2);
  }

  @Test
  void computeHmacIsDeterministic() {
    String result1 = CryptoUtils.computeHmac("key", "data");
    String result2 = CryptoUtils.computeHmac("key", "data");
    assertEquals(result1, result2);
  }

  @Test
  void computeHmacDiffersWithDifferentKeys() {
    String result1 = CryptoUtils.computeHmac("key1", "data");
    String result2 = CryptoUtils.computeHmac("key2", "data");
    assertNotEquals(result1, result2);
  }

  @Test
  void computeHmacDiffersWithDifferentData() {
    String result1 = CryptoUtils.computeHmac("key", "data1");
    String result2 = CryptoUtils.computeHmac("key", "data2");
    assertNotEquals(result1, result2);
  }

  @Test
  void computeHmacReturnsBase64() {
    String result = CryptoUtils.computeHmac("password", "salt1salt2");
    assertNotNull(result);
    assertFalse(result.isEmpty());
    assertDoesNotThrow(() -> java.util.Base64.getDecoder().decode(result));
  }

  @Test
  void computeHmacThrowsOnEmptyKey() {
    assertThrows(IllegalArgumentException.class, () -> CryptoUtils.computeHmac("", "data"));
  }

  @Test
  void computeHmacHandlesEmptyData() {
    String result = CryptoUtils.computeHmac("key", "");
    assertNotNull(result);
    assertFalse(result.isEmpty());
  }

  @Test
  void computeHmacHandlesUnicodeInput() {
    String result = CryptoUtils.computeHmac("密码", "数据");
    assertNotNull(result);
    assertFalse(result.isEmpty());
  }

  @Test
  void authHandshakeSimulation() {
    String password = "test_password";
    String serverSalt = CryptoUtils.generateSalt();
    String clientSalt = CryptoUtils.generateSalt();

    String clientSignature = CryptoUtils.computeHmac(password, serverSalt + clientSalt);
    String expectedSignature = CryptoUtils.computeHmac(password, serverSalt + clientSalt);
    assertEquals(expectedSignature, clientSignature);

    String serverSignature = CryptoUtils.computeHmac(password, clientSalt + serverSalt);
    assertNotEquals(clientSignature, serverSignature);
  }
}
