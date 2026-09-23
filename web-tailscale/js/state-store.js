export async function openStateStore(name = 'monkeycraft-tailscale-v1') {
  if (!globalThis.indexedDB || !globalThis.navigator?.locks) {
    throw new Error('This browser cannot save Tailscale sign-in. Use a current browser over HTTPS.');
  }
  let release;
  let acquired;
  const ready = new Promise((resolve, reject) => { acquired = { resolve, reject }; });
  const lock = navigator.locks.request(name, { ifAvailable: true }, async held => {
    if (!held) { acquired.reject(new Error('Tailscale is open in another tab. Close that tab and try again.')); return; }
    await new Promise(resolve => { release = resolve; acquired.resolve(); });
  });
  lock.catch(acquired.reject);
  await ready;
  let db;
  try {
    db = await new Promise((resolve, reject) => {
      const request = indexedDB.open(name, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('state');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(new Error('Cannot open browser storage for Tailscale.'));
    });
    const values = new Map();
    await new Promise((resolve, reject) => {
      const tx = db.transaction('state', 'readonly');
      const cursor = tx.objectStore('state').openCursor();
      cursor.onsuccess = () => {
        const item = cursor.result;
        if (item) { values.set(item.key, item.value); item.continue(); }
      };
      tx.oncomplete = resolve;
      tx.onabort = () => reject(new Error('Cannot read saved Tailscale sign-in.'));
    });
    let pending = Promise.resolve();
    let failure;
    let cleared = false;
    const mutate = operation => {
      pending = pending.then(() => new Promise((resolve, reject) => {
        const tx = db.transaction('state', 'readwrite');
        operation(tx.objectStore('state'));
        tx.oncomplete = resolve;
        tx.onabort = () => reject(new Error('Cannot save Tailscale sign-in. Check browser storage.'));
      })).catch(error => { failure = error; });
    };
    return {
      getState: id => values.get(String(id)) || '',
      setState(id, value) {
        if (cleared) return;
        const key = String(id), text = String(value);
        values.set(key, text);
        mutate(store => store.put(text, key));
      },
      async flush() { await pending; if (failure) throw failure; },
      async clear() {
        cleared = true;
        values.clear();
        mutate(store => store.clear());
        await this.flush();
      },
      async close() { cleared = true; try { await this.flush(); } finally { db.close(); release(); await lock; } },
    };
  } catch (error) { db?.close(); release(); throw error; }
}
