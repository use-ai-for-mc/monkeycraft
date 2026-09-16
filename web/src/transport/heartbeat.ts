// Client-side liveness (docs/PROTOCOL.md 1.4). Pure; the owner calls tick()
// about once a second and acts on the returned instruction.

export interface HeartbeatOptions {
  /** Send HEARTBEAT after this much server silence. */
  idleMs?: number;
  /** Declare the connection lost when no HEARTBEAT_ACK arrives within this. */
  ackTimeoutMs?: number;
  now?: () => number;
}

export type HeartbeatAction = "send" | "lost" | null;

export class Heartbeat {
  private readonly idleMs: number;
  private readonly ackTimeoutMs: number;
  private readonly now: () => number;
  private lastServerMessageAt: number;
  private sentAt: number | null = null;
  private hidden = false;

  constructor(opts: HeartbeatOptions = {}) {
    this.idleMs = opts.idleMs ?? 3000;
    this.ackTimeoutMs = opts.ackTimeoutMs ?? 5000;
    this.now = opts.now ?? (() => Date.now());
    this.lastServerMessageAt = this.now();
  }

  /** Any message from the server, text or binary. */
  onServerMessage(): void {
    this.lastServerMessageAt = this.now();
  }

  onAck(): void {
    this.sentAt = null;
    this.lastServerMessageAt = this.now();
  }

  /** While hidden nothing is sent and nothing times out; on return the clock restarts. */
  onVisibility(hidden: boolean): void {
    this.hidden = hidden;
    if (!hidden) {
      this.lastServerMessageAt = this.now();
      this.sentAt = null;
    }
  }

  get waitingForAck(): boolean {
    return this.sentAt !== null;
  }

  tick(): HeartbeatAction {
    if (this.hidden) return null;
    const t = this.now();
    if (this.sentAt !== null) {
      if (t - this.sentAt >= this.ackTimeoutMs) {
        this.sentAt = null;
        return "lost";
      }
      return null;
    }
    if (t - this.lastServerMessageAt >= this.idleMs) {
      this.sentAt = t;
      return "send";
    }
    return null;
  }
}
