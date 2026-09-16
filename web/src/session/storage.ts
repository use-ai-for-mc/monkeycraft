// Credential vault and server preference (docs/LEGACY_CLIENT_NOTES.md,
// "Credential vault"). Keys are namespaced `monkeycraft.*`; nothing is read
// from the old Flutter `flutter.*` keys.

import type { StorageLike } from "./settings.ts";

export const VAULT_KEY = "monkeycraft.vault";
export const SERVER_KEY = "monkeycraft.server";
export const REMEMBER_KEY = "monkeycraft.remember";
export const MAX_VAULT_ENTRIES = 8;
/** Vault slot used when the server sends no keyId (older mods). */
export const LEGACY_KEY_ID = "legacy";

export interface VaultEntry {
  password: string;
  lastServer: string;
  lastSeen: number;
}

export type Vault = Record<string, VaultEntry>;

export class CredentialStore {
  constructor(
    private readonly storage: StorageLike,
    private readonly now: () => number = () => Date.now(),
  ) {}

  get remember(): boolean {
    return this.storage.getItem(REMEMBER_KEY) !== "false";
  }

  set remember(value: boolean) {
    this.storage.setItem(REMEMBER_KEY, value ? "true" : "false");
    if (!value) this.clearPasswords();
  }

  /** User-typed server override; null means "use the page origin". */
  get server(): string | null {
    return this.storage.getItem(SERVER_KEY);
  }

  set server(value: string | null) {
    if (value === null || value.trim() === "") this.storage.removeItem(SERVER_KEY);
    else this.storage.setItem(SERVER_KEY, value.trim());
  }

  vault(): Vault {
    try {
      const raw = JSON.parse(this.storage.getItem(VAULT_KEY) ?? "{}") as unknown;
      if (typeof raw !== "object" || raw === null) return {};
      const out: Vault = {};
      for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
        if (typeof v !== "object" || v === null) continue;
        const e = v as Record<string, unknown>;
        if (typeof e.password !== "string" || e.password === "") continue;
        out[k] = {
          password: e.password,
          lastServer: typeof e.lastServer === "string" ? e.lastServer : "",
          lastSeen: typeof e.lastSeen === "number" ? e.lastSeen : 0,
        };
      }
      return out;
    } catch {
      return {};
    }
  }

  lookup(keyId: string | null): string | null {
    const entry = this.vault()[keyId || LEGACY_KEY_ID];
    return entry?.password ?? null;
  }

  /** The most recently used password, for pre-filling the login form. */
  latest(): VaultEntry | null {
    const entries = Object.values(this.vault());
    if (entries.length === 0) return null;
    return entries.reduce((a, b) => (b.lastSeen > a.lastSeen ? b : a));
  }

  /** Remember a password that just authenticated. No-op when remember is off. */
  bind(keyId: string | null, password: string, server: string): void {
    if (!this.remember || password === "") return;
    const vault = this.vault();
    vault[keyId || LEGACY_KEY_ID] = { password, lastServer: server, lastSeen: this.now() };
    const byRecency = Object.entries(vault).sort(([, a], [, b]) => b.lastSeen - a.lastSeen);
    for (const [k] of byRecency.slice(MAX_VAULT_ENTRIES)) delete vault[k];
    this.storage.setItem(VAULT_KEY, JSON.stringify(vault));
  }

  /** Drop a password the server rejected. */
  forget(keyId: string | null): void {
    const vault = this.vault();
    delete vault[keyId || LEGACY_KEY_ID];
    this.storage.setItem(VAULT_KEY, JSON.stringify(vault));
  }

  clearPasswords(): void {
    this.storage.removeItem(VAULT_KEY);
  }
}

/** In-memory StorageLike for tests and for browsers that block localStorage. */
export class MemoryStorage implements StorageLike {
  private readonly map = new Map<string, string>();
  getItem(key: string): string | null {
    return this.map.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.map.set(key, value);
  }
  removeItem(key: string): void {
    this.map.delete(key);
  }
}

export function browserStorage(): StorageLike {
  try {
    const s = globalThis.localStorage;
    const probe = "monkeycraft.probe";
    s.setItem(probe, "1");
    s.removeItem(probe);
    return s;
  } catch {
    return new MemoryStorage();
  }
}
