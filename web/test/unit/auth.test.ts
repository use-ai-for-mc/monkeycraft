import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  clientSignature,
  generateSalt,
  hmacBase64,
  verifyServerSignature,
} from "../../src/protocol/auth.ts";

const password = "ForAppleBetaReview";
const serverSalt = "q7v0mCk2Yw1ZpN3tRxL5aA==";
const clientSalt = "Zm9vYmFyYmF6cXV4MTIzNA==";

function nodeHmac(key: string, msg: string): string {
  return createHmac("sha256", key).update(msg, "utf8").digest("base64");
}

describe("hmacBase64", () => {
  it("matches Node's HMAC-SHA256 in standard Base64", async () => {
    expect(await hmacBase64(password, serverSalt + clientSalt)).toBe(
      nodeHmac(password, serverSalt + clientSalt),
    );
  });

  it("handles non-ASCII passwords as UTF-8", async () => {
    expect(await hmacBase64("密码🐒", "m")).toBe(nodeHmac("密码🐒", "m"));
  });
});

describe("handshake signatures", () => {
  it("client signs serverSalt+clientSalt", async () => {
    expect(await clientSignature(password, serverSalt, clientSalt)).toBe(
      nodeHmac(password, serverSalt + clientSalt),
    );
  });

  it("verifies the server's reversed-order signature", async () => {
    const good = nodeHmac(password, clientSalt + serverSalt);
    expect(await verifyServerSignature(password, serverSalt, clientSalt, good)).toBe(true);
    const wrongOrder = nodeHmac(password, serverSalt + clientSalt);
    expect(await verifyServerSignature(password, serverSalt, clientSalt, wrongOrder)).toBe(false);
    expect(await verifyServerSignature(password, serverSalt, clientSalt, "")).toBe(false);
  });
});

describe("generateSalt", () => {
  it("is 16 random bytes in padded Base64", () => {
    const a = generateSalt();
    const b = generateSalt();
    expect(a).toMatch(/^[A-Za-z0-9+/]{22}==$/);
    expect(a).not.toBe(b);
  });
});
