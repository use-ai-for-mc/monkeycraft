import { chromium } from '../../../web/node_modules/@playwright/test/index.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const required = name => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

const webUrl = required('FLUTTER_WEB_URL');
const server = required('MONKEYCRAFT_LIVE_SERVER');
const configPath = required('MONKEYCRAFT_CONFIG_PATH');
const durationSeconds = Number.parseInt(process.env.MONKEYCRAFT_LIVE_DURATION_SEC ?? '600', 10);
const menuPauseSeconds = Number.parseInt(process.env.MONKEYCRAFT_MENU_PAUSE_SEC ?? '90', 10);
const output = path.resolve(process.env.MONKEYCRAFT_LIVE_EVIDENCE ?? 'outputs/flutter-live-chrome');

if (!Number.isSafeInteger(durationSeconds) || durationSeconds < 60) {
  throw new Error('MONKEYCRAFT_LIVE_DURATION_SEC must be an integer of at least 60 seconds');
}
if (!Number.isSafeInteger(menuPauseSeconds) || menuPauseSeconds < 1 || menuPauseSeconds > 120) {
  throw new Error('MONKEYCRAFT_MENU_PAUSE_SEC must be an integer from 1 through 120');
}

async function loadPassword(file) {
  const config = JSON.parse(await readFile(file, 'utf8'));
  if (typeof config.password !== 'string' || !config.password) {
    throw new Error('MonkeyCraft config has no password');
  }
  return config.password;
}

await mkdir(output, { recursive: true });
const statePath = path.join(output, 'status.json');
const resultPath = path.join(output, 'result.json');
const checkpointsPath = path.join(output, 'checkpoints.json');
const result = { startedAt: new Date().toISOString(), durationSeconds, checks: [], errors: [], sentTypes: [], checkpoints: [] };
const updateStatus = async (phase, extra = {}) => {
  await writeFile(statePath, `${JSON.stringify({ phase, updatedAt: new Date().toISOString(), checks: result.checks, ...extra }, null, 2)}\n`);
};

let browser;
let page;
try {
  const password = await loadPassword(configPath);
  await updateStatus('launching');
  browser = await chromium.launch({
    headless: process.env.MONKEYCRAFT_LIVE_HEADED !== '1',
    executablePath: process.env.CHROME_EXECUTABLE || undefined,
  });
  result.browserVersion = browser.version();
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await context.addInitScript(() => {
    const now = () => Math.round(performance.now());
    window.monkeycraftLiveProbe = { decoders: 0, decoded: 0, decoderErrors: 0, sizes: [], sockets: 0, sent: [], received: [], inputReleases: [] };
    const NativeDecoder = window.VideoDecoder;
    window.VideoDecoder = class extends NativeDecoder {
      constructor(config) {
        super({
          ...config,
          output: frame => {
            const probe = window.monkeycraftLiveProbe;
            probe.decoded += 1;
            const size = `${frame.displayWidth}x${frame.displayHeight}`;
            if (!probe.sizes.includes(size)) probe.sizes.push(size);
            config.output(frame);
          },
          error: error => { window.monkeycraftLiveProbe.decoderErrors += 1; config.error(error); },
        });
        window.monkeycraftLiveProbe.decoders += 1;
      }
    };
    const NativeSocket = window.WebSocket;
    window.WebSocket = class extends NativeSocket {
      constructor(...args) {
        super(...args);
        window.monkeycraftLiveProbe.sockets += 1;
        this.addEventListener('message', event => {
          if (typeof event.data !== 'string') return;
          try {
            const message = JSON.parse(event.data);
            if (message.type !== 'HELLO' && message.type !== 'AUTH_OK') {
              window.monkeycraftLiveProbe.received.push({
                type: message.type,
                isOpen: message.isOpen,
                videoState: message.videoState,
                active: message.active,
                at: now(),
              });
            }
          } catch (_) {}
        });
      }
      send(data) {
        if (typeof data === 'string') {
          try {
            const message = JSON.parse(data);
            if (message.type !== 'AUTH') {
              const safe = { type: message.type, at: now() };
              if (message.type === 'INPUT' || message.type === 'SCREEN_KEY') {
                safe.key = message.key;
                safe.pressed = message.pressed;
                if (!message.pressed) window.monkeycraftLiveProbe.inputReleases.push(message.key);
              }
              window.monkeycraftLiveProbe.sent.push(safe);
            }
          } catch (_) {}
        }
        return super.send(data);
      }
    };
  });
  page = await context.newPage();
  page.on('pageerror', error => result.errors.push(error.message));
  await page.goto(webUrl);
  await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
  const edit = async (name, value) => {
    const field = page.getByRole('textbox', { name, exact: true });
    await field.click();
    await page.waitForTimeout(200);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type(value, { delay: 5 });
    await page.waitForTimeout(100);
  };
  const stats = () => page.evaluate(() => ({
    decoders: window.monkeycraftLiveProbe.decoders,
    decoded: window.monkeycraftLiveProbe.decoded,
    decoderErrors: window.monkeycraftLiveProbe.decoderErrors,
    sizes: window.monkeycraftLiveProbe.sizes,
    sockets: window.monkeycraftLiveProbe.sockets,
    sent: window.monkeycraftLiveProbe.sent,
    received: window.monkeycraftLiveProbe.received,
    inputReleases: window.monkeycraftLiveProbe.inputReleases,
  }));
  const markers = () => page.evaluate(() => ({ sent: window.monkeycraftLiveProbe.sent.length, received: window.monkeycraftLiveProbe.received.length }));
  const passwordMode = page.getByText('Use password or scan QR', { exact: true });
  if (await passwordMode.count()) await passwordMode.click();

  await updateStatus('checking-authentication-rejection');
  await edit('Server address', server);
  await edit('Password', `invalid-${randomUUID()}`);
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => /invalid|failed|did not match/i.test(document.body.innerText), null, { timeout: 12_000 });
  result.checks.push('incorrect password rejected by live server');

  await page.waitForTimeout(900);
  await edit('Password', password);
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => window.monkeycraftLiveProbe.decoded >= 20, null, { timeout: 20_000 });
  const baseline = await stats();
  assert.equal(baseline.decoderErrors, 0);
  result.checks.push('correct password authenticates and actual H264 frames decode');
  await page.screenshot({ path: path.join(output, 'connected.png') });

  await updateStatus('checking-resize-stability');
  for (const viewport of [{ width: 900, height: 700 }, { width: 430, height: 900 }, { width: 1400, height: 850 }, { width: 1280, height: 800 }]) {
    await page.setViewportSize(viewport);
    await page.waitForTimeout(250);
  }
  await page.waitForFunction(count => window.monkeycraftLiveProbe.decoded >= count + 15, baseline.decoded, { timeout: 12_000 });
  const resized = await stats();
  assert.equal(resized.decoders, baseline.decoders);
  assert.equal(resized.sockets, baseline.sockets);
  assert.equal(resized.decoderErrors, 0);
  result.checks.push('resize preserves decoder and connection while frames continue');

  await updateStatus('checking-safe-menu-and-input-release');
  await page.locator('flutter-view').focus();
  const beforeE = await markers();
  await page.keyboard.press('e');
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.sent.slice(start.sent).some(m => m.type === 'INPUT' && m.key === 'E' && m.pressed === true),
    beforeE,
    { timeout: 8_000 },
  );
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.received.slice(start.received).some(m => m.type === 'SCREEN_STATE' && m.isOpen === true),
    beforeE,
    { timeout: 8_000 },
  );
  const screenOpenBaseline = await stats();
  await updateStatus('menu-open-awaiting-video-frame', { decodedFrames: screenOpenBaseline.decoded });
  await page.waitForFunction(
    baseline => window.monkeycraftLiveProbe.decoded >= baseline.decoded + 5,
    screenOpenBaseline,
    { timeout: 12_000 },
  );
  await page.screenshot({ path: path.join(output, 'inventory-open.png') });
  await updateStatus('menu-open-awaiting-inspection', { menuPauseSeconds });
  await page.waitForTimeout(menuPauseSeconds * 1000);
  const beforeEscape = await markers();
  await page.keyboard.press('Escape');
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.sent.slice(start.sent).some(m => m.type === 'SCREEN_KEY' && m.key === 'ESCAPE' && m.pressed === true) &&
      window.monkeycraftLiveProbe.sent.slice(start.sent).some(m => m.type === 'SCREEN_KEY' && m.key === 'ESCAPE' && m.pressed === false),
    beforeEscape,
    { timeout: 8_000 },
  );
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.received.slice(start.received).some(m => m.type === 'SCREEN_STATE' && m.isOpen === false),
    beforeEscape,
    { timeout: 8_000 },
  );
  const beforeShift = await markers();
  await page.keyboard.down('Shift');
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.sent.slice(start.sent).some(m => m.type === 'INPUT' && m.key === 'SHIFT' && m.pressed === true),
    beforeShift,
    { timeout: 5_000 },
  );
  await page.waitForTimeout(150);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await page.waitForFunction(
    start => window.monkeycraftLiveProbe.sent.slice(start.sent).some(m => m.type === 'INPUT' && m.key === 'SHIFT' && m.pressed === false),
    beforeShift,
    { timeout: 5_000 },
  );
  await page.keyboard.up('Shift');
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  result.checks.push('fresh E/ESC menu round-trip and blur release of a short Shift press');

  await updateStatus('checking-credential-persistence');
  await page.reload();
  await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => window.monkeycraftLiveProbe.decoded >= 12, null, { timeout: 20_000 });
  result.checks.push('refresh restores same-target identity and reconnects');

  const reconnectBaseline = await stats();
  await updateStatus('waiting-controlled-disconnect', {
    socketCount: reconnectBaseline.sockets,
    decodedFrames: reconnectBaseline.decoded,
    timeoutSeconds: 90,
  });
  await page.waitForFunction(
    baseline => window.monkeycraftLiveProbe.sockets > baseline.sockets,
    reconnectBaseline,
    { timeout: 90_000 },
  );
  const afterNewSocket = await stats();
  await page.waitForFunction(
    baseline => window.monkeycraftLiveProbe.decoded >= baseline.decoded + 12,
    afterNewSocket,
    { timeout: 20_000 },
  );
  const reconnected = await stats();
  assert.equal(reconnected.decoderErrors, 0);
  result.checks.push('server-initiated socket close reconnects and resumes H264 decoding');

  await updateStatus('observing-live-video', { durationSeconds, intervalSeconds: 15 });
  const sustainedBaseline = reconnected;
  let previous = sustainedBaseline;
  for (let elapsed = 0; elapsed < durationSeconds; elapsed += 15) {
    await page.waitForTimeout(Math.min(15, durationSeconds - elapsed) * 1000);
    const current = await stats();
    const recentStatus = current.received.slice(previous.received.length);
    const hibernating = recentStatus.some(m =>
      (m.type === 'SERVER_STATUS' && String(m.videoState ?? '').toLowerCase() === 'hibernating') ||
      (m.type === 'HIBERNATION_STATUS' && m.active === true),
    );
    const checkpoint = { elapsedSeconds: Math.min(elapsed + 15, durationSeconds), decodedDelta: current.decoded - previous.decoded, decoderErrors: current.decoderErrors, sockets: current.sockets, hibernating };
    result.checkpoints.push(checkpoint);
    await writeFile(checkpointsPath, `${JSON.stringify(result.checkpoints, null, 2)}\n`);
    await updateStatus('observing-live-video', { durationSeconds, intervalSeconds: 15, checkpoint });
    assert.equal(current.decoderErrors, 0, 'decoder error during sustained video');
    assert.equal(current.sockets, sustainedBaseline.sockets, 'socket changed during sustained video');
    if (hibernating) throw new Error(`server hibernated during sustained video at ${checkpoint.elapsedSeconds}s`);
    assert.ok(checkpoint.decodedDelta > 0, `no decoded H264 frame during ${checkpoint.elapsedSeconds - 15}-${checkpoint.elapsedSeconds}s interval`);
    previous = current;
  }
  const sustained = await stats();
  const unsafe = sustained.sent.filter(message => ['RUN_COMMAND', 'SEND_CHAT', 'LOOK_DELTA', 'CLICK', 'HOTBAR_SELECT'].includes(message.type));
  assert.deepEqual(unsafe, []);
  assert.deepEqual(result.errors, []);
  result.final = sustained;
  result.sentTypes = [...new Set(sustained.sent.map(message => message.type))];
  result.checks.push(`${durationSeconds}-second live video decodes in every 15-second interval without forbidden game actions`);
  await page.screenshot({ path: path.join(output, 'stable-stream.png') });
  result.passed = true;
  await updateStatus('passed', { durationSeconds });
} catch (error) {
  result.passed = false;
  result.failure = String(error.stack ?? error);
  if (page) {
    result.probe = await page.evaluate(() => window.monkeycraftLiveProbe ?? null).catch(() => null);
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
  }
  await updateStatus('failed');
  process.exitCode = 1;
} finally {
  await browser?.close();
  await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
}
