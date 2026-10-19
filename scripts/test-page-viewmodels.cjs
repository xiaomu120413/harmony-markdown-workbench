const assert = require('node:assert/strict');
const path = require('node:path');
const createLoader = require('./lib/ets-loader.cjs');
const toasts = [];
const load = createLoader({
  '@kit.AbilityKit': {}, '@kit.ArkData': {}, '@kit.CoreFileKit': {}, '@kit.ArkTS': {},
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkUI': { promptAction: { showToast: value => toasts.push(value) } },
}, { Observed: cls => cls });
const root = path.join(__dirname, '../entry/src/main/ets');
const { SettingsState } = load(`${root}/features/settings/SettingsState`);
const { SettingsViewModel } = load(`${root}/features/settings/SettingsViewModel`);
const { RecoveryState } = load(`${root}/features/recovery/RecoveryState`);
const { RecoveryViewModel } = load(`${root}/features/recovery/RecoveryViewModel`);
const { RecoveryDecision } = load(`${root}/domain/recovery/DraftDecision`);
(async () => {
  const state = new SettingsState(), vm = new SettingsViewModel(state, {}), writes = [];
  let release;
  vm.store.save = async settings => { writes.push(settings); if (writes.length === 1) await new Promise(r => { release = r; }); };
  state.fontSize = 18; const first = vm.persist();
  await Promise.resolve(); state.fontSize = 20; const second = vm.persist();
  await Promise.resolve(); assert.equal(writes.length, 1);
  release(); await Promise.all([first, second]); assert.deepEqual(writes.map(s => s.fontSize), [18, 20]);
  vm.store.save = async () => { throw Error('full'); };
  await vm.persist(); assert.equal(toasts.length, 1);
  vm.store.save = async settings => writes.push(settings); await vm.persist();
  assert.equal(writes.at(-1).fontSize, 20);
  vm.adjustFont(1000); assert.ok(state.fontSize < 1000);

  let completeLoad; vm.store.load = () => new Promise(r => { completeLoad = r; });
  const pending = vm.load(); const previous = state.fontSize; vm.dispose();
  completeLoad({ fontSize: 12 }); await pending; assert.equal(state.fontSize, previous);

  const recovery = new RecoveryViewModel(new RecoveryState(), {});
  let removed = 0, attempted = 0;
  recovery.store.remove = () => removed++;
  recovery.store.listAll = () => [];
  recovery.internal.listLibrary = () => [];
  recovery.internal.write = async () => { attempted++; return { ok: false, reason: 'io', message: 'full' }; };
  const row = { decision: RecoveryDecision.CONFLICT, decisionName: 'conflict', draft: {
    documentId: 'draft', sourceFingerprint: 'internal:library/test.md', content: '# recovered',
    baseRevision: { size: 0, contentHash: '' }, updatedAt: 1 } };
  await recovery.restoreRow(row); assert.equal(attempted, 0);
  await recovery.saveCopy(row); assert.equal(attempted, 1); assert.equal(removed, 0);
  recovery.internal.write = async () => ({ ok: true }); recovery.trackRecent = async () => {};
  await recovery.saveCopy(row); assert.equal(removed, 1);
  console.log('7 page ViewModel scenarios passed (serialized settings, failure/retry, validation, lifecycle, recovery protection)');
})().catch(error => { console.error(error); process.exitCode = 1; });
