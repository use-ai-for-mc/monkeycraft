package com.monkeycraft.tailscale;

import com.google.gson.*;
import java.net.URI;

public final class ControlProbe {
  public static void main(String[] args) throws Exception {
    byte[] machine = Crypto.privateKey(), node = Crypto.privateKey();
    try (ControlHttp h = new ControlHttp(URI.create(args[0]), machine)) {
      JsonObject r = new JsonObject();
      r.addProperty("Version", ControlHttp.CAPABILITY);
      r.addProperty("NodeKey", "nodekey:" + Crypto.hex(Crypto.publicKey(node)));
      JsonObject hi = new JsonObject();
      hi.addProperty("Hostname", "java-control-probe");
      hi.addProperty("OS", "java");
      r.add("Hostinfo", hi);
      if (args.length < 2) {
        JsonObject response = h.post("/machine/register", r);
        if (!response.get("MachineAuthorized").getAsBoolean())
          throw new AssertionError("register not authorized");
        r.addProperty("Stream", false);
        r.addProperty("DiscoKey", "discokey:" + Crypto.hex(Crypto.publicKey(Crypto.privateKey())));
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        h.request("/machine/map", r, out::write);
        byte[] bytes = out.toByteArray();
        int len =
            java.nio.ByteBuffer.wrap(bytes, 0, 4).order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt();
        if (bytes.length != len + 4) throw new AssertionError("map length");
        JsonObject map =
            JsonParser.parseString(
                    new String(bytes, 4, len, java.nio.charset.StandardCharsets.UTF_8))
                .getAsJsonObject();
        if (!map.has("Node")) throw new AssertionError("no map node");
      } else {
        // Enough data for multiple Noise records, HPACK and flow-control window updates.
        JsonObject large = new JsonObject();
        large.addProperty("payload", "x".repeat(250_000));
        JsonObject echo = h.post("/lab/echo", large);
        if (!echo.equals(large)) throw new AssertionError("large HTTP2 echo");
      }
      System.out.println(
          "CONTROL_OK java="
              + System.getProperty("java.version")
              + " Noise-IK register map HTTP2-250KB");
    }
  }
}
