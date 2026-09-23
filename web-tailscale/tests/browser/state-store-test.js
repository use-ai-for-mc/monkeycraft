export async function testStateStore(openStateStore) {
  const name = `monkeycraft-state-test-${crypto.randomUUID()}`;
  const check = (condition, label) => { if (!condition) throw new Error(label); };
  let store;
  try {
    store = await openStateStore(name);
    store.setState('test-state', 'first');
    store.setState('test-state', 'second');
    await store.flush();
    let excluded = false;
    try { await openStateStore(name); } catch (e) { excluded = e.message.includes('another tab'); }
    check(excluded, 'concurrent identity owner must be excluded');
    await store.close();
    store = await openStateStore(name);
    check(store.getState('test-state') === 'second', 'saved identity must survive reopening');
    await store.clear();
    store.setState('test-state', 'late write after logout');
    await store.close();
    store = await openStateStore(name);
    check(store.getState('test-state') === '', 'logout must not restore stale identity');
    return {persisted: true, concurrentOwnerRejected: true, cleared: true};
  } finally {
    await store?.close();
    indexedDB.deleteDatabase(name);
  }
}
