import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  actionPins,
  artifactFiles,
  assertProductionTailscale,
  flutterToolchainIdentity,
  sha256,
  toolchainIdentity,
} from "./write-pages-provenance.mjs";

test("extracts only full-SHA action pins", () => {
  const pins = actionPins(
    "- uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n- uses: actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38\n",
  );
  assert.deepEqual(pins, {
    "actions/checkout": "d23441a48e516b6c34aea4fa41551a30e30af803",
    "actions/setup-node": "249970729cb0ef3589644e2896645e5dc5ba9c38",
  });
  assert.throws(() => actionPins("- uses: actions/checkout@v6\n"), /40-character/);
});

test("the Flutter Pages workflow records its actual six pinned actions", async () => {
  const root = new URL("../..", import.meta.url).pathname;
  const pins = actionPins(await readFile(join(root, ".github/workflows/pages.yml"), "utf8"));
  assert.deepEqual(Object.keys(pins), [
    "actions/checkout",
    "actions/configure-pages",
    "actions/deploy-pages",
    "actions/setup-go",
    "actions/setup-node",
    "actions/upload-pages-artifact",
  ]);
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

test("records a locked Flutter and Dart toolchain for the Flutter Pages client", async () => {
  const root = new URL("../..", import.meta.url).pathname;
  const versionPath = join(await mkdtemp(join(tmpdir(), "monkeycraft-flutter-version-")), "flutter.version.json");
  const frameworkRevision = "90673a4eef275d1a6692c26ac80d6d746d41a73a";
  const engineRevision = "6c0baaebf70e0148f485f27d5616b3d3382da7bf";
  await writeFile(versionPath, JSON.stringify({
    frameworkVersion: "3.41.2",
    frameworkRevision,
    engineRevision,
    dartSdkVersion: "3.11.0",
    repositoryUrl: "https://github.com/flutter/flutter.git",
  }));
  const identity = await flutterToolchainIdentity(root, {
    MONKEYCRAFT_FLUTTER_VERSION_JSON: versionPath,
    MONKEYCRAFT_FLUTTER_FRAMEWORK_COMMIT: frameworkRevision,
  });
  assert.deepEqual(identity.flutter, {
    frameworkVersion: "3.41.2",
    frameworkRevision,
    engineRevision,
    repositoryUrl: "https://github.com/flutter/flutter.git",
  });
  assert.deepEqual(identity.dartSdk, { version: "3.11.0", engineRevision });
  assert.match(identity.pubspecLockSha256, /^[0-9a-f]{64}$/);
});

test("rejects an incomplete Tailscale runtime from the Pages artifact", () => {
  assert.throws(
    () => assertProductionTailscale([{ path: "tailscale/main.wasm" }]),
    /complete production Tailscale runtime/,
  );
});

test("allows runtime files and rejects debug pages", () => {
  const files = ['worker.js', 'rpc.js', 'fake-backend.js', 'state-store.js', 'main.wasm', 'wasm_exec.js', 'VERSION.json', 'LICENSE'].map(name => ({path: `tailscale/${name}`}));
  assert.doesNotThrow(() => assertProductionTailscale(files));
  assert.throws(() => assertProductionTailscale([...files, {path: 'tailscale/poc/index.html'}]), /without debug pages/);
});
