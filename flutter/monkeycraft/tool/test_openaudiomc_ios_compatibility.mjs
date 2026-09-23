import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../lib/audio/openaudiomc_webview_script.dart', import.meta.url), 'utf8').match(/r'''([\s\S]*?)''';/)[1];
function createPage(hostname = 'session.openaudiomc.net') {
  class Media {
    muted = false; calls = 0;
    constructor(tagName, title) { this.tagName = tagName; this.title = title; }
    getAttribute(name) { return name === 'title' ? this.title : null; }
    play(...args) {
      if (!(this instanceof Media)) throw new TypeError('invalid receiver');
      this.calls++; this.args = args; this.mutedAtPlay = this.muted;
      return this.result = Promise.resolve();
    }
  }
  const environment = {window:{}, HTMLMediaElement:Media, location:{hostname}};
  vm.runInNewContext(source, environment);
  return {Media, environment};
}
test('native OpenAudioMc No Sleep video is muted before playback', () => {
  const {Media} = createPage();
  const video = new Media('VIDEO','No Sleep');
  const result = video.play('argument');
  assert.equal(video.mutedAtPlay, true);
  assert.equal(result, video.result);
  assert.deepEqual(video.args, ['argument']);
});
test('real music and unrelated videos retain their mute state', () => {
  const {Media} = createPage();
  for (const [tag,title] of [['AUDIO','No Sleep'],['AUDIO','Music'],['VIDEO','Music'],['VIDEO',null]]) {
    const media = new Media(tag,title);
    media.play();
    assert.equal(media.mutedAtPlay, false);
  }
});
test('compatibility applies only to the recognized audio client origin', () => {
  const {Media} = createPage('example.invalid');
  const video = new Media('VIDEO','No Sleep'); video.play();
  assert.equal(video.mutedAtPlay, false);
});
test('repeated installation is idempotent and preserves invalid receiver errors', () => {
  const {Media, environment} = createPage();
  const play = Media.prototype.play;
  vm.runInNewContext(source, environment);
  assert.equal(play, Media.prototype.play);
  assert.throws(()=>play.call(null), TypeError);
  const video = new Media('VIDEO','No Sleep'); video.play();
  assert.equal(video.calls, 1);
});
