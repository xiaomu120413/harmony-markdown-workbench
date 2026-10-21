const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { buildSync } = require('../../web-tools/node_modules/esbuild');
const createLoader = require('./lib/ets-loader.cjs');
const root = path.resolve(__dirname, '../..');
const permissions = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/module.json5'), 'utf8')).module.requestPermissions;
assert.ok(!permissions.some(permission => permission.name === 'ohos.permission.READ_PASTEBOARD'));
const bundle = buildSync({ entryPoints: [path.join(root, 'web-tools/src/clipboard-image.js')], bundle: true,
  format: 'cjs', platform: 'node', write: false }).outputFiles[0].text;
const mod = { exports: {} }; new Function('module', 'exports', bundle)(mod, mod.exports);
const { handleImagePaste } = mod.exports;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==', 'base64');
const data = 'data:image/png;base64,' + png.toString('base64');
let reads = 0, readerFailure = false;
global.FileReader = class {
  readAsDataURL() { reads++; if (readerFailure) { this.onerror(); return; } this.result = data; this.onload(); }
};
function paste(items, extra = {}) {
  const sent = [], event = { isTrusted: true, clipboardData: { items }, prevented: false,
    preventDefault() { this.prevented = true; }, stopImmediatePropagation() {}, ...extra };
  handleImagePaste(event, { s: 'session', v: 3, from: 2, to: 5, editable: true }, (type, payload) => sent.push({ type, payload }));
  return { event, sent };
}
const item = (type = 'image/png', size = png.length) => ({ kind: 'file', type, getAsFile: () => ({ type, size }) });
assert.equal(paste([{ kind: 'string', type: 'text/plain' }]).event.prevented, false);
assert.equal(reads, 0);
assert.equal(paste([item()], { isTrusted: false }).sent.length, 0);
const accepted = paste([item()]); assert.equal(accepted.event.prevented, true);
assert.equal(accepted.sent[0].payload.data, data); assert.equal(accepted.sent[0].payload.from, 2);
assert.equal(accepted.sent[0].payload.to, 5); assert.equal(accepted.sent[0].payload.s, 'session');
assert.equal(paste([item('image/svg+xml')]).sent[0].payload.error, 'format');
assert.equal(paste([item('image/png', 20 * 1024 * 1024 + 1)]).sent[0].payload.error, 'size');
assert.equal(paste([item(), item()]).sent[0].payload.error, 'multiple');
readerFailure = true; assert.equal(paste([item()]).sent[0].payload.error, 'read'); readerFailure = false;
let readOnlyNotified = false;
handleImagePaste({ isTrusted: true }, { editable: false }, () => { readOnlyNotified = true; });
assert.equal(readOnlyNotified, false);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mumark-paste-'));
const toasts = [], logs = [];
const io = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY,
    CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
  accessSync: fs.existsSync, mkdirSync: fs.mkdirSync, unlinkSync: fs.unlinkSync, renameSync: fs.renameSync,
  openSync: (file, flags) => ({ fd: fs.openSync(file, flags) }), closeSync: fs.closeSync, fsyncSync: fs.fsyncSync,
  writeSync: (fd, bytes) => fs.writeSync(fd, new Uint8Array(bytes)),
};
const kits = {
  '@kit.AbilityKit': {}, '@kit.ArkData': {}, '@kit.CoreFileKit': { fileIo: io },
  '@kit.ArkTS': { util: { Base64Helper: class { decodeSync(s) { return new Uint8Array(Buffer.from(s, 'base64')); } } } },
  '@kit.BasicServicesKit': {}, '@kit.ArkUI': { promptAction: { showToast: ({ message }) => toasts.push(message) } },
  '@kit.PerformanceAnalysisKit': { hilog: Object.fromEntries(['warn', 'error', 'info'].map(level => [level, (...args) => logs.push(args)])) },
};
const load = createLoader(kits);
const { InternalFileSource } = load(path.join(root, 'entry/src/main/ets/infrastructure/file/InternalFileSource'));
const { EditorDelivery } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorDelivery'));
(async () => {
  try {
    const internal = new InternalFileSource({ filesDir: dir });
    const id = internal.savePastedImage(data);
    assert.match(id, /^attachments\/paste-[\d-]+\.png$/);
    assert.deepEqual(fs.readFileSync(path.join(dir, id)), png);
    for (const invalid of ['data:image/svg+xml;base64,AAAA', 'data:image/png;base64,', 'data:image/jpeg;base64,' + png.toString('base64')]) {
      assert.throws(() => internal.savePastedImage(invalid));
    }
    assert.throws(() => internal.savePastedImage('x'.repeat(28 * 1024 * 1024 + 1)), /20 MB/);
    for (const mode of ['success', 'changed', 'throw', 'stale', 'busy', 'invalid', 'format']) {
      const removed = [], scripts = []; let saved = 0, marked = 0;
      const host = { state: { loadState: 'ready', deliveryBusy: mode === 'busy', dropBusy: false },
        env: { activeSession: 'session', controller: {}, internal: {
          savePastedImage() { saved++; return id; }, remove(source) { removed.push(source.relativePath); },
        } }, isActive: () => true, markEdited() { marked++; },
        async runJsChecked(_, script) { scripts.push(script); if (mode === 'throw') throw Error('bridge failed');
          return mode === 'changed' ? 'false' : 'true'; } };
      const payload = { s: mode === 'stale' ? 'old' : 'session', v: 3, from: 2, to: 5, data };
      if (mode === 'invalid') payload.from = -1;
      if (mode === 'format') payload.error = 'format';
      await new EditorDelivery(host).pasteImage(payload);
      assert.equal(saved, ['success', 'changed', 'throw'].includes(mode) ? 1 : 0);
      assert.equal(marked, mode === 'success' ? 1 : 0);
      assert.deepEqual(removed, ['changed', 'throw'].includes(mode) ? [id] : []);
      if (mode === 'success') assert.match(scripts[0], /insertPastedImage\(.*"session", 3, 2, 5\)/);
      if (mode !== 'busy') assert.equal(host.state.deliveryBusy, false);
    }
    assert.ok(toasts.includes('已粘贴图片')); assert.ok(logs.length > 0);
    console.log('clipboard image checks passed (system-event boundary mocked; actual Web handler, storage and delivery modules)');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); delete global.FileReader; }
})().catch(error => { console.error(error); process.exitCode = 1; });
