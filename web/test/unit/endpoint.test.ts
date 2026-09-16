import { describe, expect, it } from "vitest";
import { serverHost, serverToWsUrl, webOriginServer } from "../../src/transport/endpoint.ts";

describe("serverToWsUrl", () => {
  it("maps https to wss and http to ws", () => {
    expect(serverToWsUrl("https://mac.tail977122.ts.net:10800")).toBe(
      "wss://mac.tail977122.ts.net:10800",
    );
    expect(serverToWsUrl("http://127.0.0.1:9600")).toBe("ws://127.0.0.1:9600");
  });

  it("keeps explicit ws and wss", () => {
    expect(serverToWsUrl("ws://a:1")).toBe("ws://a:1");
    expect(serverToWsUrl("wss://a")).toBe("wss://a");
  });

  it("uses plaintext ws for host:port and wss for bare hosts", () => {
    expect(serverToWsUrl(" 192.168.0.3:9600 ")).toBe("ws://192.168.0.3:9600");
    expect(serverToWsUrl("100.64.1.2:9600")).toBe("ws://100.64.1.2:9600");
    expect(serverToWsUrl("pc.tailnet.ts.net")).toBe("wss://pc.tailnet.ts.net");
    expect(serverToWsUrl("example.com:443")).toBe("ws://example.com:443");
  });
});

describe("webOriginServer", () => {
  it("returns the origin including the port", () => {
    expect(webOriginServer(new URL("https://mac.tail977122.ts.net:10800/play?x=1"))).toBe(
      "https://mac.tail977122.ts.net:10800",
    );
    expect(webOriginServer(new URL("http://127.0.0.1:9600/"))).toBe("http://127.0.0.1:9600");
  });

  it("is empty without a host", () => {
    expect(webOriginServer(new URL("file:///index.html"))).toBe("");
  });
});

describe("serverHost", () => {
  it("extracts the hostname", () => {
    expect(serverHost("192.168.0.3:9600")).toBe("192.168.0.3");
    expect(serverHost("[::1]:9600")).toBe("[::1]");
    expect(serverHost("https://x.ts.net")).toBe("x.ts.net");
  });
});
