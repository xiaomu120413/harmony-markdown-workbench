const assert = require('node:assert/strict');
const path = require('node:path');
const createLoader = require('./lib/ets-loader.cjs');
const dialogs = [], storage = new Map();
let select = async () => [], photo = async () => ({ photoUris: [] });
const kits = {
  '@kit.AbilityKit': {}, '@kit.ArkData': {},
  '@kit.ArkWeb': { webview: { WebviewController: class {} } },
  '@kit.CoreFileKit': { picker: { DocumentViewPicker: class { select() { return select(); } },
    PhotoViewPicker: class { select() { return photo(); } }, PhotoViewMIMETypes: { IMAGE_TYPE: 0 } } },
  '@kit.ArkTS': { util: { TextEncoder: { create: () => ({ encodeInto: s => new TextEncoder().encode(s) }) } } },
  '@kit.BasicServicesKit': {},
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkUI': { promptAction: { showToast() {} } },
};
const load = createLoader(kits, { Observed: cls => cls, AlertDialog: { show: d => dialogs.push(d) },
  AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) } });
const root = path.join(__dirname, '../entry/src/main/ets');
const { EditorState } = load(`${root}/features/editor/EditorState`);
const { EditorController } = load(`${root}/features/editor/EditorController`);
const { SaveCoordinator } = load(`${root}/services/SaveCoordinator`);
const { DocumentDeliveryService } = load(`${root}/services/DocumentDeliveryService`);
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function fixture() {
  storage.clear(); dialogs.length = 0;
  const state = new EditorState();
  Object.assign(state, { docTitle: 'source.md',
    docTarget: { kind: 'internal', relativePath: 'library/source.md' } });
  const actions = new EditorController(state, {}, { filesDir: '/files', cacheDir: '/cache' });
  Object.assign(actions.env, { activeSession: 'original', webReady: true });
  actions.env.external.retainAccess = async () => false;
  const scripts = [], checkpoints = [], removed = [], writes = [];
  let text = '# Current snapshot', version = 1;
  actions.runJsChecked = async (_, script) => { scripts.push(script); return ''; };
  actions.getSnapshotData = async () => ({ ok: true, sessionId: actions.env.activeSession, version, content: text });
  actions.inspectImages = async () => [];
  actions.renderForDelivery = async content => `<p>${content}</p>`;
  actions.doSaveCheckpoint = async content => checkpoints.push(content);
  actions.env.drafts.remove = id => removed.push(id);
  actions.env.external.write = async (target, content) => { writes.push({ target, content });
    return { ok: true, revision: { size: content.length, contentHash: 'new' } }; };
  actions.trackRecent = async () => {};
  actions.refreshSidebarData = () => {};
  const c = new SaveCoordinator({ getSnapshot: () => actions.getSnapshotData(),
    saveCheckpoint: content => actions.doSaveCheckpoint(content), persist: () => { throw Error('unexpected original write'); } });
  c.onDocumentLoaded('original', 0); c.onEdit(1); actions.env.coordinator = c;
  return { state, actions, c, scripts, checkpoints, removed, writes,
    edit(value) { text = value; actions.env.coordinator.onEdit(++version); } };
}
const result = { uri: 'file://docs/new-target', fileName: 'new-target', remoteImages: false };
(async () => {
  let f = fixture(); DocumentDeliveryService.prototype.markdown = async () => undefined;
  await f.actions.deliverDocument(0);
  assert.equal(f.actions.env.coordinator, f.c); assert.equal(f.state.docTitle, 'source.md');
  assert.equal(f.removed.length, 0); assert.deepEqual(f.checkpoints, ['# Current snapshot']);
  assert.ok(f.scripts.at(-1).includes('setEditable(true)')); assert.equal(f.state.deliveryBusy, false);

  f = fixture(); DocumentDeliveryService.prototype.markdown = async () => { throw Error('full'); };
  await f.actions.deliverDocument(0);
  assert.equal(f.actions.env.coordinator, f.c); assert.equal(f.removed.length, 0); assert.equal(dialogs.length, 1);
  assert.equal(f.state.docTarget.kind, 'internal'); assert.equal(f.state.deliveryBusy, false);

  f = fixture(); DocumentDeliveryService.prototype.markdown = async () => result;
  await f.actions.deliverDocument(0);
  assert.equal(f.state.docTitle, 'new-target'); assert.equal(f.state.docTarget.uri, result.uri);
  assert.notEqual(f.actions.env.coordinator, f.c); assert.equal(f.actions.env.docFormat.encoding, 'utf-8');
  f.edit('follow-up'); await f.actions.save();
  assert.equal(f.writes.length, 1); assert.equal(f.writes[0].target.uri, result.uri);
  assert.equal(f.writes[0].content, 'follow-up');

  for (const action of [1, 2, 3]) {
    f = fixture(); let exported;
    const method = action === 1 ? 'markdown' : action === 2 ? 'zip' : 'html';
    DocumentDeliveryService.prototype[method] = async (_, text) => { exported = text; return result; };
    await f.actions.deliverDocument(action);
    assert.equal(exported, '# Current snapshot'); assert.equal(f.state.docTitle, 'source.md');
    assert.equal(f.actions.env.coordinator, f.c); assert.equal(f.removed.length, 0);
  }

  for (const method of ['openDocument', 'reselectExternalFile']) {
    for (const late of ['disposed', 'switched']) {
      f = fixture(); const gate = deferred(); select = () => gate.promise;
      const pending = f.actions[method]();
      if (late === 'disposed') { f.actions.env.disposed = true; }
      else { f.actions.env.activeSession = 'other-document'; }
      gate.resolve(['file://docs/late.md']); await pending;
      assert.equal(f.actions.env.pendingOpenUri, ''); assert.equal(f.state.docTarget.kind, 'internal');
    }
  }

  f = fixture(); let gate = deferred(); select = () => gate.promise;
  const open = f.actions.openDocument(); gate.resolve(['file://docs/authorized.md']); await open;
  assert.equal(f.actions.env.pendingOpenUri, 'file://docs/authorized.md');

  f = fixture(); gate = deferred(); DocumentDeliveryService.prototype.markdown = () => gate.promise;
  const delivery = f.actions.deliverDocument(0);
  while (!f.checkpoints.length) await Promise.resolve();
  // Let inspectImages complete and the picker operation start.
  for (let i = 0; i < 8; i++) await Promise.resolve();
  f.actions.env.disposed = true; f.actions.env.pendingOpenUri = 'file://docs/next.md';
  let opens = 0; f.actions.onExternalOpen = () => { opens++; };
  const scriptCount = f.scripts.length; gate.resolve(result); await delivery;
  assert.equal(f.state.docTitle, 'source.md'); assert.equal(f.removed.length, 0);
  assert.equal(f.scripts.length, scriptCount); assert.equal(opens, 0);

  f = fixture(); gate = deferred(); f.actions.getSnapshotData = () => gate.promise;
  let picks = 0; DocumentDeliveryService.prototype.markdown = async () => { picks++; return result; };
  const beforePicker = f.actions.deliverDocument(0); await Promise.resolve();
  f.actions.env.disposed = true;
  gate.resolve({ ok: true, sessionId: 'original', version: 1, content: 'late' }); await beforePicker;
  assert.equal(picks, 0); assert.equal(f.checkpoints.length, 0);

  f = fixture(); gate = deferred(); photo = () => gate.promise;
  let copies = 0; f.actions.env.internal.copyToAttachments = () => { copies++; return 'attachments/image.png'; };
  const image = f.actions.insertLocalImage(); f.actions.env.disposed = true;
  gate.resolve({ photoUris: ['file://docs/image.png'] }); await image;
  assert.equal(copies, 0); assert.equal(f.scripts.length, 0);
  console.log('14 file transaction scenarios passed (real controllers/coordinator, platform pickers mocked)');
})().catch(e => { console.error(e); process.exitCode = 1; });
