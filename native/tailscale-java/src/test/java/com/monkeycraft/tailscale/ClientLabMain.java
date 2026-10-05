package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import javax.net.ssl.*;

/** Local integration fixture only. Trusts exactly the supplied local DERP certificate. */
public final class ClientLabMain {
  public static void main(String[] args) throws Exception {
    java.security.cert.Certificate cert;
    try (InputStream in = Files.newInputStream(Path.of(args[3]))) {
      cert = CertificateFactory.getInstance("X.509").generateCertificate(in);
    }
    KeyStore trust = KeyStore.getInstance(KeyStore.getDefaultType());
    trust.load(null, null);
    trust.setCertificateEntry("local-derp", cert);
    TrustManagerFactory tm =
        TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
    tm.init(trust);
    SSLContext tls = SSLContext.getInstance("TLS");
    tls.init(null, tm.getTrustManagers(), null);
    Gson gson = new Gson();
    PrintWriter out = new PrintWriter(System.out, true);
    var config =
        new TailscaleClient.Config(
            Path.of(args[1]),
            URI.create(args[0]),
            "java-lab-client",
            9600,
            new InetSocketAddress("127.0.0.1", Integer.parseInt(args[2])));
    try (TailscaleClient client =
        new TailscaleClient(
            config,
            s -> out.println(gson.toJson(s)),
            tls.getSocketFactory(),
            args.length > 4 && args[4].equals("derp"),
            true)) {
      client.start();
      try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in))) {
        String command;
        while ((command = input.readLine()) != null) {
          switch (command) {
            case "udp-down" -> client.labDropUdp(true);
            case "udp-up" -> client.labDropUdp(false);
            case "status" -> out.println(gson.toJson(client.status()));
            case "stop" -> client.stop();
            case "start" -> client.start();
            case "logout" -> client.logout();
            case "login" -> client.login();
            case "close" -> {
              return;
            }
            default -> throw new IllegalArgumentException("unknown lab command");
          }
        }
      }
    }
  }
}
