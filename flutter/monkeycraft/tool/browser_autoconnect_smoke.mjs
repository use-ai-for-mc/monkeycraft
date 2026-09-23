import { chromium } from '../../../web/node_modules/@playwright/test/index.mjs';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const url = process.env.FLUTTER_WEB_URL ?? 'http://127.0.0.1:4189/';
const server = process.env.FLUTTER_REPLAY_URL ?? 'ws://127.0.0.1:9629';
const output = path.resolve(process.env.FLUTTER_WEB_EVIDENCE ?? 'outputs/browser-autoconnect');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: true });
const result = { checks: [], errors: [] };
let page;
try {
  const context = await browser.newContext();
  await context.addInitScript(() => {
    window.connectionProbe = { sockets: 0, frames: 0 };
    const Socket = window.WebSocket;
    window.WebSocket = class extends Socket {
      constructor(...args) { super(...args); window.connectionProbe.sockets++; }
    };
    const Decoder = window.VideoDecoder;
    window.VideoDecoder = class extends Decoder {
      constructor(config) {
        super({ ...config, output(frame) {
          window.connectionProbe.frames++;
          config.output(frame);
        } });
      }
    };
  });
  page = await context.newPage();
  const observe = p => p.on('pageerror', error => result.errors.push(error.message));
  observe(page);
  const semantics = async () => {
    const placeholder = page.locator('flt-semantics-placeholder');
    await placeholder.waitFor({ state: 'attached' });
    await placeholder.evaluate(element => element.click());
  };
  const edit = async (name, value) => {
    const field = page.getByRole('textbox', { name, exact: true });
    await field.click();
    await page.waitForTimeout(200);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type(value, { delay: 10 });
    await page.waitForTimeout(100);
  };
  const connected = async () => {
    await page.waitForFunction(() => window.connectionProbe.frames >= 3);
    assert.equal(await page.evaluate(() => window.connectionProbe.sockets), 1);
  };
  const disconnect = async () => {
    await page.getByRole('button', { name: 'Disconnect', exact: true }).click();
    await page.getByRole('button', { name: 'Connect', exact: true }).waitFor();
    await page.waitForTimeout(1000);
    assert.equal(await page.evaluate(() => window.connectionProbe.sockets), 1);
  };
  await page.goto(url);
  await semantics();
  await page.getByRole('button', { name: 'Change', exact: true }).click();
  await edit('Server address', server);
  const passwordMode = page.getByText('Use password or scan QR', { exact: true });
  if (await passwordMode.count()) await passwordMode.click();
  await edit('Password', 'test');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await connected();
  result.checks.push('first password login decodes replay video');

  await page.reload();
  await semantics();
  await connected();
  result.checks.push('reload connects with saved credentials without a Connect click');
  await disconnect();
  result.checks.push('explicit disconnect stays on the connection screen');
  await page.screenshot({ path: path.join(output, 'remembered-computer.png') });

  await page.close();
  page = await context.newPage();
  observe(page);
  await page.goto(url);
  await semantics();
  await connected();
  result.checks.push('new document in the same browser automatically enters the game');
  await disconnect();
  const savedState = await context.storageState();
  await page.getByRole('checkbox', { name: 'Remember and connect automatically' }).click();
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => window.connectionProbe.sockets === 2);
  await page.getByRole('button', { name: 'Disconnect', exact: true }).waitFor();
  await page.reload();
  await semantics();
  await page.getByRole('button', { name: 'Connect', exact: true }).waitFor();
  await page.waitForTimeout(1000);
  assert.equal(await page.evaluate(() => window.connectionProbe.sockets), 0);
  result.checks.push('opting out removes saved credentials and prevents automatic connection');
  const offlineContext = await browser.newContext({ storageState: savedState });
  page = await offlineContext.newPage();
  observe(page);
  let offlineAttempts = 0;
  await page.routeWebSocket(server, socket => {
    offlineAttempts++;
    socket.close({ code: 1000 });
  });
  await page.goto(url);
  await semantics();
  await page.getByRole('button', { name: 'Connect', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Change', exact: true }).waitFor();
  await page.waitForTimeout(1000);
  assert.equal(offlineAttempts, 1);
  result.checks.push('unavailable server restores the editable connection screen without looping');
  assert.deepEqual(result.errors, []);
  result.passed = true;
} catch (error) {
  result.passed = false;
  if (page) {
    result.body = await page.locator('body').innerText().catch(() => '');
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
  }
  result.failure = String(error.stack ?? error);
  process.exitCode = 1;
} finally {
  await browser.close();
  await writeFile(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
}
