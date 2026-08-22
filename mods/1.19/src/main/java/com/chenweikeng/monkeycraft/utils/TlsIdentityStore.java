package com.chenweikeng.monkeycraft.utils;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Provider;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Date;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.ExtendedKeyUsage;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.KeyPurposeId;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.OperatorCreationException;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

public final class TlsIdentityStore {
  private static final String ALIAS = "monkeycraft";
  private static final char[] STORE_PASSWORD = "monkeycraft-local-tls".toCharArray();
  private static final SecureRandom RANDOM = new SecureRandom();

  private TlsIdentityStore() {}

  public static TlsIdentity loadOrCreate(Path path) throws IOException, GeneralSecurityException {
    KeyStore keyStore = KeyStore.getInstance("PKCS12");
    if (Files.exists(path)) {
      restrictPermissions(path);
      try (InputStream input = Files.newInputStream(path)) {
        keyStore.load(input, STORE_PASSWORD);
      }
    } else {
      Files.createDirectories(path.getParent());
      keyStore.load(null, STORE_PASSWORD);
      KeyPair keyPair = generateKeyPair();
      X509Certificate certificate = generateCertificate(keyPair);
      keyStore.setKeyEntry(
          ALIAS, keyPair.getPrivate(), STORE_PASSWORD, new X509Certificate[] {certificate});
      writeAtomically(path, keyStore);
    }

    PrivateKey privateKey = (PrivateKey) keyStore.getKey(ALIAS, STORE_PASSWORD);
    X509Certificate certificate = (X509Certificate) keyStore.getCertificate(ALIAS);
    if (privateKey == null || certificate == null) {
      throw new GeneralSecurityException("TLS identity is missing its key or certificate");
    }
    verifyKeyPair(privateKey, certificate);

    KeyManagerFactory keyManagers =
        KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
    keyManagers.init(keyStore, STORE_PASSWORD);
    SSLContext sslContext = SSLContext.getInstance("TLS");
    sslContext.init(keyManagers.getKeyManagers(), null, RANDOM);
    return new TlsIdentity(sslContext, fingerprint(certificate));
  }

  private static KeyPair generateKeyPair() throws GeneralSecurityException {
    KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
    generator.initialize(new ECGenParameterSpec("secp256r1"), RANDOM);
    return generator.generateKeyPair();
  }

  private static X509Certificate generateCertificate(KeyPair keyPair)
      throws IOException, GeneralSecurityException {
    Instant now = Instant.now();
    X500Name subject = new X500Name("CN=MonkeyCraft Local Server");
    JcaX509v3CertificateBuilder builder =
        new JcaX509v3CertificateBuilder(
            subject,
            new BigInteger(160, RANDOM).abs(),
            Date.from(now.minus(1, ChronoUnit.DAYS)),
            Date.from(now.plus(3650, ChronoUnit.DAYS)),
            subject,
            keyPair.getPublic());
    JcaX509ExtensionUtils extensions = new JcaX509ExtensionUtils();
    builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(false));
    builder.addExtension(Extension.keyUsage, true, new KeyUsage(KeyUsage.digitalSignature));
    builder.addExtension(
        Extension.extendedKeyUsage, false, new ExtendedKeyUsage(KeyPurposeId.id_kp_serverAuth));
    builder.addExtension(
        Extension.subjectKeyIdentifier,
        false,
        extensions.createSubjectKeyIdentifier(keyPair.getPublic()));
    builder.addExtension(
        Extension.authorityKeyIdentifier,
        false,
        extensions.createAuthorityKeyIdentifier(keyPair.getPublic()));

    Provider provider = new BouncyCastleProvider();
    try {
      ContentSigner signer =
          new JcaContentSignerBuilder("SHA256withECDSA")
              .setProvider(provider)
              .build(keyPair.getPrivate());
      X509Certificate certificate =
          new JcaX509CertificateConverter()
              .setProvider(provider)
              .getCertificate(builder.build(signer));
      certificate.verify(keyPair.getPublic());
      return certificate;
    } catch (OperatorCreationException e) {
      throw new GeneralSecurityException("Failed to sign TLS certificate", e);
    }
  }

  private static void verifyKeyPair(PrivateKey privateKey, X509Certificate certificate)
      throws GeneralSecurityException {
    byte[] challenge = new byte[32];
    RANDOM.nextBytes(challenge);
    Signature signature = Signature.getInstance("SHA256withECDSA");
    signature.initSign(privateKey, RANDOM);
    signature.update(challenge);
    byte[] signed = signature.sign();
    signature.initVerify(certificate.getPublicKey());
    signature.update(challenge);
    if (!signature.verify(signed)) {
      throw new GeneralSecurityException("TLS private key does not match its certificate");
    }
  }

  private static void writeAtomically(Path path, KeyStore keyStore)
      throws IOException, GeneralSecurityException {
    Path temp = Files.createTempFile(path.getParent(), "monkeycraft-tls-", ".p12");
    try {
      try (OutputStream output = Files.newOutputStream(temp)) {
        keyStore.store(output, STORE_PASSWORD);
      }
      restrictPermissions(temp);
      try {
        Files.move(temp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
      } catch (AtomicMoveNotSupportedException e) {
        Files.move(temp, path, StandardCopyOption.REPLACE_EXISTING);
      }
      restrictPermissions(path);
    } finally {
      Files.deleteIfExists(temp);
    }
  }

  private static void restrictPermissions(Path path) throws IOException {
    try {
      Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rw-------"));
    } catch (UnsupportedOperationException ignored) {
    }
  }

  private static String fingerprint(X509Certificate certificate) throws GeneralSecurityException {
    byte[] digest = MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded());
    return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
  }

  public record TlsIdentity(SSLContext sslContext, String certificateSha256) {}
}
