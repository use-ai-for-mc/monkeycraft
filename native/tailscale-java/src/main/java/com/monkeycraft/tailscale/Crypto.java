package com.monkeycraft.tailscale;

import com.iwebpp.crypto.TweetNaclFast;
import java.math.BigInteger;
import java.nio.*;
import java.security.*;
import java.security.spec.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import org.bouncycastle.crypto.digests.Blake2sDigest;

/** Standard primitives only. Protocol constructions mirror the upstream specifications. */
final class Crypto {
  static final SecureRandom RANDOM = new SecureRandom();
  static final byte[] EMPTY = new byte[0];

  static byte[] random(int n) {
    byte[] b = new byte[n];
    RANDOM.nextBytes(b);
    return b;
  }

  static byte[] privateKey() {
    byte[] k = random(32);
    k[0] &= 248;
    k[31] &= 127;
    k[31] |= 64;
    return k;
  }

  static byte[] publicKey(byte[] secret) throws GeneralSecurityException {
    byte[] base = new byte[32];
    base[0] = 9;
    return dh(secret, base);
  }

  static byte[] dh(byte[] secret, byte[] publicKey) throws GeneralSecurityException {
    if (secret.length != 32 || publicKey.length != 32)
      throw new InvalidKeyException("X25519 key length");
    byte[] big = publicKey.clone();
    big[31] &= 127;
    for (int i = 0; i < 16; i++) {
      byte t = big[i];
      big[i] = big[31 - i];
      big[31 - i] = t;
    }
    KeyFactory f = KeyFactory.getInstance("X25519");
    KeyAgreement a = KeyAgreement.getInstance("X25519");
    a.init(f.generatePrivate(new XECPrivateKeySpec(NamedParameterSpec.X25519, secret)));
    a.doPhase(
        f.generatePublic(new XECPublicKeySpec(NamedParameterSpec.X25519, new BigInteger(1, big))),
        true);
    return a.generateSecret(); // JCA rejects all-zero shared secrets.
  }

  static byte[] hash(byte[]... parts) {
    Blake2sDigest d = new Blake2sDigest(256);
    for (byte[] p : parts) d.update(p, 0, p.length);
    byte[] out = new byte[32];
    d.doFinal(out, 0);
    return out;
  }

  static byte[] mac(byte[] key, byte[]... parts) {
    byte[] k = key.length > 64 ? hash(key) : key, inner = new byte[64], outer = new byte[64];
    Arrays.fill(inner, (byte) 0x36);
    Arrays.fill(outer, (byte) 0x5c);
    for (int i = 0; i < k.length; i++) {
      inner[i] ^= k[i];
      outer[i] ^= k[i];
    }
    byte[][] data = new byte[parts.length + 1][];
    data[0] = inner;
    System.arraycopy(parts, 0, data, 1, parts.length);
    return hash(outer, hash(data));
  }

  static byte[][] kdf(byte[] chaining, byte[] input, int count) {
    byte[] temp = mac(chaining, input), prev = EMPTY;
    byte[][] out = new byte[count][];
    for (int i = 0; i < count; i++) {
      prev = mac(temp, prev, new byte[] {(byte) (i + 1)});
      out[i] = prev;
    }
    Arrays.fill(temp, (byte) 0);
    return out;
  }

  static byte[] keyedHash(byte[] key, int size, byte[] data) {
    Blake2sDigest d = new Blake2sDigest(key, size, null, null);
    d.update(data, 0, data.length);
    byte[] out = new byte[size];
    d.doFinal(out, 0);
    return out;
  }

  static byte[] aead(boolean seal, byte[] key, byte[] nonce, byte[] data, byte[] aad)
      throws GeneralSecurityException {
    Cipher c = Cipher.getInstance("ChaCha20-Poly1305");
    c.init(
        seal ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE,
        new SecretKeySpec(key, "ChaCha20"),
        new IvParameterSpec(nonce));
    if (aad.length > 0) c.updateAAD(aad);
    return c.doFinal(data);
  }

  static byte[] xaead(boolean seal, byte[] key, byte[] nonce, byte[] data, byte[] aad)
      throws GeneralSecurityException {
    var cipher = new org.bouncycastle.crypto.modes.XChaCha20Poly1305();
    cipher.init(
        seal,
        new org.bouncycastle.crypto.params.AEADParameters(
            new org.bouncycastle.crypto.params.KeyParameter(key), 128, nonce, aad));
    byte[] out = new byte[cipher.getOutputSize(data.length)];
    try {
      int n = cipher.processBytes(data, 0, data.length, out, 0);
      n += cipher.doFinal(out, n);
      return Arrays.copyOf(out, n);
    } catch (org.bouncycastle.crypto.InvalidCipherTextException e) {
      throw new AEADBadTagException("XChaCha authentication failed");
    }
  }

  static byte[] nonce(long counter, ByteOrder order) {
    return ByteBuffer.allocate(12).order(order).putInt(0).putLong(counter).array();
  }

  static byte[] box(byte[] secret, byte[] pub, byte[] plain) throws GeneralSecurityException {
    dh(secret, pub);
    byte[] n = random(24);
    return concat(n, new TweetNaclFast.Box(pub, secret).box(plain, n));
  }

  static byte[] openBox(byte[] secret, byte[] pub, byte[] sealed) throws GeneralSecurityException {
    if (sealed.length < 40) throw new GeneralSecurityException("short NaCl box");
    dh(secret, pub);
    byte[] p =
        new TweetNaclFast.Box(pub, secret)
            .open(Arrays.copyOfRange(sealed, 24, sealed.length), Arrays.copyOf(sealed, 24));
    if (p == null) throw new AEADBadTagException("NaCl box authentication failed");
    return p;
  }

  static byte[] concat(byte[]... a) {
    int n = 0;
    for (byte[] b : a) n += b.length;
    byte[] out = new byte[n];
    int p = 0;
    for (byte[] b : a) {
      System.arraycopy(b, 0, out, p, b.length);
      p += b.length;
    }
    return out;
  }

  static String hex(byte[] b) {
    return HexFormat.of().formatHex(b);
  }

  static byte[] key(String s, String prefix) {
    if (!s.startsWith(prefix)) throw new IllegalArgumentException("unexpected key type");
    byte[] k = HexFormat.of().parseHex(s.substring(prefix.length()));
    if (k.length != 32) throw new IllegalArgumentException("invalid key length");
    return k;
  }
}
