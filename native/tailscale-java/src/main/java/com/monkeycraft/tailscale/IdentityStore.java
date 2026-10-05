package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.io.*;
import java.nio.*;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.util.*;

/** Single-owner, atomic local identity storage. Private keys are never part of status events. */
final class IdentityStore implements AutoCloseable {
  private final Path directory, file;
  private final FileChannel lockChannel;
  private final FileLock lock;
  byte[] machine, node, oldNode;
  boolean loggedOut;

  IdentityStore(Path directory) throws Exception {
    this.directory = directory.toAbsolutePath();
    this.file = this.directory.resolve("identity.json");
    Files.createDirectories(this.directory);
    if (Files.isSymbolicLink(this.directory))
      throw new IOException("state directory must not be a symlink");
    restrict(this.directory, true);
    Path lockPath = this.directory.resolve("identity.lock");
    if (Files.isSymbolicLink(lockPath)) throw new IOException("state lock must not be a symlink");
    lockChannel =
        FileChannel.open(
            lockPath,
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE,
            LinkOption.NOFOLLOW_LINKS);
    restrict(lockPath, false);
    FileLock acquired;
    try {
      acquired = lockChannel.tryLock();
    } catch (OverlappingFileLockException e) {
      lockChannel.close();
      throw new IOException("state directory is already in use");
    }
    if (acquired == null) {
      lockChannel.close();
      throw new IOException("state directory is already in use");
    }
    lock = acquired;
    try {
      if (Files.exists(file, LinkOption.NOFOLLOW_LINKS)) {
        if (Files.isSymbolicLink(file) || Files.size(file) > 16_384)
          throw new IOException("invalid identity file");
        restrict(file, false);
        JsonObject o = JsonParser.parseString(Files.readString(file)).getAsJsonObject();
        if (o.get("version").getAsInt() != 1) throw new IOException("unsupported identity version");
        machine = Crypto.key(o.get("machine").getAsString(), "private:");
        node = Crypto.key(o.get("node").getAsString(), "private:");
        oldNode = o.has("oldNode") ? Crypto.key(o.get("oldNode").getAsString(), "public:") : null;
        loggedOut = o.get("loggedOut").getAsBoolean();
      } else {
        machine = Crypto.privateKey();
        node = Crypto.privateKey();
        save();
      }
    } catch (Exception e) {
      lock.release();
      lockChannel.close();
      throw e;
    }
  }

  synchronized void rotateNode() throws Exception {
    oldNode = Crypto.publicKey(node);
    Arrays.fill(node, (byte) 0);
    node = Crypto.privateKey();
    save();
  }

  synchronized void save() throws IOException {
    JsonObject o = new JsonObject();
    o.addProperty("version", 1);
    o.addProperty("machine", "private:" + Crypto.hex(machine));
    o.addProperty("node", "private:" + Crypto.hex(node));
    o.addProperty("loggedOut", loggedOut);
    if (oldNode != null) o.addProperty("oldNode", "public:" + Crypto.hex(oldNode));
    Path temporary = Files.createTempFile(directory, "identity-", ".tmp");
    try {
      restrict(temporary, false);
      try (FileChannel c =
          FileChannel.open(
              temporary, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
        ByteBuffer b = StandardCharsets.UTF_8.encode(o.toString());
        while (b.hasRemaining()) c.write(b);
        c.force(true);
      }
      Files.move(
          temporary, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    } finally {
      Files.deleteIfExists(temporary);
    }
  }

  private static void restrict(Path path, boolean dir) throws IOException {
    PosixFileAttributeView posix =
        Files.getFileAttributeView(path, PosixFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
    if (posix != null) {
      posix.setPermissions(PosixFilePermissions.fromString(dir ? "rwx------" : "rw-------"));
      return;
    }
    AclFileAttributeView acl =
        Files.getFileAttributeView(path, AclFileAttributeView.class, LinkOption.NOFOLLOW_LINKS);
    if (acl == null) throw new IOException("state filesystem lacks private-file permissions");
    AclEntry.Builder entry =
        AclEntry.newBuilder()
            .setType(AclEntryType.ALLOW)
            .setPrincipal(acl.getOwner())
            .setPermissions(EnumSet.allOf(AclEntryPermission.class));
    if (dir) entry.setFlags(AclEntryFlag.DIRECTORY_INHERIT, AclEntryFlag.FILE_INHERIT);
    acl.setAcl(List.of(entry.build()));
  }

  public synchronized void close() throws IOException {
    if (machine != null) Arrays.fill(machine, (byte) 0);
    if (node != null) Arrays.fill(node, (byte) 0);
    lock.release();
    lockChannel.close();
  }
}
