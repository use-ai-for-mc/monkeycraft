import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { extname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL("../..", import.meta.url)));
const chrome =
  process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".css": "text/css",
};

const hits = [];
const server = createServer(async (req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/tests/browser/runner.html";
  hits.push(p);
  const file = join(root, p.replace(/^\//, ""));
  if (!file.startsWith(root)) {
    res.writeHead(403);
    res.end();
    return;
  }
  try {
    const body = await readFile(file);
    const type = mime[extname(file)] || "application/octet-stream";
    res.writeHead(200, {
      "content-type": type,
      "cache-control": "no-store",
    });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
});

await new Promise((r) => server.listen(0, "127.0.0.1", r));
const { port } = server.address();
const url = `http://127.0.0.1:${port}/tests/browser/runner.html`;
const profile = await mkdtemp(join(tmpdir(), "mc-ts-chrome-"));
function runChrome(target) {
  return new Promise((resolve) => {
    const child = spawn(
      chrome,
      [
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-sandbox",
        "--user-data-dir=" + profile,
        "--dump-dom",
        target,
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    let out = "";
    let err = "";
    child.stdout.on("data", (d) => {
      out += d.toString();
    });
    child.stderr.on("data", (d) => {
      err += d.toString();
    });
    const t = setTimeout(() => {
      child.kill("SIGKILL");
    }, 15000);
    child.on("close", (code) => {
      clearTimeout(t);
      resolve({ code, out, err });
    });
  });
}

const page = await runChrome(url);
if (!page.out.includes("BROWSER_TESTS_OK")) {
  console.error("page dump:\n", page.out.slice(0, 4000));
  console.error("stderr:\n", page.err.slice(0, 2000));
  await rm(profile, { recursive: true, force: true });
  server.close();
  process.exit(1);
}
console.log("chrome headless: BROWSER_TESTS_OK");
const mimeOk = await fetch(`http://127.0.0.1:${port}/tests/browser/probe.wasm`).then((r) => {
  const type = r.headers.get("content-type");
  console.log("wasm mime:", type);
  return type === "application/wasm";
});
await rm(profile, { recursive: true, force: true });
if (!mimeOk) {
  server.close();
  process.exit(1);
}
server.close();
process.exit(0);
