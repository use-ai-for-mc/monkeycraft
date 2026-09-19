// Server address rules. These match the Flutter client so that addresses users
// already know keep working (see docs/LEGACY_CLIENT_NOTES.md).

const TRAILING_PORT = /:\d+$/;

/** Turn a user-entered server string into a WebSocket URL. */
export function serverToWsUrl(input: string): string {
  const s = input.trim();
  if (s.startsWith("https://")) return `wss://${s.slice("https://".length)}`;
  if (s.startsWith("http://")) return `ws://${s.slice("http://".length)}`;
  if (s.startsWith("ws://") || s.startsWith("wss://")) return s;
  if (TRAILING_PORT.test(s)) return `ws://${s}`;
  return `wss://${s}`;
}

export function hostedWebClient(): boolean {
  return import.meta.env.VITE_MONKEYCRAFT_HOSTED === "true";
}

/** Default server for a page served by the mod: its own origin, or "" when there is no host. */
export function webOriginServer(page: URL, hosted = hostedWebClient()): string {
  if (hosted) return "";
  return page.host === "" ? "" : page.origin;
}

export function insecureWebSocketMessage(page: URL, server: string): string | null {
  if (page.protocol !== "https:") return null;
  try {
    if (new URL(serverToWsUrl(server)).protocol === "ws:") {
      return "This HTTPS page cannot connect to a bare ws:// server. Use a secure wss:// address, such as your Tailscale Serve HTTPS address.";
    }
  } catch {
    return null;
  }
  return null;
}

/** Hostname of a server string, or null when it cannot be parsed. */
export function serverHost(input: string): string | null {
  try {
    return new URL(serverToWsUrl(input)).hostname;
  } catch {
    return null;
  }
}
