const assert = require('node:assert/strict');
const path = require('node:path');
const createLoader = require('./lib/ets-loader.cjs');
const calls = [], logs = [];
let supported, persisted, persist, activate, openError;
const fileShare = {
  OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
  async checkPersistentPermission(p) { calls.push(['check', p]); return [persisted(p[0].operationMode)]; },
  async persistPermission(p) { calls.push(['persist', p]); return persist(p[0].operationMode); },
  async activatePermission(p) { calls.push(['activate', p]); return activate(p[0].operationMode); },
};
const load = createLoader({
  '@kit.CoreFileKit': { fileShare, fileIo: {
    OpenMode: { READ_ONLY: 1 },
    openSync(uri, mode) { calls.push(['open', uri, mode]); if (openError) throw openError; return { fd: 7 }; },
    statSync: () => ({ size: 0, mtime: 0 }), readSync: () => 0, closeSync() {},
  } },
  '@kit.PerformanceAnalysisKit': { hilog: { info: (...v) => logs.push(v), warn: (...v) => logs.push(v) } },
  '@kit.ArkTS': { util: { TextDecoder: { create: () => ({ decodeToString: () => '' }) } } },
}, { canIUse: () => supported });
const root = path.join(__dirname, '../entry/src/main/ets');
const { ExternalFileAccess } = load(`${root}/infrastructure/file/ExternalFileAccess`);
const { ExternalUriFileSource } = load(`${root}/infrastructure/file/ExternalUriFileSource`);
const uri = 'file://docs/private-name.md';
const source = { kind: 'external', uri, displayName: 'private-name.md' };
function reset() {
  supported = true; persisted = () => false; persist = () => {}; activate = () => {};
  openError = undefined; calls.length = 0; logs.length = 0;
}
function error(code) { return Object.assign(Error(uri), { code }); }
(async () => {
  reset(); supported = false;
  assert.equal(await ExternalFileAccess.prepare(uri), false); assert.equal(calls.length, 0);

  reset(); assert.equal(await ExternalFileAccess.prepare(uri), true);
  assert.deepEqual(calls.map(v => v[0]), ['check', 'persist', 'activate']);
  assert.equal(calls[1][1][0].uri, uri); assert.equal(calls[1][1][0].operationMode, 3);

  reset(); persisted = () => true;
  assert.equal(await ExternalFileAccess.prepare(uri), true);
  assert.deepEqual(calls.map(v => v[0]), ['check', 'activate']);

  reset(); persist = mode => { if (mode === 3) throw error(13900001); };
  assert.equal(await ExternalFileAccess.prepare(uri), true);
  assert.equal(calls.at(-1)[1][0].operationMode, 1);

  reset(); persist = () => { throw error(201); };
  assert.equal(await ExternalFileAccess.prepare(uri), false);
  assert.equal(calls.filter(v => v[0] === 'activate').length, 0);
  assert.ok(!JSON.stringify(logs).includes('private-name'));

  reset(); persisted = () => true; activate = () => { throw error(13900001); };
  assert.equal(await ExternalFileAccess.prepare(uri), false);

  reset(); persist = () => { throw error(201); };
  const adapter = new ExternalUriFileSource();
  assert.equal((await adapter.read(source)).content, '');
  assert.equal(calls.at(-1)[0], 'open'); // Temporary grant remains usable without approval.

  reset(); persisted = () => true;
  await adapter.read(source);
  assert.ok(calls.findIndex(v => v[0] === 'activate') < calls.findIndex(v => v[0] === 'open'));
  assert.equal(await adapter.canPersistAccess(source), true);

  reset(); persist = () => { throw error(13900001); }; openError = error(13900001);
  await assert.rejects(adapter.read(source), { code: 13900001 });
  assert.equal((await adapter.write(source, 'keep original', { size: 0, contentHash: '' })).reason, 'permission');
  assert.ok(calls.filter(v => v[0] === 'open').every(v => v[1] === uri && v[2] === 1));
  assert.equal(await adapter.canPersistAccess(source), false);
  console.log('9 external access scenarios passed (grant, restart, read-only, denial, revocation, temporary fallback, write blocking)');
})().catch(e => { console.error(e); process.exitCode = 1; });
