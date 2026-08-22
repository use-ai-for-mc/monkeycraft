package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class TlsIdentityStoreTest {
  @TempDir Path tempDir;

  @Test
  void createsAndReloadsStableIdentity() throws Exception {
    Path path = tempDir.resolve("monkeycraft-tls.p12");

    TlsIdentityStore.TlsIdentity created = TlsIdentityStore.loadOrCreate(path);
    TlsIdentityStore.TlsIdentity reloaded = TlsIdentityStore.loadOrCreate(path);

    assertTrue(Files.isRegularFile(path));
    assertNotNull(created.sslContext());
    assertEquals(43, created.certificateSha256().length());
    assertEquals(created.certificateSha256(), reloaded.certificateSha256());
  }

  @Test
  void repairsExistingIdentityPermissions() throws Exception {
    assumeTrue(tempDir.getFileSystem().supportedFileAttributeViews().contains("posix"));
    Path path = tempDir.resolve("monkeycraft-tls.p12");
    TlsIdentityStore.loadOrCreate(path);
    Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rw-r--r--"));

    TlsIdentityStore.loadOrCreate(path);

    assertEquals(PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(path));
  }

  @Test
  void rejectsCorruptIdentity() throws Exception {
    Path path = tempDir.resolve("monkeycraft-tls.p12");
    Files.writeString(path, "not a keystore");

    assertThrows(Exception.class, () -> TlsIdentityStore.loadOrCreate(path));
  }

  @Test
  void sslContextServesThePinnedCertificate() throws Exception {
    TlsIdentityStore.TlsIdentity identity =
        TlsIdentityStore.loadOrCreate(tempDir.resolve("monkeycraft-tls.p12"));
    try (SSLServerSocket server =
        (SSLServerSocket) identity.sslContext().getServerSocketFactory().createServerSocket(0)) {
      CompletableFuture<Void> accepting =
          CompletableFuture.runAsync(
              () -> {
                try (SSLSocket socket = (SSLSocket) server.accept()) {
                  socket.startHandshake();
                } catch (Exception e) {
                  throw new RuntimeException(e);
                }
              });

      SSLContext clientContext = SSLContext.getInstance("TLS");
      clientContext.init(null, new TrustManager[] {trustAllCertificates()}, null);
      try (SSLSocket client =
          (SSLSocket)
              clientContext.getSocketFactory().createSocket("127.0.0.1", server.getLocalPort())) {
        client.startHandshake();
        X509Certificate certificate =
            (X509Certificate) client.getSession().getPeerCertificates()[0];
        String fingerprint =
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(
                    MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
        assertEquals(identity.certificateSha256(), fingerprint);
      }
      accepting.get(5, TimeUnit.SECONDS);
    }
  }

  private static X509TrustManager trustAllCertificates() {
    return new X509TrustManager() {
      @Override
      public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
      }

      @Override
      public void checkClientTrusted(X509Certificate[] chain, String authType) {}

      @Override
      public void checkServerTrusted(X509Certificate[] chain, String authType) {}
    };
  }
}
