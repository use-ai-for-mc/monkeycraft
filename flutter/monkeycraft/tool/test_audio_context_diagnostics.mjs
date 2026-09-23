import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../lib/audio/audio_context_diagnostics.dart', import.meta.url), 'utf8').match(/r'''([\s\S]*?)''';/)[1];

function createPage() {
  class AudioContext {
    state = 'running';
    currentTime = 12;
    resumes = 0;
    listeners = [];
    constructor(options) { this.options = options; }
    addEventListener(name, listener) { if (name === 'statechange') this.listeners.push(listener); }
    async resume() {
      this.resumes++;
      if (this.rejectResume) throw new Error('blocked');
      this.state = 'running';
      this.listeners.forEach(listener => listener());
    }
  }
  const window = { AudioContext, webkitAudioContext: AudioContext };
  vm.runInNewContext(source, { window, WeakRef });
  return window;
}

test('observation preserves constructors and does not resume or disclose properties', () => {
  const page = createPage();
  class Derived extends page.AudioContext {}
  const context = new Derived({ sampleRate: 48000 });
  context.secretUrl = 'https://example.invalid/private-session';
  assert.ok(context instanceof Derived);
  assert.equal(context.options.sampleRate, 48000);
  assert.equal(page.AudioContext, page.webkitAudioContext);
  const snapshot = JSON.parse(JSON.stringify(page.__monkeyAudioDiagnostics.snapshot()));
  assert.equal(snapshot.length, 1);
  assert.equal(snapshot[0].state, 'running');
  assert.equal(context.resumes, 0);
  assert.ok(!JSON.stringify(snapshot).includes('private-session'));
});

test('one explicit recovery only resumes suspended or interrupted contexts', async () => {
  const page = createPage();
  const contexts = ['running', 'closed', 'suspended', 'interrupted'].map(state => {
    const context = new page.AudioContext();
    context.state = state;
    return context;
  });
  page.__monkeyAudioDiagnostics.resumeOnce();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(contexts.map(context => context.resumes), [0, 0, 1, 1]);
  assert.deepEqual(contexts.map(context => context.state), ['running', 'closed', 'running', 'running']);
});

test('rejected recovery is recorded without an automatic retry loop', async () => {
  const page = createPage();
  const context = new page.AudioContext();
  context.state = 'interrupted';
  context.rejectResume = true;
  page.__monkeyAudioDiagnostics.resumeOnce();
  await new Promise(resolve => setImmediate(resolve));
  const snapshot = page.__monkeyAudioDiagnostics.snapshot()[0];
  assert.equal(snapshot.attempts, 1);
  assert.equal(snapshot.failures, 1);
  assert.equal(context.resumes, 1);
});
