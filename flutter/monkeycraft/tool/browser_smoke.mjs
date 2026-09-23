import { chromium } from '../../../web/node_modules/@playwright/test/index.mjs';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const url = process.env.FLUTTER_WEB_URL ?? 'http://127.0.0.1:4175/monkeycraft/?debug=1';
const server = process.env.FLUTTER_REPLAY_URL ?? 'ws://127.0.0.1:9611';
const output = path.resolve(process.env.FLUTTER_WEB_EVIDENCE ?? 'outputs/flutter-web-feasibility-2026-09-19/ui-smoke');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: process.env.FLUTTER_HEADED !== '1' });
const result = { url, server, checks: [], errors: [] };
let page;
try {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, permissions: ['notifications'] });
  await context.grantPermissions(['notifications'], { origin: new URL(url).origin });
  await context.addInitScript(() => {
    window.flutterProbe = { decoders: 0, decoded: 0, errors: 0, tones: 0, sockets: [], sent: [], sizes: [], pointerEvents: [], received: [] };
    const NativeDecoder = window.VideoDecoder;
    window.VideoDecoder = class extends NativeDecoder {
      constructor(config) {
        super({ ...config, output: frame => {
          window.flutterProbe.decoded++;
          const size = `${frame.displayWidth}x${frame.displayHeight}`;
          if (!window.flutterProbe.sizes.includes(size)) window.flutterProbe.sizes.push(size);
          config.output(frame);
        }, error: error => { window.flutterProbe.errors++; config.error(error); } });
        window.flutterProbe.decoders++;
      }
    };
    const NativeSocket = window.WebSocket;
    window.WebSocket = class extends NativeSocket {
      constructor(...args) { super(...args); window.flutterProbe.sockets.push(this); this.addEventListener('message', e => {if(typeof e.data==='string'){const msg=JSON.parse(e.data); if(!['HELLO','AUTH_OK','PAIR_OK'].includes(msg.type)) flutterProbe.received.push(msg);}}); }
      send(data) {
        if (typeof data === 'string') {
          const parsed = JSON.parse(data);
          if (parsed.type !== 'AUTH') window.flutterProbe.sent.push(parsed);
        }
        return super.send(data);
      }
    };
    const lock = Element.prototype.requestPointerLock;
    Element.prototype.requestPointerLock = function (...args) {
      flutterProbe.pointerEvents.push({event:'request',tag:this.tagName,connected:this.isConnected,active:document.hasFocus()});
      const result = lock.apply(this, args);
      result?.then(() => flutterProbe.pointerEvents.push('resolved'), e => flutterProbe.pointerEvents.push(e.name + ': ' + e.message));
      return result;
    };
    const unlock = Document.prototype.exitPointerLock;
    Document.prototype.exitPointerLock = function (...args) { flutterProbe.pointerEvents.push('exit'); return unlock.apply(this, args); };
    document.addEventListener('pointerlockchange', () => flutterProbe.pointerEvents.push(document.pointerLockElement ? 'locked' : 'unlocked'));
    const start = OscillatorNode.prototype.start;
    OscillatorNode.prototype.start = function (...args) { window.flutterProbe.tones++; return start.apply(this, args); };
  });
  page = await context.newPage();
  page.on('pageerror', e => result.errors.push(e.message));
  result.console = [];
  page.on('console', m => result.console.push(m.text()));
  await page.goto(url);
  await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
  const edit = async (name, value) => {
    const field = page.getByRole('textbox', { name, exact: true });
    await field.click();
    await page.waitForTimeout(200);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type(value, { delay: 10 });
    await page.waitForTimeout(100);
  };
  const changeServer = page.getByRole('button', { name: 'Change', exact: true });
  if (await changeServer.count()) await changeServer.click();
  await edit('Server address', server);
  const passwordMode = page.getByText('Use password or scan QR', { exact: true });
  if (await passwordMode.count()) await passwordMode.click();
  await edit('Password', 'incorrect');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => document.body.innerText.includes('Invalid') || document.body.innerText.includes('failed') || document.body.innerText.includes('password did not match'));
  result.checks.push('wrong password rejected');
  await page.waitForTimeout(900);
  await edit('Password', 'test');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => window.flutterProbe.decoded >= 20);
  const stats = () => page.evaluate(() => ({ decoders: flutterProbe.decoders, decoded: flutterProbe.decoded, errors: flutterProbe.errors, tones: flutterProbe.tones, sockets: flutterProbe.sockets.length, sizes: flutterProbe.sizes }));
  const baseline = await stats();
  assert.equal(baseline.errors, 0);
  result.checks.push('Flutter login and real H264 decoding');
  await page.screenshot({ path: path.join(output, 'stream.png') });
  for (const viewport of [{ width: 900, height: 700 }, { width: 430, height: 900 }, { width: 1400, height: 850 }, { width: 1280, height: 800 }]) {
    await page.setViewportSize(viewport);
    await page.waitForTimeout(180);
  }
  await page.waitForFunction(n => window.flutterProbe.decoded >= n + 15, baseline.decoded);
  const resized = await stats();
  assert.equal(resized.decoders, baseline.decoders);
  assert.equal(resized.sockets, baseline.sockets);
  assert.equal(resized.errors, 0);
  result.checks.push('resize preserves decoder, socket and continuing frames');
  const inject = msg => page.evaluate(msg => {
    const ws = flutterProbe.sockets.at(-1);
    ws.send(JSON.stringify({ type: 'RUN_COMMAND', command: `/replay emit ${JSON.stringify(msg)}` }));
  }, msg);
  await page.bringToFront();
  await page.mouse.click(640, 350);
  await page.waitForFunction(() => document.pointerLockElement !== null || flutterProbe.pointerEvents.some(e => typeof e === 'string' && e.startsWith('WrongDocumentError')));
  const pointerLocked = await page.evaluate(() => document.pointerLockElement !== null);
  if (!pointerLocked) { result.pointerLockBlocked = await page.evaluate(() => flutterProbe.pointerEvents); await page.mouse.down(); }
  await page.mouse.move(680, 365);
  await page.waitForFunction(() => flutterProbe.sent.some(m => m.type === 'LOOK_DELTA'));
  if (!pointerLocked) await page.mouse.up();
  await page.keyboard.down('w');
  await page.waitForFunction(() => flutterProbe.sent.some(m => m.type === 'INPUT' && m.key === 'W' && m.pressed));
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await page.waitForFunction(() => document.pointerLockElement === null && flutterProbe.sent.some(m => m.type === 'INPUT' && m.key === 'W' && !m.pressed));
  await page.keyboard.up('w');
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await page.locator('flutter-view').focus();
  await page.waitForTimeout(300);
  result.checks.push(pointerLocked ? 'actual pointer lock and free movement; blur releases W and mouse' : 'drag fallback movement; blur releases W; pointer lock remains environment-blocked');
  await inject({ type: 'SCREEN_STATE', isOpen: true });
  await page.waitForTimeout(250);
  await page.locator('flutter-view').focus();
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => flutterProbe.sent.some(m => m.type === 'SCREEN_KEY' && m.key === 'ESCAPE' && m.pressed === false));
  await inject({ type: 'SCREEN_STATE', isOpen: false });
  result.checks.push('menu escape sends down and up');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByText('Enable reminders', { exact: true }).scrollIntoViewIfNeeded();
  await page.getByText('Enable reminders', { exact: true }).click();
  await page.waitForTimeout(300);
  await page.getByText('Test sound', { exact: true }).click();
  await page.waitForFunction(() => flutterProbe.tones === 1);
  result.browserPermission = await page.evaluate(() => Notification.permission);
  await inject({ type: 'NUDGE', title: 'Flutter silent', body: 'Silent page reminder', sound: false });
  await page.waitForTimeout(250);
  result.silentReminderProbe = await page.evaluate(() => [...document.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')).filter(label => label?.includes('Flutter silent')));
  await page.screenshot({ path: path.join(output, 'silent-reminder-immediate.png') });
  await page.locator('[aria-label*="Flutter silent"]').waitFor();
  assert.equal((await stats()).tones, 1);
  await inject({ type: 'NUDGE', title: 'Flutter audible', body: 'One tone', sound: true });
  await page.locator('[aria-label*="Flutter audible"]').waitFor();
  assert.equal((await stats()).tones, 2);
  await inject({ type: 'NUDGE', title: 'Flutter audible', body: 'One tone', sound: true });
  await page.waitForTimeout(150);
  assert.equal((await stats()).tones, 2);
  if (result.browserPermission === 'granted' && await page.evaluate(() => isSecureContext && 'serviceWorker' in navigator)) {
    const observer = await context.newPage();
    await observer.goto('about:blank');
    await observer.bringToFront();
    await page.waitForFunction(() => document.hidden);
    await inject({ type: 'NUDGE', title: 'Flutter system silent', body: 'Simulated-permission background notification', sound: false });
    await page.waitForFunction(async () => !!(await navigator.serviceWorker.getRegistration())?.active, { timeout: 5000 });
    result.systemNotificationProbe = await page.evaluate(async () => {
      const registration = await navigator.serviceWorker.getRegistration();
      const notifications = await registration?.getNotifications({ tag: 'monkeycraft-immediate' }) ?? [];
      return {
        secure: isSecureContext,
        registrationActive: !!registration?.active,
        notifications: notifications.map(notification => ({ title: notification.title, silent: notification.silent, tag: notification.tag })),
      };
    });
    assert.ok(result.systemNotificationProbe.notifications.some(notification => notification.title === 'Flutter system silent' && notification.silent === true));
    await page.bringToFront();
    await observer.close();
  } else {
    result.systemNotificationProbe = {
      secure: await page.evaluate(() => isSecureContext),
      skipped: `notification permission is ${result.browserPermission}; Playwright headless permission emulation did not grant it`,
    };
  }
  result.checks.push('settings enable/test sound; silent/audible/deduplicated page banners');
  const timedToneBaseline = (await stats()).tones;
  const fireAt = await page.evaluate(() => Date.now() + 1800);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: fireAt, timedTitle: 'Flutter timer', timedBody: 'Initial timer', timedSound: true, timedCountDownText: 'Timer' });
  await page.waitForTimeout(180);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: fireAt, timedTitle: 'Flutter timer update', timedBody: 'Updated timer', timedSound: true, timedCountDownText: 'Updated' });
  await page.locator('[aria-label*="Flutter timer update"]').waitFor({ timeout: 5000 });
  await page.waitForFunction(n => window.flutterProbe.tones === n + 1, timedToneBaseline);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: fireAt, timedTitle: 'Flutter timer update', timedBody: 'Updated timer', timedSound: true, timedCountDownText: 'Updated' });
  await page.waitForTimeout(250);
  assert.equal((await stats()).tones, timedToneBaseline + 1);
  const cancelledFireAt = await page.evaluate(() => Date.now() + 900);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: cancelledFireAt, timedTitle: 'Flutter cancelled', timedBody: 'Must not alert', timedSound: true, timedCountDownText: 'Cancelled' });
  await page.waitForTimeout(150);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: null });
  await page.waitForTimeout(1000);
  assert.equal(await page.locator('[aria-label*="Flutter cancelled"]').count(), 0);
  assert.equal((await stats()).tones, timedToneBaseline + 1);
  const expiredAt = await page.evaluate(() => Date.now() - 1000);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: expiredAt, timedTitle: 'Flutter expired', timedBody: 'Must not replay', timedSound: true, timedCountDownText: 'Expired' });
  await page.waitForTimeout(250);
  await inject({ type: 'SERVER_STATUS', videoState: 'ACTIVE', timedFireAtEpochMs: expiredAt, timedTitle: 'Flutter expired', timedBody: 'Must not replay', timedSound: true, timedCountDownText: 'Expired' });
  await page.waitForTimeout(250);
  assert.equal(await page.locator('[aria-label*="Flutter expired"]').count(), 0);
  assert.equal((await stats()).tones, timedToneBaseline + 1);
  result.checks.push('timed reminder create/update fires once; cancellation and expired replay stay silent');
  const reconnectBaseline = await stats();
  await page.evaluate(() => flutterProbe.sockets.at(-1).send(JSON.stringify({ type: 'RUN_COMMAND', command: '/replay close 4000' })));
  await page.waitForFunction(n => flutterProbe.sockets.length > n, reconnectBaseline.sockets, { timeout: 8000 });
  await page.waitForFunction(n => flutterProbe.decoded >= n + 12, reconnectBaseline.decoded, { timeout: 8000 });
  result.checks.push('server close reconnects and restores decoded frames');
  await page.screenshot({ path: path.join(output, 'reminder-settings.png') });
  await page.reload();
  await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
  const restoredServer = page.getByRole('textbox', { name: 'Server address', exact: true });
  await page.waitForFunction(() => window.flutterProbe.decoded >= 12, { timeout: 8000 });
  result.checks.push('reload restores same-target credentials and reconnects');
  await page.getByRole('button', { name: 'Disconnect', exact: true }).click();
  await page.getByRole('button', { name: 'Change', exact: true }).click();
  await restoredServer.waitFor();
  await edit('Server address', 'ws://127.0.0.1:1');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => document.body.innerText.includes('Enter the password'));
  result.checks.push('target change clears autofill before connect');
  result.final = await stats();
  assert.equal(result.final.errors, 0);
  assert.deepEqual(result.errors, []);
  result.passed = true;
} catch (error) {
  result.passed = false;
  result.failure = String(error.stack ?? error);
  if (page) { result.probe = await page.evaluate(() => ({decoded: window.flutterProbe?.decoded, decoders: window.flutterProbe?.decoders, socketCount: window.flutterProbe?.sockets.length, pointerEvents: window.flutterProbe?.pointerEvents, received: window.flutterProbe?.received.slice(-12), sent: window.flutterProbe?.sent.filter(m => !['ACK','AUTH'].includes(m.type)).slice(-15)})).catch(() => null); await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); result.body = await page.locator('body').innerText().catch(() => ''); }
  process.exitCode = 1;
} finally {
  await browser.close();
  await writeFile(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
}
