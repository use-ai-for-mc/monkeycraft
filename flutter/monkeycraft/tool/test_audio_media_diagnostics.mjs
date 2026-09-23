import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../lib/audio/audio_media_diagnostics.dart', import.meta.url), 'utf8').match(/r'''([\s\S]*?)''';/)[1];
function createPage() {
  class Media {
    paused = true; ended = false; muted = false; volume = 1;
    time = 0; duration = 300; readyState = 4; networkState = 1;
    playbackRate = 1; currentSrc = 'https://example.invalid/private-session';
    isConnected = false; listeners = new Map(); plays = 0;
    get currentTime() { return this.time; }
    set currentTime(value) { this.time = value; }
    addEventListener(type, fn) { this.listeners.set(type, fn); }
    emit(type) { this.listeners.get(type)?.(); }
    play() { this.plays++; this.paused = false; return this.result = Promise.resolve(); }
    pause() { this.paused = true; }
  }
  const document = {hidden:false, querySelectorAll: () => []};
  const window = {};
  vm.runInNewContext(source, {window, document, HTMLMediaElement:Media, WeakRef});
  return {Media, document, diagnostics: window.__monkeyMediaDiagnostics};
}
test('detached media observation preserves playback result and does not replay', () => {
  const {Media, diagnostics} = createPage();
  const media = new Media();
  const result = media.play();
  assert.equal(result, media.result);
  media.emit('playing');
  media.pause();
  const [state] = diagnostics.snapshot();
  assert.equal(state.inDocument, false);
  assert.equal(state.paused, true);
  assert.equal(media.plays, 1);
  assert.ok(!JSON.stringify(state).includes('private-session'));
});
test('existing media can be observed through unchanged clock getter and setter', () => {
  const {Media, diagnostics} = createPage();
  const media = new Media();
  media.currentTime = 31;
  assert.equal(media.currentTime, 31);
  assert.equal(diagnostics.snapshot()[0].time, 31);
  assert.equal(media.plays, 0);
});
test('native pause is distinguishable from JavaScript pause and event history is bounded', () => {
  const {Media, document, diagnostics} = createPage();
  const media = new Media();
  media.play();
  document.hidden = true;
  for (let i=0;i<40;i++) media.emit('playing');
  document.hidden = false;
  media.paused = true;
  media.emit('pause');
  const [state] = diagnostics.snapshot();
  assert.equal(state.events.length, 16);
  assert.equal(state.events.at(-1).event, 'pause');
  assert.equal(state.events.at(-1).hidden, false);
  assert.ok(!state.events.some(event=>event.event==='pause-call'));
});
test('explicit one-shot recovery targets only selected paused live media', async () => {
  const {Media, diagnostics} = createPage();
  const items = Array.from({length:4}, () => { const e = new Media(); e.play(); e.pause(); return e; });
  items[1].ended = true;
  items[2].currentSrc = '';
  assert.equal(diagnostics.resumeOnce([1,2,3]), 1);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(items.map(e=>e.plays), [2,1,1,1]);
});
