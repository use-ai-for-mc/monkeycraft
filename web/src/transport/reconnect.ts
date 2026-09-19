// Reconnect policy: 1 s, 2 s, 4 s, then give up (matches the Flutter client).

export interface ReconnectOptions {
  maxRetries?: number;
  baseDelayMs?: number;
}

export class ReconnectPolicy {
  private readonly maxRetries: number;
  private readonly baseDelayMs: number;
  attempts = 0;

  constructor(opts: ReconnectOptions = {}) {
    this.maxRetries = opts.maxRetries ?? 3;
    this.baseDelayMs = opts.baseDelayMs ?? 1000;
  }

  nextDelay(): number | null {
    if (this.attempts >= this.maxRetries) return null;
    return this.baseDelayMs * 2 ** this.attempts;
  }

  /** Delay before the next attempt, or null when retries are exhausted. */
  next(): number | null {
    const delay = this.nextDelay();
    if (delay === null) return null;
    this.attempts += 1;
    return delay;
  }

  /** Called on every HEARTBEAT_ACK so a healthy session never accumulates attempts. */
  reset(): void {
    this.attempts = 0;
  }

  get exhausted(): boolean {
    return this.attempts >= this.maxRetries;
  }
}
