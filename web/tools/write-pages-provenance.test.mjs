import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { actionPins, artifactFiles, sha256, toolchainIdentity } from "./write-pages-provenance.mjs";

test("extracts only full-SHA action pins", () => {
  const pins = actionPins(
    "- uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n- uses: pnpm/action-setup@0977fd99725f1db4007ccb2928dbb4e90d06cc86\n",
  );
  assert.deepEqual(pins, {
    "actions/checkout": "d23441a48e516b6c34aea4fa41551a30e30af803",
    "pnpm/action-setup": "0977fd99725f1db4007ccb2928dbb4e90d06cc86",
  });
  assert.throws(() => actionPins("- uses: actions/checkout@v6\n"), /40-character/);
});

test("hashes every publishable artifact but excludes its own provenance file", async () => {
  const root = await mkdtemp(join(tmpdir(), "monkeycraft-pages-provenance-"));
  await mkdir(join(root, "assets"));
  await Promise.all([
    writeFile(join(root, "index.html"), "index"),
    writeFile(join(root, "assets", "app.js"), "app"),
    writeFile(join(root, "build-provenance.json"), "old"),
  ]);
  assert.deepEqual(await artifactFiles(root), [
    { path: "assets/app.js", sha256: sha256("app"), bytes: 3 },
    { path: "index.html", sha256: sha256("index"), bytes: 5 },
  ]);
});


test("records the running Node version and exact declared pnpm toolchain", async () => {
  const identity = await toolchainIdentity(new URL("../..", import.meta.url).pathname);
  assert.equal(identity.node, process.version);
  assert.match(identity.packageManager, /^pnpm@\d+\.\d+\.\d+$/);
  assert.match(identity.pnpmLockSha256, /^[0-9a-f]{64}$/);
});
