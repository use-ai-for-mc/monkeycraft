// HMAC handshake, see docs/PROTOCOL.md section 2. Runs in browsers and Node
// (both expose WebCrypto as globalThis.crypto).

const enc = new TextEncoder();

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

/** 16 random bytes, standard Base64 with padding; same shape as the server salt. */
export function generateSalt(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return toBase64(bytes);
}

/** base64(HMAC-SHA256(key = utf8(password), msg = utf8(message))). */
export async function hmacBase64(password: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(password),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return toBase64(new Uint8Array(sig));
}

/** Signature the client sends: server salt first, then client salt. */
export function clientSignature(password: string, serverSalt: string, clientSalt: string) {
  return hmacBase64(password, serverSalt + clientSalt);
}

/** AUTH_OK.signature is computed with the salts in the opposite order. */
export async function verifyServerSignature(
  password: string,
  serverSalt: string,
  clientSalt: string,
  signature: string,
): Promise<boolean> {
  const expected = await hmacBase64(password, clientSalt + serverSalt);
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0;
}
