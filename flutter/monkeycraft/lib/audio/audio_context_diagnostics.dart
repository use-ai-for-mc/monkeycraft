const audioContextDiagnosticSource = r'''
(() => {
  if (window.__monkeyAudioDiagnostics || typeof WeakRef !== 'function') return;
  let entries = [];
  const live = () => {
    entries = entries.filter(entry => entry.ref.deref());
    return entries;
  };
  const wrappers = new Map();
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const Original = window[name];
    if (typeof Original !== 'function') continue;
    if (!wrappers.has(Original)) {
      wrappers.set(Original, new Proxy(Original, {
        construct(target, args, newTarget) {
          const context = Reflect.construct(target, args, newTarget);
          const entry = {ref: new WeakRef(context), attempts: 0, failures: 0, events: []};
          const changed = () => {
            entry.events.push({at: Date.now(), state: context.state, time: context.currentTime});
            if (entry.events.length > 12) entry.events.shift();
          };
          changed();
          context.addEventListener('statechange', changed);
          entries.push(entry);
          return context;
        }
      }));
    }
    window[name] = wrappers.get(Original);
  }
  window.__monkeyAudioDiagnostics = {
    snapshot() {
      return live().slice(0, 8).map(entry => {
        const context = entry.ref.deref();
        return {state: context.state, time: context.currentTime,
          attempts: entry.attempts, failures: entry.failures, events: entry.events.slice()};
      });
    },
    resumeOnce() {
      for (const entry of live()) {
        const context = entry.ref.deref();
        if (!context || !['suspended', 'interrupted'].includes(context.state)) continue;
        entry.attempts++;
        try {
          Promise.resolve(context.resume()).catch(() => entry.failures++);
        } catch (_) {
          entry.failures++;
        }
      }
      return true;
    }
  };
})();
''';
