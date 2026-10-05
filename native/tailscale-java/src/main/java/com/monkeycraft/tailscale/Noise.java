package com.monkeycraft.tailscale;

import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

/** Tailscale controlbase Noise IK framing, derived from tailscale v1.102.3 (BSD-3-Clause). */
final class Noise implements Closeable {
  private final InputStream in;
  private final OutputStream out;
  private final Closeable transport;
  private byte[] tx, rx;
  private long txNonce, rxNonce;
  private volatile boolean closed;
  final byte[] handshakeHash;

  private Noise(InputStream in, OutputStream out, Closeable transport, byte[][] keys, byte[] hash) {
    this.in = in;
    this.out = out;
    this.transport = transport;
    tx = keys[0];
    rx = keys[1];
    handshakeHash = hash.clone();
  }

  static final class Initiation {
    private byte[]
        h = Crypto.hash("Noise_IK_25519_ChaChaPoly_BLAKE2s".getBytes(StandardCharsets.US_ASCII)),
        ck = h.clone();
    private final byte[] machine, ephemeral = Crypto.privateKey();
    private boolean used;
    final byte[] message;

    Initiation(byte[] machine, byte[] control, int version) throws GeneralSecurityException {
      this.machine = machine.clone();
      mixHash(("Tailscale Control Protocol v" + version).getBytes(StandardCharsets.US_ASCII));
      mixHash(control);
      byte[] pub = Crypto.publicKey(ephemeral);
      mixHash(pub);
      byte[] encrypted = encrypt(mixDH(ephemeral, control), Crypto.publicKey(machine));
      byte[] tag = encrypt(mixDH(machine, control), Crypto.EMPTY);
      message =
          ByteBuffer.allocate(101)
              .putShort((short) version)
              .put((byte) 1)
              .putShort((short) 96)
              .put(pub)
              .put(encrypted)
              .put(tag)
              .array();
    }

    private void mixHash(byte[] b) {
      h = Crypto.hash(h, b);
    }

    private byte[] mixDH(byte[] a, byte[] b) throws GeneralSecurityException {
      byte[][] k = Crypto.kdf(ck, Crypto.dh(a, b), 2);
      ck = k[0];
      return k[1];
    }

    private byte[] encrypt(byte[] key, byte[] plain) throws GeneralSecurityException {
      byte[] c = Crypto.aead(true, key, new byte[12], plain, h);
      mixHash(c);
      return c;
    }

    Noise finish(InputStream in, OutputStream out, Closeable transport) throws IOException {
      if (used) throw new IOException("handshake already consumed");
      used = true;
      try {
        byte[] header = readExactly(in, 3);
        int len = Short.toUnsignedInt(ByteBuffer.wrap(header, 1, 2).getShort());
        if (header[0] != 2 || len != 48) throw new IOException("invalid Noise response header");
        byte[] response = readExactly(in, 48), remote = Arrays.copyOf(response, 32);
        mixHash(remote);
        mixDH(ephemeral, remote);
        byte[] key = mixDH(machine, remote), tag = Arrays.copyOfRange(response, 32, 48);
        Crypto.aead(false, key, new byte[12], tag, h);
        mixHash(tag);
        return new Noise(in, out, transport, Crypto.kdf(ck, Crypto.EMPTY, 2), h);
      } catch (GeneralSecurityException e) {
        transport.close();
        throw new IOException("Noise authentication failed", e);
      } finally {
        Arrays.fill(machine, (byte) 0);
        Arrays.fill(ephemeral, (byte) 0);
        Arrays.fill(ck, (byte) 0);
      }
    }
  }

  synchronized void write(byte[] data) throws IOException {
    if (closed) throw new IOException("Noise closed");
    try {
      for (int offset = 0; offset < data.length; ) {
        if (txNonce == -1L) throw new IOException("Noise nonce exhausted");
        int n = Math.min(4077, data.length - offset);
        // Controlbase deliberately uses a big-endian counter; WireGuard uses little endian.
        byte[] cipher =
            Crypto.aead(
                true,
                tx,
                Crypto.nonce(txNonce++, ByteOrder.BIG_ENDIAN),
                Arrays.copyOfRange(data, offset, offset + n),
                Crypto.EMPTY);
        out.write(ByteBuffer.allocate(3).put((byte) 4).putShort((short) cipher.length).array());
        out.write(cipher);
        offset += n;
      }
      out.flush();
    } catch (GeneralSecurityException | IOException e) {
      close();
      throw new IOException("Noise write failed", e);
    }
  }

  byte[] read() throws IOException {
    if (closed) throw new IOException("Noise closed");
    try {
      byte[] header = readExactly(in, 3);
      int n = Short.toUnsignedInt(ByteBuffer.wrap(header, 1, 2).getShort());
      if (header[0] != 4 || n < 16 || n > 4093 || rxNonce == -1L)
        throw new IOException("invalid Noise record");
      return Crypto.aead(
          false,
          rx,
          Crypto.nonce(rxNonce++, ByteOrder.BIG_ENDIAN),
          readExactly(in, n),
          Crypto.EMPTY);
    } catch (GeneralSecurityException | IOException e) {
      close();
      throw new IOException("Noise read failed", e);
    }
  }

  InputStream input() {
    return new InputStream() {
      private byte[] current = Crypto.EMPTY;
      private int p;

      public int read() throws IOException {
        while (p == current.length) {
          current = Noise.this.read();
          p = 0;
        }
        return Byte.toUnsignedInt(current[p++]);
      }

      public int read(byte[] b, int off, int len) throws IOException {
        if (len == 0) return 0;
        while (p == current.length) {
          current = Noise.this.read();
          p = 0;
        }
        int n = Math.min(len, current.length - p);
        System.arraycopy(current, p, b, off, n);
        p += n;
        return n;
      }
    };
  }

  static byte[] readExactly(InputStream in, int n) throws IOException {
    byte[] b = in.readNBytes(n);
    if (b.length != n) throw new EOFException("truncated protocol frame");
    return b;
  }

  public void close() throws IOException {
    closed = true;
    transport.close();
  }
}
