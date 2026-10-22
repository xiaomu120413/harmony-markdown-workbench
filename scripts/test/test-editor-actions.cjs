const path = require('node:path');
const assert = require('node:assert/strict');
const createLoader = require('./lib/ets-loader.cjs');
const dialogs = [], toasts = [], routes = [], storage = new Map();
const kits = {
  '@kit.ArkWeb': { webview: { WebviewController: class {} } },
  '@kit.AbilityKit': {}, '@kit.CoreFileKit': {}, '@kit.ArkTS': {},
  '@kit.ArkData': {}, '@kit.BasicServicesKit': {},
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkUI': { promptAction: { showToast: d => toasts.push(d) },
    router: { replaceUrl: async r => routes.push(r), getState: () => ({ name: 'HomePage' }), pushUrl: async r => routes.push(r) } },
};
const load = createLoader(kits, {
  canIUse: () => false, Observed: cls => cls, AlertDialog: { show: d => dialogs.push(d) },
  AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) },
});
const root = path.join(__dirname, '../../entry/src/main/ets');
const { EditorState } = load(`${root}/features/editor/EditorState`);
const { EditorController } = load(`${root}/features/editor/EditorController`);
const { HomeState } = load(`${root}/features/home/HomeState`);
const { HomeController } = load(`${root}/features/home/HomeController`);
function fixture() {
  const state = new EditorState({ filesDir: '/test', cacheDir: '/cache' });
  state.bp = 'pc'; state.contentWidthVp = 1200;
  const actions = new EditorController(state, {}, { filesDir: '/test', cacheDir: '/cache' });
  let syncs = 0;
  actions.syncDocNow = () => syncs++;
  actions.runJsValue = async () => '# Heading\nBody';
  return { state, actions, syncs: () => syncs };
}
(async () => {
  const derived = new EditorState();
  derived.findMatches = [{ from: 0, to: 5 }, { from: 6, to: 11 }];
  assert.equal(derived.matchCount, 2);
  derived.findMatches = []; assert.equal(derived.matchCount, 0);
  derived.saveState = 'conflict'; assert.equal(derived.conflictVisible, true);
  assert.equal(derived.saveLabel, '外部冲突');
  derived.loadState = 'loading'; assert.equal(derived.saveLabel, '正在打开');
  derived.loadState = 'accessExpired'; assert.equal(derived.saveLabel, '未打开');
  derived.loadState = 'ready'; derived.saveState = 'clean';
  assert.equal(derived.conflictVisible, false); assert.equal(derived.saveLabel, '已保存');
  const wide = fixture();
  wide.actions.toggleOutline(); assert.equal(wide.state.outlineVisible, true); assert.equal(wide.syncs(), 1);
  wide.actions.toggleOutline(); assert.equal(wide.state.outlineVisible, false);

  const narrow = fixture(); narrow.state.bp = 'phone'; narrow.state.outlineVisible = true;
  narrow.actions.toggleOutline(); await Promise.resolve();
  assert.equal(narrow.state.outlineVisible, false); assert.equal(narrow.state.fileSheetVisible, true);
  assert.equal(narrow.state.fileSheetSection, 'outline'); assert.equal(narrow.syncs(), 0);
  assert.equal(narrow.state.outlineEntries[0].text, 'Heading');
  narrow.actions.toggleOutline(); assert.equal(narrow.state.fileSheetVisible, false);
  narrow.state.fileSheetSection = 'export'; narrow.state.fileSheetVisible = true;
  narrow.actions.toggleOutline(); await Promise.resolve(); assert.equal(narrow.state.fileSheetSection, 'outline');

  const cramped = fixture(); Object.assign(cramped.state, { bp: 'tablet', contentWidthVp: 676, sidebarVisible: true });
  cramped.actions.toggleOutline(); assert.equal(cramped.state.outlineVisible, false); assert.equal(toasts.length, 1);
  Object.assign(cramped.state, { outlineVisible: true, viewMode: 'split' });
  cramped.actions.enforceWorkspaceBudget(); assert.equal(cramped.state.outlineVisible, false); assert.equal(cramped.state.viewMode, 'edit');
  Object.assign(cramped.state, { sidebarVisible: false, viewMode: 'split', contentWidthVp: 1000 });
  cramped.actions.toggleOutline(); assert.equal(cramped.state.outlineVisible, true); assert.equal(cramped.state.viewMode, 'split');
  cramped.state.contentWidthVp = 800; cramped.actions.enforceWorkspaceBudget(); assert.equal(cramped.state.viewMode, 'edit');

  wide.actions.sendBridge('first'); narrow.actions.sendBridge('second');
  assert.deepEqual(wide.actions.env.bridgeMessages, ['first']); assert.deepEqual(narrow.actions.env.bridgeMessages, ['second']);
  wide.actions.env.pendingOpenUri = 'file://received.md'; assert.equal(storage.get('pendingOpenUri'), 'file://received.md');
  const home = new HomeState({ filesDir: '/test' }); const homeActions = new HomeController(home, {}, { filesDir: '/test' });
  homeActions.consumeExternalOpen(); await Promise.resolve();
  assert.equal(storage.get('pendingOpenUri'), ''); assert.equal(routes[0].params.uri, 'file://received.md');
  let deferred = 0;
  wide.actions.dismissFileSheet(() => deferred++); wide.actions.fileSheetClosed(); wide.actions.fileSheetClosed();
  assert.equal(deferred, 1);
  wide.actions.dismissFileSheet(() => deferred++); wide.actions.env.disposed = true; wide.actions.fileSheetClosed();
  assert.equal(deferred, 1);
  wide.actions.aboutToDisappear(); wide.actions.sendBridge('late');
  assert.deepEqual(wide.actions.env.bridgeMessages, []);
  assert.deepEqual(narrow.actions.env.bridgeMessages, ['second']);
  const late = fixture(); late.state.bp = 'phone';
  let resolveSnapshot;
  late.actions.runJsValue = () => new Promise(resolve => { resolveSnapshot = resolve; });
  const pending = late.actions.openPhoneOutline();
  late.actions.aboutToDisappear(); // The old environment stays disposed when a new mount reuses the model.
  resolveSnapshot('# stale'); await pending;
  assert.equal(late.state.fileSheetVisible, false);
  late.actions.sendBridge('stale'); assert.deepEqual(late.actions.env.bridgeMessages, []);
  const liveFind = fixture(); delete liveFind.actions.syncDocNow;
  Object.assign(liveFind.state, { findVisible: true, findQuery: 'MatePad' });
  Object.assign(liveFind.actions.env, { webReady: true, activeSession: 'find' });
  const snap = (content, version = 1) => ({ ok: true, sessionId: 'find', version, content });
  liveFind.actions.getSnapshotData = async () => snap('MatePad MatePad MatePad MatePad');
  liveFind.actions.scheduleDocSync();
  await new Promise(resolve => setTimeout(resolve, 350));
  assert.equal(liveFind.state.matchCount, 4); assert.equal(liveFind.state.matchIndex, 0);
  const findScripts = [];
  liveFind.actions.runJsValue = async script => { findScripts.push(script); return ''; };
  liveFind.actions.locateFirstMatch(); liveFind.actions.jumpNext(); liveFind.actions.jumpPrev();
  assert.equal(findScripts.length, 3);
  assert.ok(findScripts.every(script => /setSelectionRange\(\d+, \d+, false\)/.test(script)));
  liveFind.actions.updateFindMatches('removed'); assert.equal(liveFind.state.matchCount, 0);
  assert.equal(liveFind.state.matchIndex, -1);

  let resolveFind;
  liveFind.actions.getSnapshotData = () => new Promise(resolve => { resolveFind = resolve; });
  const oldFind = liveFind.actions.refreshFind();
  liveFind.state.findQuery = 'new'; liveFind.actions.updateFindMatches('new new');
  resolveFind(snap('MatePad')); await oldFind;
  assert.equal(liveFind.state.matchCount, 2);

  const oldSync = liveFind.actions.syncDocNow();
  liveFind.actions.env.disposed = true;
  resolveFind(snap('new new new')); await Promise.resolve();
  assert.equal(liveFind.state.matchCount, 2);
  assert.equal(oldSync, undefined);
  const revision = fixture();
  revision.actions.env.activeSession = 'find'; revision.state.findQuery = 'new';
  revision.actions.env.coordinator = { documentVersion: 2 };
  revision.actions.getSnapshotData = async () => snap('new new', 1);
  await revision.actions.refreshFind(); assert.equal(revision.state.matchCount, 0);
  revision.actions.getSnapshotData = async () => snap('new new', 2);
  await revision.actions.refreshFind(); assert.equal(revision.state.matchCount, 2);
  revision.state.matchIndex = -1; revision.actions.openFind();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(revision.state.matchIndex, 0);

  const loads = fixture(); let firstRead, secondRead;
  loads.actions.env.internal.read = () => new Promise(resolve => { if (!firstRead) firstRead = resolve; else secondRead = resolve; });
  const target = { kind: 'internal', relativePath: 'library/test.md' };
  loads.actions.trackRecent = async () => {}; loads.actions.refreshSidebarData = () => {};
  loads.actions.loadOpenedDoc(target); loads.actions.loadOpenedDoc(target);
  const readResult = content => ({ content, revision: { size: content.length, contentHash: content },
    encoding: 'utf-8', lineEnding: 'lf', validUtf8: true });
  secondRead(readResult('latest')); await Promise.resolve();
  firstRead(readResult('obsolete')); await Promise.resolve();
  assert.equal(loads.actions.env.pendingLoad, 'latest');
  const searchState = new HomeState();
  const search = new HomeController(searchState, {}, { filesDir: '/test' });
  searchState.searchQuery = 'old'; let finishRead;
  search.env.fileSource.listLibrary = () => ['test.md'];
  search.env.fileSource.read = () => new Promise(resolve => { finishRead = resolve; });
  const oldSearch = search.runSearch(); searchState.searchQuery = '';
  await search.runSearch(); assert.equal(searchState.searchBusy, false);
  finishRead({ content: 'old' }); await oldSearch;
  assert.deepEqual(searchState.searchResults, []); assert.equal(searchState.searchBusy, false);
  const settings = fixture(); settings.actions.env.webReady = true;
  settings.actions.env.settings.load = async () => ({ theme: 'dark', fontSize: 16, wrap: true,
    lineNumbers: true, autoSave: true, defaultView: 'preview' });
  settings.actions.applyAppSettings(); await Promise.resolve();
  assert.equal(settings.state.viewMode, 'preview'); // Initial defaults survive a late settings read.
  settings.state.viewMode = 'edit'; settings.actions.applyAppSettings(true); await Promise.resolve();
  assert.equal(settings.state.viewMode, 'edit'); assert.equal(settings.actions.env.appSettings.fontSize, 16);
  settings.actions.env.settings.load = async () => ({ fontSize: 20 });
  settings.actions.env.disposed = true; settings.actions.applyAppSettings(true); await Promise.resolve();
  assert.equal(settings.actions.env.appSettings.fontSize, 16);
  const web = fixture(); delete web.actions.runJsValue;
  web.actions.env.controller.runJavaScript = (_, callback) => callback(undefined, JSON.stringify('body\ntext'));
  assert.equal(await web.actions.runJsValue('read'), 'body\ntext');
  assert.equal(await web.actions.runJsChecked(web.actions.env.controller, 'read'), 'body\ntext');
  web.actions.env.controller.runJavaScript = (_, callback) => callback(Error('native failure'));
  assert.equal(await web.actions.runJsValue('read'), '');
  await assert.rejects(web.actions.runJsChecked(web.actions.env.controller, 'read'));
  web.actions.env.controller.runJavaScript = () => { throw Error('unmounted'); };
  assert.equal(await web.actions.runJsValue('read'), '');
  await assert.rejects(web.actions.runJsChecked(web.actions.env.controller, 'read'));
  const recent = [{ documentId: 'library/remove.md', lastOpenedAt: 2, pinned: true },
    { documentId: 'library/keep.md', lastOpenedAt: 1, pinned: false }];
  let records = structuredClone(recent), deleted = [], refreshes = 0;
  const removedDrafts = [];
  homeActions.env.draftStore.remove = id => removedDrafts.push(id);
  homeActions.refreshRecovery = async () => {};
  homeActions.env.meta.loadRecent = async () => records;
  homeActions.env.meta.saveRecent = async list => { records = list; };
  homeActions.env.fileSource.deleteLibrary = name => { deleted.push(name); return true; };
  homeActions.refresh = async () => { refreshes++; };
  homeActions.refreshLibrary = async () => {};
  dialogs.length = 0;
  homeActions.deleteRecent('library/remove.md');
  assert.equal(dialogs.length, 1); assert.deepEqual(deleted, []);
  assert.match(dialogs[0].message, /无法恢复/);
  dialogs[0].secondaryButton.action(); assert.deepEqual(deleted, []);
  dialogs[0].primaryButton.action(); await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(deleted, ['remove.md']); assert.equal(records.length, 1);
  assert.deepEqual(removedDrafts, ['internal:library/remove.md']);
  assert.equal(records[0].documentId, 'library/keep.md'); assert.equal(refreshes, 1);
  homeActions.deleteRecent('file://docs/external.md'); assert.equal(dialogs.length, 1);
  assert.match(toasts.at(-1).message, /文件管理器/);
  homeActions.deleteRecent('library/../outside.md'); assert.equal(dialogs.length, 1);
  records = structuredClone(recent);
  homeActions.env.fileSource.deleteLibrary = () => false;
  await homeActions.doDelete('remove.md'); assert.equal(records.length, 2);
  assert.equal(removedDrafts.length, 1); // Failed file deletion keeps recovery data.
  const deletion = fixture(); let sidebarRefreshes = 0;
  deletion.actions.refreshSidebarData = () => sidebarRefreshes++;
  deletion.actions.env.meta.loadRecent = async () => records;
  deletion.actions.env.meta.saveRecent = async list => { records = list; };
  deletion.actions.env.internal.deleteLibrary = name => { deleted.push(name); return true; };
  deletion.actions.env.drafts.remove = id => removedDrafts.push(id);
  deletion.state.docTarget = { kind: 'internal', relativePath: 'library/remove.md' };
  dialogs.length = 0;
  deletion.actions.deleteDocument('library/../outside.md'); assert.equal(dialogs.length, 0);
  deletion.actions.deleteDocument('library/remove.md'); assert.equal(dialogs.length, 1);
  dialogs[0].secondaryButton.action(); assert.deepEqual(deleted, ['remove.md']);
  deletion.actions.deleteDocument('library/keep.md'); assert.equal(dialogs.length, 2);
  dialogs.at(-1).primaryButton.action();
  assert.equal(deletion.state.deliveryBusy, true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(deletion.state.deliveryBusy, false); assert.equal(sidebarRefreshes, 1);
  assert.equal(removedDrafts.at(-1), 'internal:library/keep.md');
  assert.deepEqual(records.map(r => r.documentId), ['library/remove.md']);
  await deletion.actions.toggleRecentPin('library/remove.md'); assert.equal(records[0].pinned, false);
  deletion.actions.env.internal.deleteLibrary = () => false;
  deletion.actions.deleteDocument('library/remove.md'); dialogs.at(-1).primaryButton.action();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(records.length, 1); assert.equal(deletion.state.deliveryBusy, false);
  assert.equal(deletion.actions.isActive(), true, 'failed current deletion keeps editor usable');
  let releaseCheckpoint;
  deletion.actions.env.coordinator = { state: 'dirty', checkpointNow: () => new Promise(resolve => { releaseCheckpoint = resolve; }) };
  deletion.actions.env.internal.deleteLibrary = () => true;
  deletion.actions.env.meta.saveRecent = async () => { throw Error('disk full'); };
  deletion.actions.deleteCurrentDocument(); dialogs.at(-1).primaryButton.action();
  assert.equal(deletion.actions.isActive(), true);
  assert.equal(deletion.state.deliveryBusy, true, 'wait for pending checkpoint before removing file');
  releaseCheckpoint(true); await new Promise(resolve => setImmediate(resolve));
  assert.equal(deletion.actions.isActive(), false);
  assert.match(toasts.at(-1).message, /记录清理失败/); assert.equal(deletion.state.deliveryBusy, false);
  assert.equal(routes.at(-1).url, 'pages/HomePage', 'deleted current editor must exit even if metadata fails');
  assert.ok(removedDrafts.includes(deletion.actions.env.sessionDraftId));
  await assert.rejects(() => deletion.actions.doSaveCheckpoint('late'), /session ended/);
  assert.equal((await deletion.actions.doPersist('late')).ok, false, 'late save must not recreate deleted file');
  dialogs.length = 0;
  deletion.actions.deleteDocument('library/remove.md'); assert.equal(dialogs.length, 0);
  const savingDeletion = fixture();
  savingDeletion.state.docTarget = { kind: 'internal', relativePath: 'library/busy.md' };
  savingDeletion.actions.env.coordinator = { state: 'saving' };
  savingDeletion.actions.deleteCurrentDocument(); dialogs.at(-1).primaryButton.action();
  assert.match(toasts.at(-1).message, /正在保存/);
  assert.equal(savingDeletion.actions.isActive(), true);
  const switchedDeletion = fixture(); let switchRecords = [{ documentId: 'library/gone.md', pinned: false }];
  switchedDeletion.actions.env.internal.deleteLibrary = () => true;
  switchedDeletion.actions.env.meta.loadRecent = async () => switchRecords;
  switchedDeletion.actions.env.meta.saveRecent = async list => { switchRecords = list; };
  switchedDeletion.actions.env.drafts.remove = () => {};
  switchedDeletion.actions.deleteDocument('library/gone.md');
  switchedDeletion.state.docTarget = { kind: 'internal', relativePath: 'library/gone.md' };
  dialogs.at(-1).primaryButton.action(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(switchedDeletion.actions.isActive(), false, 'resolve current target again on confirmation');
  assert.deepEqual(switchRecords, []);
  records = [{ documentId: 'library/missing.md', lastOpenedAt: 3, pinned: false },
    { documentId: 'library/keep.md', lastOpenedAt: 1, pinned: true },
    { documentId: 'file://docs/external.md', lastOpenedAt: 2, pinned: false }];
  homeActions.env.fileSource.listLibrary = () => ['keep.md'];
  await HomeController.prototype.refresh.call(homeActions);
  assert.deepEqual(home.recent.map(r => r.documentId), ['library/keep.md', 'file://docs/external.md']);
  const sidebar = fixture();
  sidebar.actions.env.meta.loadRecent = async () => records;
  sidebar.actions.env.internal.listLibrary = () => ['keep.md'];
  sidebar.actions.refreshSidebarData(); await Promise.resolve();
  assert.deepEqual(sidebar.state.sidebarRecent.map(r => r.documentId), ['library/keep.md', 'file://docs/external.md']);
  const fresh = fixture(); let freshRecent = [];
  fresh.actions.env.internal.listLibrary = () => ['fresh.md'];
  fresh.actions.env.meta.loadRecent = async () => freshRecent;
  fresh.actions.env.meta.saveRecent = async list => { freshRecent = list; };
  await fresh.actions.trackRecent({ kind: 'internal', relativePath: 'library/fresh.md' });
  await Promise.resolve();
  assert.deepEqual(fresh.state.sidebarRecent.map(r => r.documentId), ['library/fresh.md']);
  console.log('Editor/home controller scenarios passed, including current deletion and late-save rejection (real modules, platform boundaries mocked)');
})().catch(error => { console.error(error); process.exitCode = 1; });
