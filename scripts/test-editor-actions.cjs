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
    router: { getState: () => ({ name: 'HomePage' }), pushUrl: async r => routes.push(r) } },
};
const load = createLoader(kits, {
  Observed: cls => cls, AlertDialog: { show: d => dialogs.push(d) },
  AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) },
});
const root = path.join(__dirname, '../entry/src/main/ets');
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

  wide.actions.showHelp(); assert.equal(dialogs.length, 1);
  assert.ok(dialogs[0].message.includes('\n')); assert.ok(!dialogs[0].message.includes('\\n'));
  assert.ok(dialogs[0].message.includes('Ctrl+Shift+F'));

  wide.actions.sendBridge('first'); narrow.actions.sendBridge('second');
  assert.deepEqual(wide.actions.channel.pending, ['first']); assert.deepEqual(narrow.actions.channel.pending, ['second']);
  wide.state.pendingOpenUri = 'file://received.md'; assert.equal(storage.get('pendingOpenUri'), 'file://received.md');
  const home = new HomeState({ filesDir: '/test' }); const homeActions = new HomeController(home, {}, { filesDir: '/test' });
  homeActions.consumeExternalOpen(); await Promise.resolve();
  assert.equal(storage.get('pendingOpenUri'), ''); assert.equal(routes[0].params.uri, 'file://received.md');
  let deferred = 0;
  wide.actions.dismissFileSheet(() => deferred++); wide.actions.fileSheetClosed(); wide.actions.fileSheetClosed();
  assert.equal(deferred, 1);
  wide.actions.dismissFileSheet(() => deferred++); wide.state.pageActive = false; wide.actions.fileSheetClosed();
  assert.equal(deferred, 1);
  wide.actions.aboutToDisappear(); wide.actions.sendBridge('late');
  assert.deepEqual(wide.actions.channel.pending, []);
  assert.deepEqual(narrow.actions.channel.pending, ['second']);
  const late = fixture(); late.state.bp = 'phone';
  let resolveSnapshot;
  late.actions.runJsValue = () => new Promise(resolve => { resolveSnapshot = resolve; });
  const pending = late.actions.openPhoneOutline();
  late.actions.aboutToDisappear(); late.state.pageActive = true; // A new mount reuses the model.
  resolveSnapshot('# stale'); await pending;
  assert.equal(late.state.fileSheetVisible, false);
  late.actions.sendBridge('stale'); assert.deepEqual(late.actions.channel.pending, []);
  console.log('13 editor/home controller scenarios passed (real modules, platform boundaries mocked)');
})().catch(error => { console.error(error); process.exitCode = 1; });
