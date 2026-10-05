package com.monkeycraft.tailscale;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.handler.codec.http2.DefaultHttp2Headers;
import io.netty.handler.codec.http2.DefaultHttp2HeadersEncoder;
import java.nio.file.Path;

public final class DependencyChecks {
  public static void main(String[] args) throws Exception {
    var encoder = new DefaultHttp2HeadersEncoder();
    encoder.configuration().maxHeaderTableSize(0xffffffffL);
    if (encoder.configuration().maxHeaderTableSize() > 65_536)
      throw new AssertionError("Peer-controlled HPACK table has no small local bound");
    ByteBuf output = Unpooled.buffer();
    try {
      for (int i = 0; i < 10_000; i++) {
        output.clear();
        encoder.encodeHeaders(
            1,
            new DefaultHttp2Headers()
                .method("POST")
                .scheme("https")
                .authority("localhost")
                .path("/machine/map")
                .set("x-test-unique", "value-" + i),
            output);
      }
    } finally {
      output.release();
    }
    String source =
        Path.of(
                DefaultHttp2HeadersEncoder.class
                    .getProtectionDomain()
                    .getCodeSource()
                    .getLocation()
                    .toURI())
            .getFileName()
            .toString();
    System.out.println("DEPENDENCY_CHECKS_OK HTTP2=" + source + " bounded-HPACK-table");
  }
}
