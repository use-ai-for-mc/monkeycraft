const audioMediaDiagnosticSource = r'''
(() => {
  if (window.__monkeyMediaDiagnostics || typeof WeakRef !== 'function') return;
  const entries = [];
  let nextId = 1;
  const observed = new WeakMap();
  const record = (entry, event, media) => {
    entry.events.push({at: Date.now(), event, hidden: document.hidden,
      paused: media.paused, time: media.currentTime});
    if (entry.events.length > 16) entry.events.shift();
  };
  const observe = media => {
    if (observed.has(media)) return observed.get(media);
    const entry = {ref: new WeakRef(media), events: [], id: nextId++};
    observed.set(media, entry);
    entries.push(entry);
    if (entries.length > 128) entries.shift();
    for (const event of ['play', 'playing', 'pause', 'ended', 'emptied', 'stalled', 'error']) {
      media.addEventListener(event, () => record(entry, event, media));
    }
    return entry;
  };
  const time = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
  if (time?.get && time.configurable) {
    Object.defineProperty(HTMLMediaElement.prototype, 'currentTime', {
      ...time,
      get() {
        const value = Reflect.apply(time.get, this, []);
        observe(this);
        return value;
      }
    });
  }
  for (const name of ['play', 'pause']) {
    const original = HTMLMediaElement.prototype[name];
    HTMLMediaElement.prototype[name] = new Proxy(original, {
      apply(target, receiver, args) {
        const result = Reflect.apply(target, receiver, args);
        record(observe(receiver), name + '-call', receiver);
        return result;
      }
    });
  }
  window.__monkeyMediaDiagnostics = {
    resumeOnce(ids) {
      let requested = 0;
      for (const entry of entries) {
        const media = entry.ref.deref();
        if (!ids.includes(entry.id) || !media || !media.paused || media.ended || !media.currentSrc) continue;
        requested++;
        try { Promise.resolve(media.play()).catch(() => record(entry, 'resume-rejected', media)); }
        catch (_) { record(entry, 'resume-rejected', media); }
      }
      return requested;
    },
    snapshot() {
      document.querySelectorAll('audio,video').forEach(observe);
      return entries.filter(entry => entry.ref.deref()).slice(-32).map(entry => {
        const e = entry.ref.deref();
        return {id: entry.id, inDocument: e.isConnected,
          paused: e.paused, ended: e.ended, muted: e.muted, volume: e.volume,
          time: e.currentTime, duration: Number.isFinite(e.duration) ? e.duration : null,
          ready: e.readyState, network: e.networkState, rate: e.playbackRate,
          hasSource: !!e.currentSrc, error: e.error ? e.error.code : null,
          events: entry.events.slice()};
      });
    }
  };
})();
''';
