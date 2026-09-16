// In-memory WebSocket stand-in for Connection tests.

import type { SocketLike } from "../../src/transport/connection.ts";

type Listener = (...args: never[]) => void;

export class FakeSocket implements SocketLike {
  binaryType = "blob";
  readyState = 0;
  readonly sent: string[] = [];
  private readonly listeners = new Map<string, Listener[]>();
  closedWith: { code: number | undefined; reason: string | undefined } | null = null;

  constructor(readonly url: string) {}

  addEventListener(type: string, listener: Listener): void {
    const list = this.listeners.get(type) ?? [];
    list.push(listener);
    this.listeners.set(type, list);
  }

  send(data: string): void {
    if (this.readyState !== 1) throw new Error("socket not open");
    this.sent.push(data);
  }

  close(code?: number, reason?: string): void {
    if (this.readyState === 3) return;
    this.closedWith = { code, reason };
    this.readyState = 3;
    this.fire("close", { code: code ?? 1005, reason: reason ?? "" });
  }

  // test-side controls
  open(): void {
    this.readyState = 1;
    this.fire("open");
  }

  receiveText(obj: Record<string, unknown> | string): void {
    this.fire("message", { data: typeof obj === "string" ? obj : JSON.stringify(obj) });
  }

  receiveBinary(bytes: Uint8Array): void {
    const copy = new Uint8Array(bytes.length);
    copy.set(bytes);
    this.fire("message", { data: copy.buffer });
  }

  serverClose(code: number, reason = ""): void {
    this.readyState = 3;
    this.fire("close", { code, reason });
  }

  sentJson(): Record<string, unknown>[] {
    return this.sent.map((s) => JSON.parse(s) as Record<string, unknown>);
  }

  private fire(type: string, arg?: unknown): void {
    for (const l of this.listeners.get(type) ?? []) (l as (a?: unknown) => void)(arg);
  }
}

/**
 * Let async handshake steps (WebCrypto runs on the Node threadpool) settle.
 * Uses setImmediate, which tests leave unfaked when they fake timers.
 */
export async function settle(rounds = 6): Promise<void> {
  for (let i = 0; i < rounds; i++) await new Promise((r) => setImmediate(r));
}
