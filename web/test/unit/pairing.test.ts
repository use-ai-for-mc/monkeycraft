import { describe, expect, it } from "vitest";
import {
  defaultLoginMode,
  isPairingEligibleHost,
  isPairingEligibleServer,
} from "../../src/session/pairing.ts";

describe("isPairingEligibleHost", () => {
  it("accepts loopback, private, link-local, CGNAT and IPv6 local ranges", () => {
    for (const h of [
      "localhost",
      "127.0.0.1",
      "127.255.255.255",
      "10.1.2.3",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.0.3",
      "169.254.1.1",
      "100.64.0.1",
      "100.127.255.255",
      "::1",
      "[::1]",
      "fe80::1",
      "fd7a:115c:a1e0::1",
      "LOCALHOST.",
    ]) {
      expect(isPairingEligibleHost(h), h).toBe(true);
    }
  });

  it("rejects public addresses and every hostname", () => {
    for (const h of [
      "",
      "8.8.8.8",
      "100.63.255.255",
      "100.128.0.1",
      "172.32.0.1",
      "192.169.0.1",
      "256.1.1.1",
      "desk.tail1234.ts.net",
      "example.com",
      "2001:db8::1",
    ]) {
      expect(isPairingEligibleHost(h), h).toBe(false);
    }
  });
});

describe("isPairingEligibleServer / defaultLoginMode", () => {
  it("parses the host out of a server string", () => {
    expect(isPairingEligibleServer("192.168.0.3:9600")).toBe(true);
    expect(isPairingEligibleServer("https://mac.tail977122.ts.net:10800")).toBe(false);
    expect(isPairingEligibleServer("http://100.64.1.2:9600")).toBe(true);
    expect(isPairingEligibleServer("")).toBe(false);
  });

  it("prefers a saved password, then pairing where eligible", () => {
    expect(defaultLoginMode(true, "192.168.0.3:9600")).toBe("password");
    expect(defaultLoginMode(false, "192.168.0.3:9600")).toBe("pair");
    expect(defaultLoginMode(false, "https://x.ts.net")).toBe("password");
  });
});
