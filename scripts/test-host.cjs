/* Real domain/test sources, transpiled without changing their logic. Platform mocks test IO failures;
 * this runner supplements, rather than replaces, ArkTS compilation and device verification. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const os = require('node:os');
const { transformSync, buildSync } = require('../web-tools/node_modules/esbuild');
const cases = [];
const cache = new Map();
const root = path.resolve(__dirname, '..');
let selection = [];
let writeLimit = Infinity;
let readLimit = Infinity;
let failSync = false;
let chooseCount = 0;
const io = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY,
    CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
  openSync: (p, flags) => ({ fd: fs.openSync(p, flags & fs.constants.O_TRUNC ? 'w' : flags) }),
  closeSync: fs.closeSync,
  statSync: p => { const s = typeof p === 'number' ? fs.fstatSync(p) : fs.statSync(p); return {
    size: s.size, mtime: s.mtimeMs, isFile: () => s.isFile(), isDirectory: () => s.isDirectory(),
  }; },
  accessSync: p => fs.existsSync(p),
  readSync: (fd, data) => fs.readSync(fd, new Uint8Array(data), 0, Math.min(data.byteLength, readLimit)),
  writeSync: (fd, data) => fs.writeSync(fd, new Uint8Array(data), 0, Math.min(data.byteLength, writeLimit)),
  fsyncSync: fd => { if (failSync) throw new Error('injected fsync failure'); fs.fsyncSync(fd); },
  renameSync: fs.renameSync, unlinkSync: fs.unlinkSync, mkdirSync: fs.mkdirSync,
  rmdirSync: fs.rmdirSync, listFileSync: fs.readdirSync,
};
const hypium = {
  describe: (_, body) => body(), it: (name, _, body) => cases.push({ name, body }),
  expect: value => ({
    assertEqual: wanted => assert.deepEqual(value, wanted), assertTrue: () => assert.equal(value, true),
    assertFalse: () => assert.equal(value, false), assertUndefined: () => assert.equal(value, undefined),
  }),
};
const toasts = [];
const kits = {
  '@kit.AbilityKit': {},
  '@kit.ArkData': { unifiedDataChannel: { ProgressIndicator: { NONE: 0 }, ListenerStatus: { FINISHED: 0, PROCESSING: 1 } } },
  '@kit.CoreFileKit': { fileIo: io, fileUri: { getUriFromPath: p => `file://${p}` }, picker: {
    DocumentViewPicker: class { async save() { chooseCount++; return selection; } },
    PhotoViewPicker: class { async select() { return { photoUris: ['file:///tmp/picked.png'] }; } },
    PhotoViewMIMETypes: { IMAGE_TYPE: 'image/*' }, DocumentSelectMode: { FOLDER: 0 },
  } },
  '@kit.ArkTS': { util: {
    TextEncoder: { create: () => ({ encodeInto: s => new TextEncoder().encode(s) }) },
    TextDecoder: { create: () => ({ decodeToString: b => new TextDecoder().decode(b) }) },
    Base64Helper: class { encodeToStringSync(b) { return Buffer.from(b).toString('base64'); } },
  } },
  '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {}, error() {} } },
  '@kit.BasicServicesKit': {
    zlib: { compressFile: async () => { throw new Error('device-only compression'); } },
    pasteboard: { createData: () => ({}), getSystemPasteboard: () => ({ setData() {}, getData: async () => ({}) }) },
  },
  '@kit.ArkUI': {
    router: { pushUrl: async () => {}, back() {}, replaceUrl: async () => {}, getState: () => ({ name: '' }) },
    promptAction: { showToast: args => toasts.push(args.message), showActionMenu: async () => ({ index: 0 }) },
    mediaquery: { matchMediaSync: () => ({ on() {}, off() {} }) },
    UIContext: class {},
  },
  '@kit.ArkWeb': { webview: { WebviewController: class {} } },
};
function load(file) {
  file = path.resolve(file);
  if (!file.endsWith('.ets')) file += '.ets';
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} }; cache.set(file, module);
  const code = transformSync(fs.readFileSync(file, 'utf8'), { loader: 'ts', format: 'cjs', target: 'es2022' }).code;
  const req = name => name === '@ohos/hypium' ? hypium : kits[name] ||
    (name.startsWith('.') ? load(path.resolve(path.dirname(file), name)) : require(name));
  vm.runInThisContext(`(function(require,module,exports){${code}\n})`, { filename: file })(req, module, module.exports);
  return module.exports;
}
load(path.join(root, 'entry/src/test/List.test.ets')).default();
cases.push({ name: 'MuLogger preserves levels, private formatting and literal message contents', body() {
  const kit = kits['@kit.PerformanceAnalysisKit'], original = kit.hilog, calls = [];
  kit.hilog = Object.fromEntries(['debug', 'info', 'warn', 'error'].map(level =>
    [level, (...args) => calls.push([level, ...args])]));
  try {
    const { MuLogger } = load(path.join(root, 'entry/src/main/ets/common/MuLogger.ets'));
    for (const level of ['debug', 'info', 'warn', 'error']) MuLogger[level]('literal %{public}s %d\nmessage');
    assert.deepEqual(calls, ['debug', 'info', 'warn', 'error'].map(level =>
      [level, 0, 'MuMark', '%{private}s', 'literal %{public}s %d\nmessage']));
  } finally { kit.hilog = original; }
} });
const { SafeFileIO } = load(path.join(root, 'entry/src/main/ets/infrastructure/file/SafeFileIO.ets'));
const { DocumentDeliveryService } = load(path.join(root, 'entry/src/main/ets/services/DocumentDeliveryService.ets'));
const { SaveCoordinator } = load(path.join(root, 'entry/src/main/ets/services/SaveCoordinator.ets'));
const { DocumentIntake } = load(path.join(root, 'entry/src/main/ets/domain/document/DocumentIntake.ets'));
const { DroppedDocumentReader } = load(path.join(root, 'entry/src/main/ets/services/DroppedDocumentReader.ets'));
const { DocumentImportService } = load(path.join(root, 'entry/src/main/ets/services/DocumentImportService.ets'));
const { MetadataStore } = load(path.join(root, 'entry/src/main/ets/infrastructure/metadata/MetadataStore.ets'));
cases.push({ name: 'sidebar preference reuses legacy key and keeps recent metadata intact', async body() {
  const original = kits['@kit.ArkData'].preferences;
  const values = new Map([['recent', '[{"id":"library/keep.md","at":123,"pinned":true}]']]);
  kits['@kit.ArkData'].preferences = { async getPreferences(_, name) {
    assert.equal(name, 'hmwb_metadata');
    return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => values.set(key, value), flush: async () => {} };
  } };
  try {
    const store = new MetadataStore({});
    assert.equal(await store.loadSidebarPreferredOpen(), true);
    values.set('sidebarPreferredOpen', false); assert.equal(await store.loadSidebarPreferredOpen(), false);
    await store.saveSidebarPreferredOpen(true); assert.equal(values.get('sidebarPreferredOpen'), true);
    assert.deepEqual(await store.loadRecent(), [{ documentId: 'library/keep.md', lastOpenedAt: 123, pinned: true }]);
  } finally { kits['@kit.ArkData'].preferences = original; }
} });
cases.push({ name: 'sidebar preference failure preserves default and does not block interaction', async body() {
  const original = kits['@kit.ArkData'].preferences;
  kits['@kit.ArkData'].preferences = { async getPreferences() { throw Error('unavailable'); } };
  try {
    const store = new MetadataStore({});
    assert.equal(await store.loadSidebarPreferredOpen(), true);
    await store.saveSidebarPreferredOpen(false);
  } finally { kits['@kit.ArkData'].preferences = original; }
} });
let viewportWidth = 0;
const mediaListeners = [];
kits['@kit.ArkUI'].mediaquery = { matchMediaSync(query) {
  const min = /min-width:\s*(\d+)vp/.exec(query);
  const max = /max-width:\s*(\d+)vp/.exec(query);
  const listener = { get matches() { return (!min || viewportWidth >= +min[1]) && (!max || viewportWidth <= +max[1]); },
    on(_, fn) { this.callback = fn; mediaListeners.push(this); }, off() { this.callback = undefined; } };
  return listener;
} };
const { bpOf, watchBreakpoints, unwatchBreakpoints } = load(path.join(root, 'entry/src/main/ets/common/Breakpoints.ets'));
cases.push({ name: 'breakpoints cover fractional widths and resize in both directions', body() {
  const observed = [];
  const listeners = watchBreakpoints(bp => observed.push(bp));
  for (const [width, expected] of [[320,'phone'],[599,'phone'],[599.9,'phone'],[600,'tablet'],
    [959,'tablet'],[959.9,'tablet'],[960,'pc'],[1440,'pc'],[959.5,'tablet'],[599.5,'phone']]) {
    viewportWidth = width;
    assert.equal(bpOf(), expected, `width=${width}`);
    for (const listener of mediaListeners) listener.callback?.();
    assert.equal(observed.at(-1), expected);
  }
  unwatchBreakpoints(listeners);
  assert.ok(listeners.every(l => !l.callback));
} });
kits['@kit.BasicServicesKit'].deviceInfo = {};
const { WebDragStyle } = load(path.join(root, 'entry/src/main/ets/common/WebDragStyle.ets'));
cases.push({ name: 'Web drag compatibility skips absent/unsupported API and applies only on API26', body() {
  const modifier = new WebDragStyle();
  modifier.applyNormalAttribute({}); // A legacy system has neither new API.
  kits['@kit.BasicServicesKit'].deviceInfo.apiAvailable = () => false;
  modifier.applyNormalAttribute({});
  kits['@kit.BasicServicesKit'].deviceInfo.apiAvailable = version => { assert.equal(version, '26.0.0'); return true; };
  let value;
  modifier.applyNormalAttribute({ enableDrag(v) { value = v; } });
  assert.equal(value, false);
} });
const { DraftStore } = load(path.join(root, 'entry/src/main/ets/infrastructure/metadata/DraftStore.ets'));
cases.push({ name: 'draft load and recovery listing survive UTF8 short reads', body() {
  const store = new DraftStore({ filesDir });
  const content = '木笺😀\r\n恢复正文'.repeat(150);
  store.save('compat-draft', 'fingerprint', 10, 'base', content);
  readLimit = 7;
  try {
    assert.equal(store.load('compat-draft').content, content);
    assert.equal(store.listAll().find(d => d.documentId === 'compat-draft').content, content);
  } finally { readLimit = Infinity; store.remove('compat-draft'); }
} });
cases.push({ name: 'draft checkpoint app version matches the app manifest', body() {
  const versionName = JSON.parse(fs.readFileSync(path.join(root, 'AppScope/app.json5'), 'utf8')).app.versionName;
  const store = new DraftStore({ filesDir });
  store.save('version-draft', 'fingerprint', 0, '', 'x');
  try { assert.equal(store.load('version-draft').appVersion, versionName); }
  finally { store.remove('version-draft'); }
} });
cases.push({ name: 'intake validates one local text document and preserves authorization URI', body() {
  const uri = 'file://docs/a%20b.MD?grant=1';
  assert.equal(DocumentIntake.select([uri, uri]), uri);
  for (const input of [[], ['file://a.md','file://b.md'], ['file://a.pdf'], ['https://a.md'], ['file:///%ZZ.md']]) {
    assert.throws(() => DocumentIntake.select(input));
  }
} });
cases.push({ name: 'drop asynchronously receives URI without synchronous getData', async body() {
  let callback;
  const promise = DroppedDocumentReader.receive({ startDataLoading(options) { callback = options.dataProgressListener; } });
  callback({ status: 1, progress: 50 }, null);
  callback({ status: 0, progress: 100 }, { getRecords() { return [{
    getTypes() { return ['general.file-uri']; }, getEntry() { return { oriUri: 'file://docs/a.md' }; },
  }]; } });
  assert.equal(await promise, 'file://docs/a.md');
} });
cases.push({ name: 'drop timeout releases wait and ignores late callbacks', async body() {
  let callback, cancelled;
  const promise = DroppedDocumentReader.receive({ startDataLoading(options) {
    callback = options.dataProgressListener; return 'task-1';
  } }, 5, '', key => { cancelled = key; });
  await assert.rejects(promise, /超时/);
  assert.equal(cancelled, 'task-1');
  callback({ status: 0, progress: 100 }, { getRecords() { throw new Error('stale callback must not parse'); } });
  await assert.rejects(DroppedDocumentReader.receive({ startDataLoading() { throw new Error('system failure'); } }), /system failure/);
} });
cases.push({ name: 'failed system transfer rejects once and the next drop can succeed', async body() {
  await assert.rejects(DroppedDocumentReader.receive({ startDataLoading(options) {
    options.dataProgressListener({ status: 200, progress: -1 }, null);
    options.dataProgressListener({ status: 0, progress: 100 }, { getRecords() { throw new Error('late result'); } });
    return 'failed-task';
  } }), /授权/);
  const good = await DroppedDocumentReader.receive({ startDataLoading(options) {
    options.dataProgressListener({ status: 0, progress: 100 }, { getRecords() { return [{
      getTypes() { return []; }, uri: 'file://docs/next.txt',
    }]; } }); return 'good-task';
  } });
  assert.equal(good, 'file://docs/next.txt');
} });
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mumark-tests-'));
const filesDir = path.join(dir, 'files'); fs.mkdirSync(filesDir); fs.mkdirSync(path.join(filesDir, 'attachments'));
cases.push({ name: 'import persists document, reuses identical copy and never overwrites different content', async body() {
  const source = path.join(dir, 'imported.md').replaceAll('\\', '/'); fs.writeFileSync(source, '# 第一份\r\n木笺🙂');
  const service = new DocumentImportService({ filesDir, cacheDir: dir });
  const first = await service.importUri(source);
  assert.equal(first, 'library/imported.md');
  assert.equal(await service.importUri(source), first);
  fs.writeFileSync(source, '# 第二份');
  assert.equal(await service.importUri(source), 'library/imported(2).md');
  assert.equal(fs.readFileSync(path.join(filesDir, first), 'utf8'), '# 第一份\r\n木笺🙂');
  assert.equal(fs.readFileSync(source, 'utf8'), '# 第二份');
} });
cases.push({ name: 'partial writes are completed, including multibyte text', body() {
  writeLimit = 2;
  const file = path.join(dir, 'partial.txt'); SafeFileIO.writeText(file, '木笺🙂');
  assert.equal(fs.readFileSync(file, 'utf8'), '木笺🙂'); writeLimit = Infinity;
} });
cases.push({ name: 'partial reads assemble complete Unicode bytes', body() {
  const file = path.join(dir, 'read.txt'); fs.writeFileSync(file, '木笺🙂'); readLimit = 2;
  try { assert.equal(new TextDecoder().decode(SafeFileIO.readBytes(file)), '木笺🙂'); }
  finally { readLimit = Infinity; }
} });
cases.push({ name: 'coalesced checkpoint catches edits arriving during previous write', async body() {
  let release, started;
  const began = new Promise(resolve => { started = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  let content = 'first', version = 1, writes = [];
  const coordinator = new SaveCoordinator({
    async getSnapshot() { return { ok: true, sessionId: 'session', version, content }; },
    async saveCheckpoint(text) { writes.push(text); if (writes.length === 1) { started(); await gate; } },
    async persist() { throw new Error('checkpoint must not write source'); },
  });
  const first = coordinator.checkpointNow(); await began;
  content = 'second'; version = 2; const second = coordinator.checkpointNow();
  release(); assert.equal(await first, true); assert.equal(await second, true);
  assert.deepEqual(writes, ['first', 'second']);
} });
cases.push({ name: 'delivery result uses filename edited in the system picker', async body() {
  const file = path.join(dir, 'chosen-name.md'); fs.writeFileSync(file, ''); selection = [file.replaceAll('\\', '/')];
  const service = new DocumentDeliveryService({ filesDir, cacheDir: dir });
  const result = await service.markdown('suggested-name', 'content');
  assert.equal(result.fileName, 'chosen-name.md'); assert.equal(fs.readFileSync(file, 'utf8'), 'content');
} });
cases.push({ name: 'delivery reports actual extensionless and custom-extension filenames', async body() {
  const service = new DocumentDeliveryService({ filesDir, cacheDir: dir });
  for (const name of ['notes-no-extension', 'notes.custom']) {
    const file = path.join(dir, name); fs.writeFileSync(file, ''); selection = [file.replaceAll('\\', '/')];
    const result = await service.markdown('old-title.md', 'fresh');
    assert.equal(result.fileName, name); assert.equal(fs.readFileSync(file, 'utf8'), 'fresh');
  }
} });
cases.push({ name: 'atomic checkpoint preserves original on fsync failure', body() {
  const file = path.join(dir, 'draft.json'); fs.writeFileSync(file, 'old'); failSync = true;
  try { assert.throws(() => SafeFileIO.atomicText(file, 'new')); }
  finally { failSync = false; }
  assert.equal(fs.readFileSync(file, 'utf8'), 'old'); assert.equal(fs.existsSync(`${file}.tmp`), false);
} });
cases.push({ name: 'cancelled Markdown delivery never writes output', async body() {
  selection = []; const service = new DocumentDeliveryService({ filesDir, cacheDir: dir });
  assert.equal(await service.markdown('title', '正文'), undefined);
} });
cases.push({ name: 'HTML delivery embeds local images and uses supplied fresh render', async body() {
  fs.writeFileSync(path.join(filesDir, 'attachments', 'image.png'), Buffer.from([1, 2, 3]));
  const file = path.join(dir, 'output.html'); fs.writeFileSync(file, ''); selection = [file];
  const service = new DocumentDeliveryService({ filesDir, cacheDir: dir });
  await service.html('title', '最新正文', ['attachments/image.png'], async (text, resources) =>
    `<p>${text}</p><img src="${resources['attachments/image.png']}">`);
  const html = fs.readFileSync(file, 'utf8'); assert.match(html, /最新正文/); assert.match(html, /data:image\/png;base64,AQID/);
} });
cases.push({ name: 'missing attachment blocks delivery before picker or partial output', async body() {
  const before = chooseCount; const service = new DocumentDeliveryService({ filesDir, cacheDir: dir });
  await assert.rejects(service.html('title', 'x', ['attachments/missing.png'], async () => 'old'));
  assert.equal(chooseCount, before);
} });
cases.push({ name: 'failed export restores preexisting user file instead of deleting it', body() {
  const file = path.join(dir, 'existing.md'); fs.writeFileSync(file, 'original');
  let wrote = false;
  assert.throws(() => SafeFileIO.replaceTarget(file, fd => { SafeFileIO.writeAll(fd, new TextEncoder().encode('partial')); wrote = true; throw new Error('full'); }));
  assert.equal(wrote, true);
  assert.equal(fs.readFileSync(file, 'utf8'), 'original');
} });
const markdownBundle = buildSync({ entryPoints: [path.join(root, 'web-tools/src/markdown.js')], bundle: true,
  format: 'cjs', platform: 'node', write: false }).outputFiles[0].text;
const markdownModule = { exports: {} };
vm.runInThisContext(`(function(module,exports){${markdownBundle}\n})`)(markdownModule, markdownModule.exports);
cases.push({ name: 'real Markdown parser finds reference images and ignores code fences', body() {
  const md = '![图][photo]\n\n[photo]: attachments/a%20b.png\n\n```md\n![ignore](private.png)\n```';
  assert.deepEqual(JSON.parse(markdownModule.exports.inspectMarkdown(md)).images, ['attachments/a%20b.png']);
} });
cases.push({ name: 'preview and export resolve angle-wrapped paths with spaces through parser resources', body() {
  const md = '![图片](<attachments/a b.png>)';
  const sources = JSON.parse(markdownModule.exports.inspectMarkdown(md)).images;
  assert.equal(sources.length, 1);
  const resources = { [sources[0]]: 'data:image/png;base64,AQID' };
  const html = markdownModule.exports.renderMarkdown(md, resources);
  assert.match(html, /src="data:image\/png;base64,AQID"/);
} });
cases.push({ name: 'strikethrough content remains escaped and scripts cannot render', body() {
  const html = markdownModule.exports.renderMarkdown('~~<img src=x onerror=alert(1)>~~');
  assert.ok(!html.includes('<img')); assert.match(html, /&lt;img/);
} });
cases.push({ name: 'markdown links reject javascript protocols', body() {
  const html = markdownModule.exports.renderMarkdown('[点我](javascript:alert(1))');
  assert.ok(!/href="javascript:/i.test(html));
} });
// ---- 编辑器写回安全：读取失败必须中止，写失败不得推进保存/命中状态 ----
const { EditorController } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorController.ets'));
const { EditorFind } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorFind.ets'));
const { EditorDelivery } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorDelivery.ets'));
function findHost(handler) {
  const state = {
    deliveryBusy: false, findQuery: 'foo', replaceText: 'bar', findCase: false, findWord: false,
    matchIndex: 0, findMatches: [{ from: 0, to: 3 }], docLength: 99, saveState: 'clean',
    get matchCount() { return this.findMatches.length; },
  };
  const env = { activeSession: 's1', controller: {}, coordinator: undefined };
  let edits = 0;
  return {
    state, env, isActive: () => true,
    findOpts: () => ({ caseSensitive: false, wholeWord: false }),
    runJsChecked: async (ctrl, script, allowEmpty) => {
      const value = handler(script);
      if (value === undefined && !allowEmpty) throw new Error('editor read failed');
      return value === undefined ? '' : value;
    },
    markEdited: () => { edits++; },
    selectCurrentMatch: () => {},
    editCount: () => edits,
  };
}
cases.push({ name: 'find replace aborts before writing when snapshot read fails', async body() {
  const host = findHost(script => { if (script.includes('getSnapshot')) throw new Error('read failed'); return ''; });
  await new EditorFind(host).replaceCurrent();
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'find replace failure keeps doc length and save state untouched', async body() {
  const host = findHost(script => {
    if (script.includes('getSnapshot')) return 'foo baz';
    throw new Error('write failed');
  });
  await new EditorFind(host).replaceCurrent();
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'find replace advances state only after write succeeds', async body() {
  const scripts = [];
  const host = findHost(script => { scripts.push(script); return script.includes('getSnapshot') ? 'foo baz' : undefined; });
  await new EditorFind(host).replaceCurrent();
  assert.ok(scripts.some(s => s.includes('setDocument')));
  assert.equal(host.state.docLength, 7); assert.equal(host.editCount(), 1);
} });
cases.push({ name: 'replace-all failure preserves matches and does not mark edited', async body() {
  const host = findHost(script => {
    if (script.includes('getSnapshot')) return 'foo foo';
    throw new Error('write failed');
  });
  host.state.findMatches = [{ from: 0, to: 3 }, { from: 4, to: 7 }];
  host.state.matchIndex = 1;
  await new EditorFind(host).replaceAllMatches();
  assert.equal(host.state.docLength, 99); assert.equal(host.state.findMatches.length, 2);
  assert.equal(host.state.matchIndex, 1); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'replace-all clears matches only after the write succeeds', async body() {
  const host = findHost(script => script.includes('getSnapshot') ? 'foo foo' : undefined);
  await new EditorFind(host).replaceAllMatches();
  assert.equal(host.state.docLength, 7); assert.equal(host.state.findMatches.length, 0);
  assert.equal(host.state.matchIndex, -1); assert.equal(host.editCount(), 1);
} });
function controllerHost(handler) {
  const host = Object.create(EditorController.prototype);
  host.state = { deliveryBusy: false, docLength: 99 };
  host.env = { activeSession: 's1', controller: { runJavaScript(script, cb) {
    try { cb(null, handler(script)); } catch (e) { cb(e, undefined); }
  } } };
  host.isActive = () => true;
  let edits = 0;
  host.markEdited = () => { edits++; };
  host.editCount = () => edits;
  return host;
}
cases.push({ name: 'toolbar command aborts when selection read fails', async body() {
  const host = controllerHost(script => { if (script.includes('getSelectionRange')) throw new Error('read failed'); return '{}'; });
  await host.applyCommand('bold');
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'toolbar command aborts when snapshot read fails', async body() {
  const scripts = [];
  const host = controllerHost(script => {
    scripts.push(script);
    if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
    throw new Error('read failed');
  });
  await host.applyCommand('bold');
  assert.ok(!scripts.some(s => s.includes('setDocument')));
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'toolbar command write failure does not mark document edited', async body() {
  const host = controllerHost(script => {
    if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
    if (script.includes('getSnapshot')) return 'foo';
    throw new Error('write failed');
  });
  await host.applyCommand('bold');
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'toolbar command aborts after session switch without writing', async body() {
  const scripts = [];
  const host = controllerHost(script => {
    scripts.push(script);
    if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
    host.env.activeSession = 's2';
    return 'foo';
  });
  await host.applyCommand('bold');
  assert.ok(!scripts.some(s => s.includes('setDocument')));
  assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
} });
cases.push({ name: 'toolbar command writes once and advances state on success', async body() {
  const scripts = [];
  const host = controllerHost(script => {
    scripts.push(script);
    if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
    if (script.includes('getSnapshot')) return 'foo';
    return '7';
  });
  await host.applyCommand('bold');
  assert.equal(scripts.filter(s => s.includes('setDocument')).length, 1);
  assert.ok(scripts.find(s => s.includes('setDocument')).includes('**foo**'));
  assert.equal(host.state.docLength, 7); assert.equal(host.editCount(), 1);
} });
function deliveryHost(handler) {
  const calls = { edits: 0, syncs: 0 };
  const host = {
    state: { saveState: 'clean', deliveryBusy: false },
    env: {
      activeSession: 's1', controller: {},
      coordinator: { state: 'dirty', onEdit: () => { calls.edits++; } },
      internal: { copyToAttachments: () => 'attachments/picked.png' },
    },
    isActive: () => true,
    scheduleDocSync: () => { calls.syncs++; },
    runJsChecked: async (ctrl, script, allowEmpty) => {
      const value = handler(script, host);
      if (value === undefined && !allowEmpty) throw new Error('editor read failed');
      return value === undefined ? '' : value;
    },
    calls,
  };
  return host;
}
cases.push({ name: 'attachment insert aborts when selection read fails', async body() {
  const host = deliveryHost(() => { throw new Error('read failed'); });
  await assert.rejects(new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'));
  assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
} });
cases.push({ name: 'attachment insert write failure leaves save state untouched', async body() {
  const host = deliveryHost(script => {
    if (script.includes('getSelectionRange')) return '{"from":2,"to":2}';
    throw new Error('write failed');
  });
  await assert.rejects(new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'));
  assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
} });
cases.push({ name: 'attachment insert succeeds only after the write resolves', async body() {
  const host = deliveryHost(script => script.includes('getSelectionRange') ? '{"from":2,"to":2}' : undefined);
  assert.equal(await new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'), true);
  assert.equal(host.calls.edits, 1); assert.equal(host.calls.syncs, 1); assert.equal(host.state.saveState, 'dirty');
} });
cases.push({ name: 'attachment insert stops silently when document switches during write', async body() {
  const host = deliveryHost(script => {
    if (script.includes('getSelectionRange')) return '{"from":2,"to":2}';
    host.env.activeSession = 's2';
    return undefined;
  });
  assert.equal(await new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'), false);
  assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
} });
cases.push({ name: 'image picker reports failure instead of success when insert write fails', async body() {
  toasts.length = 0;
  const host = deliveryHost(script => {
    if (script.includes('getSelectionRange')) return '{"from":0,"to":0}';
    throw new Error('write failed');
  });
  await new EditorDelivery(host).insertLocalImage();
  assert.deepEqual(toasts, ['图片插入失败，请重试']);
  assert.equal(host.calls.edits, 0);
} });
cases.push({ name: 'image picker reports success only after the insert write resolves', async body() {
  toasts.length = 0;
  const host = deliveryHost(script => script.includes('getSelectionRange') ? '{"from":0,"to":0}' : undefined);
  await new EditorDelivery(host).insertLocalImage();
  assert.deepEqual(toasts, ['已插入 picked.png']);
  assert.equal(host.calls.edits, 1);
} });
// ---- 资料库重命名：复用 FileNameValidator，非法名不得进入文件操作 ----
const { HomeController } = load(path.join(root, 'entry/src/main/ets/features/home/HomeController.ets'));
function homeHost(renamingFrom, renameText, library) {
  const host = Object.create(HomeController.prototype);
  host.state = { renamingFrom, renameText, searchQuery: '' };
  const renamed = [];
  host.env = {
    fileSource: {
      listLibrary: () => library.slice(),
      renameLibrary: (from, to) => { renamed.push(`${from}>${to}`); return true; },
    },
    meta: { loadRecent: async () => [], saveRecent: async () => {} },
  };
  host.uiContext = {};
  host.refresh = () => {};
  host.refreshLibrary = () => {};
  host.runSearch = () => {};
  return { host, renamed };
}
cases.push({ name: 'library rename rejects hidden, control and separator names', async body() {
  for (const item of [['.hidden', '文件名不能以点开头'], ['bad\u0000name', '文件名不能包含控制字符'],
    ['../evil', '文件名不能包含路径分隔符']]) {
    toasts.length = 0;
    const { host, renamed } = homeHost('old.md', item[0], ['old.md']);
    await host.confirmRename();
    assert.equal(renamed.length, 0, item[0]);
    assert.deepEqual(toasts, [item[1]], item[0]);
  }
} });
cases.push({ name: 'library rename keeps duplicate-name rejection', async body() {
  toasts.length = 0;
  const { host, renamed } = homeHost('old.md', 'taken', ['old.md', 'taken.md']);
  await host.confirmRename();
  assert.equal(renamed.length, 0);
  assert.deepEqual(toasts, ['名称已存在']);
} });
cases.push({ name: 'library rename appends markdown extension and renames once', async body() {
  toasts.length = 0;
  const { host, renamed } = homeHost('old.md', 'new name', ['old.md']);
  await host.confirmRename();
  assert.deepEqual(renamed, ['old.md>new name.md']);
  assert.deepEqual(toasts, ['已重命名为 new name.md']);
} });
cases.push({ name: 'library rename keeps HTML extension for an HTML document', async body() {
  toasts.length = 0;
  const { host, renamed } = homeHost('page.html', 'newpage', ['page.html']);
  await host.confirmRename();
  assert.deepEqual(renamed, ['page.html>newpage.html']);
} });
cases.push({ name: 'library rename to the same normalized name is a silent no-op', async body() {
  toasts.length = 0;
  const { host, renamed } = homeHost('old.md', 'old', ['old.md']);
  await host.confirmRename();
  assert.equal(renamed.length, 0);
  assert.deepEqual(toasts, []);
} });
(async () => {
  let failures = 0;
  for (const item of cases) {
    try { await item.body(); }
    catch (error) { failures++; console.error(`FAIL ${item.name}:`, error); }
  }
  // The only recursive delete is the exact directory freshly allocated above by mkdtemp.
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`${cases.length - failures}/${cases.length} host tests passed (platform IO mocked)`);
  process.exitCode = failures ? 1 : 0;
})();
