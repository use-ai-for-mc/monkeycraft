import { describe, expect, it } from "vitest";
import {
  defaultSettings,
  loadSettings,
  SETTINGS_KEY,
  sanitizeSettings,
  saveSettings,
} from "../../src/session/settings.ts";
import { CredentialStore, MemoryStorage, VAULT_KEY } from "../../src/session/storage.ts";

describe("settings", () => {
  it("returns defaults for missing or corrupt storage", () => {
    const s = new MemoryStorage();
    expect(loadSettings(s)).toEqual(defaultSettings);
    s.setItem(SETTINGS_KEY, "{not json");
    expect(loadSettings(s)).toEqual(defaultSettings);
  });

  it("sanitizes ranges and enums", () => {
    expect(
      sanitizeSettings({
        fps: 99,
        colorMode: 7,
        preset: "ultra",
        controlLayout: "gamepad",
        deviceName: "x".repeat(60),
        lookSensitivity: -1,
        invertLookY: "yes",
      }),
    ).toEqual({ ...defaultSettings, fps: 20, colorMode: 3, deviceName: "x".repeat(48) });
    expect(sanitizeSettings({ fps: 0.4, colorMode: 2.6, preset: "low" })).toMatchObject({
      fps: 1,
      colorMode: 3,
      preset: "low",
    });
  });

  it("round-trips", () => {
    const s = new MemoryStorage();
    saveSettings(s, { ...defaultSettings, fps: 15, dataSaver: true, controlLayout: "mouse" });
    expect(loadSettings(s)).toMatchObject({ fps: 15, dataSaver: true, controlLayout: "mouse" });
  });
});

describe("CredentialStore", () => {
  it("binds, looks up, and evicts beyond 8 entries by lastSeen", () => {
    let t = 0;
    const store = new CredentialStore(new MemoryStorage(), () => ++t);
    for (let i = 0; i < 10; i++) store.bind(`k${i}`, `p${i}`, `s${i}`);
    expect(store.lookup("k0")).toBeNull();
    expect(store.lookup("k1")).toBeNull();
    expect(store.lookup("k2")).toBe("p2");
    expect(store.lookup("k9")).toBe("p9");
    expect(store.latest()).toMatchObject({ password: "p9", lastServer: "s9" });
  });

  it("uses the legacy slot when there is no keyId", () => {
    const store = new CredentialStore(new MemoryStorage());
    store.bind(null, "pw", "srv");
    expect(store.lookup(null)).toBe("pw");
    expect(store.lookup("")).toBe("pw");
    store.forget(null);
    expect(store.lookup(null)).toBeNull();
  });

  it("does not persist when remember is off, and clears existing passwords", () => {
    const store = new CredentialStore(new MemoryStorage());
    store.bind("k", "pw", "srv");
    store.remember = false;
    expect(store.lookup("k")).toBeNull();
    store.bind("k", "pw", "srv");
    expect(store.lookup("k")).toBeNull();
    store.remember = true;
    store.bind("k", "pw", "srv");
    expect(store.lookup("k")).toBe("pw");
  });

  it("ignores corrupt vault entries", () => {
    const s = new MemoryStorage();
    s.setItem(
      VAULT_KEY,
      JSON.stringify({ ok: { password: "p" }, bad: 5, empty: { password: "" } }),
    );
    const store = new CredentialStore(s);
    expect(store.vault()).toEqual({ ok: { password: "p", lastServer: "", lastSeen: 0 } });
    s.setItem(VAULT_KEY, "garbage");
    expect(store.vault()).toEqual({});
  });

  it("stores the server override trimmed and clears it on empty", () => {
    const store = new CredentialStore(new MemoryStorage());
    expect(store.server).toBeNull();
    store.server = "  192.168.0.3:9600 ";
    expect(store.server).toBe("192.168.0.3:9600");
    store.server = "  ";
    expect(store.server).toBeNull();
  });
});
