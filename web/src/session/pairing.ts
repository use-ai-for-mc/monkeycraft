// Client-side guess at whether the server will offer pairing, used only to
// pick the default login mode. The server's HELLO.pairing flag is authoritative.
// Mirrors the Flutter rules (docs/LEGACY_CLIENT_NOTES.md) and the server's
// NetworkUtils.isPairingAllowed: IP literals only, no hostnames.

import { serverHost } from "../transport/endpoint.ts";

function ipv4(host: string): [number, number, number, number] | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return null;
  const parts = m.slice(1).map(Number) as [number, number, number, number];
  return parts.every((p) => p <= 255) ? parts : null;
}

export function isPairingEligibleHost(rawHost: string): boolean {
  let host = rawHost.trim().toLowerCase();
  if (host.startsWith("[") && host.endsWith("]")) host = host.slice(1, -1);
  if (host.endsWith(".")) host = host.slice(0, -1);
  if (host === "") return false;
  if (host === "localhost" || host === "::1" || host === "0:0:0:0:0:0:0:1") return true;
  const v4 = ipv4(host);
  if (v4) {
    const [a, b] = v4;
    if (a === 127 || a === 10) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 169 && b === 254) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
    return false;
  }
  if (host.includes(":")) {
    return host.startsWith("fe80:") || host.startsWith("fc") || host.startsWith("fd");
  }
  return false;
}

export function isPairingEligibleServer(server: string): boolean {
  const host = serverHost(server);
  return host !== null && isPairingEligibleHost(host);
}

export type LoginMode = "password" | "pair";

export function defaultLoginMode(hasPassword: boolean, server: string): LoginMode {
  if (hasPassword) return "password";
  return isPairingEligibleServer(server) ? "pair" : "password";
}
