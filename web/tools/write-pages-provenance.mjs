import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const provenanceName = "build-provenance.json";
const shaPattern = /^[0-9a-f]{40}$/;

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function actionPins(workflowText) {
  const pins = {};
  for (const line of workflowText.split(/\r?\n/)) {
    const match = line.match(/^\s*-?\s*uses:\s*([^@\s]+)@([^\s#]+)(?:\s+#.*)?\s*$/);
    if (!match) continue;
    const [, action, ref] = match;
    if (!shaPattern.test(ref)) {
      throw new Error(`Pages action ${action} must use a full 40-character commit SHA`);
    }
    pins[action] = ref;
  }
  return Object.fromEntries(Object.entries(pins).sort(([a], [b]) => a.localeCompare(b)));
}

async function filesUnder(root, current = root) {
  const entries = await readdir(current, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = resolve(current, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await filesUnder(root, path)));
      continue;
    }
    if (!entry.isFile()) {
      throw new Error(`Pages artifact contains unsupported entry: ${relative(root, path)}`);
    }
    const relativePath = relative(root, path).split(sep).join("/");
    if (relativePath !== provenanceName) files.push({ path, relativePath });
  }
  return files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
}

export async function artifactFiles(root) {
  return Promise.all(
    (await filesUnder(root)).map(async ({ path, relativePath }) => {
      const [content, stat] = await Promise.all([readFile(path), lstat(path)]);
      return { path: relativePath, sha256: sha256(content), bytes: stat.size };
    }),
  );
}

function git(root, args) {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
}

export async function toolchainIdentity(root) {
  const [packageJson, lockfile] = await Promise.all([
    readFile(resolve(root, "web/package.json"), "utf8"),
    readFile(resolve(root, "web/pnpm-lock.yaml")),
  ]);
  const packageManager = JSON.parse(packageJson).packageManager;
  if (typeof packageManager !== "string" || !/^pnpm@\d+\.\d+\.\d+$/.test(packageManager)) {
    throw new Error("web/package.json must declare an exact pnpm packageManager version");
  }
  return { node: process.version, packageManager, pnpmLockSha256: sha256(lockfile) };
}

export function sourceIdentity(root, env) {
  const dirty = git(root, ["status", "--porcelain"]).length > 0;
  const head = git(root, ["rev-parse", "HEAD"]);
  const requested = env.GITHUB_SHA;
  if (requested && (!shaPattern.test(requested) || requested !== head)) {
    throw new Error("GITHUB_SHA must be the checked-out 40-character source commit");
  }
  if (dirty && env.MONKEYCRAFT_PAGES_ALLOW_DIRTY !== "1") {
    throw new Error("refusing to label a dirty checkout as a published source commit");
  }
  return dirty ? { commit: null, dirty: true } : { commit: requested ?? head, dirty: false };
}

export async function writePagesProvenance({ distDir, root, env = process.env }) {
  const output = resolve(distDir);
  const workflowPath = resolve(root, ".github/workflows/pages.yml");
  const [workflow, files, toolchain] = await Promise.all([
    readFile(workflowPath, "utf8"),
    artifactFiles(output),
    toolchainIdentity(root),
  ]);
  const source = sourceIdentity(root, env);
  const workflowCommit = env.GITHUB_WORKFLOW_SHA;
  if (workflowCommit && !shaPattern.test(workflowCommit)) {
    throw new Error("GITHUB_WORKFLOW_SHA must be a 40-character commit SHA");
  }
  const manifest = {
    schemaVersion: 1,
    source,
    workflow: {
      commit: workflowCommit ?? null,
      sha256: sha256(workflow),
      actions: actionPins(workflow),
    },
    run: {
      repository: env.GITHUB_REPOSITORY ?? null,
      id: env.GITHUB_RUN_ID ?? null,
      attempt: env.GITHUB_RUN_ATTEMPT ?? null,
      serverUrl: env.GITHUB_SERVER_URL ?? null,
    },
    pagesBase: env.MONKEYCRAFT_PAGES_BASE ?? "/monkeycraft/",
    toolchain,
    artifactFiles: files,
  };
  await mkdir(output, { recursive: true });
  await writeFile(resolve(output, provenanceName), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

async function main() {
  const here = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
  const root = resolve(here, "..");
  const distDir = process.argv[2] ? resolve(here, process.argv[2]) : resolve(here, "dist-pages");
  const manifest = await writePagesProvenance({ distDir, root });
  process.stdout.write(`${provenanceName}: ${manifest.artifactFiles.length} files\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
