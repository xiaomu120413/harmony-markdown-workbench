const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const createLoader = require('./lib/ets-loader.cjs');
const routes = [];
const load = createLoader({
  '@kit.AbilityKit': {}, '@kit.CoreFileKit': {}, '@kit.ArkTS': {}, '@kit.ArkData': {},
  '@kit.BasicServicesKit': {}, '@kit.ArkWeb': {},
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkUI': { promptAction: { showToast() {} }, router: { pushUrl: async r => routes.push(r), replaceUrl: async r => routes.push(r) } },
}, { Observed: cls => cls });
const root = path.join(__dirname, '../entry/src/main/ets');
const { DocumentIntake } = load(`${root}/domain/document/DocumentIntake`);
const { HtmlPreviewState, HtmlPreviewViewModel } = load(`${root}/features/preview/HtmlPreviewViewModel`);
const { InternalFileSource } = load(`${root}/infrastructure/file/InternalFileSource`);
const { ExternalUriFileSource } = load(`${root}/infrastructure/file/ExternalUriFileSource`);
const { MetadataStore } = load(`${root}/infrastructure/metadata/MetadataStore`);
const { EditorDocuments } = load(`${root}/features/editor/EditorDocuments`);
const { HomeController } = load(`${root}/features/home/HomeController`);
MetadataStore.prototype.loadRecent = async () => [];
MetadataStore.prototype.saveRecent = async () => {};
const fixture = () => {
  const state = new HtmlPreviewState(), calls = [];
  const model = new HtmlPreviewViewModel(state, {}, { loadData: (...args) => calls.push(args) });
  return { state, model, calls };
};
(async () => {
  for (const id of ['file://docs/a%20b.HTML?grant=1', 'file://docs/a.htm', 'library/a.html']) {
    assert.equal(DocumentIntake.page(id), 'pages/HtmlPreviewPage');
  }
  assert.equal(DocumentIntake.select(['file://docs/a.HTM']), 'file://docs/a.HTM');
  assert.equal(DocumentIntake.page('library/a.html.md'), 'pages/EditorPage');
  assert.throws(() => DocumentIntake.select(['file://docs/a.pdf']));
  new EditorDocuments({}).openReceivedDocument('library/a.html');
  assert.equal(routes[0].url, 'pages/HtmlPreviewPage');
  assert.equal(routes[0].params.name, 'library/a.html');
  const renames = [];
  for (const newName of ['renamed', 'renamed.htm']) {
    await HomeController.prototype.confirmRename.call({
      state: { renamingFrom: 'a.html', renameText: newName },
      env: { fileSource: { listLibrary: () => [], renameLibrary: (old, next) => { renames.push(next); return false; } } },
    });
  }
  assert.deepEqual(renames, ['renamed.html', 'renamed.htm']);

  const payload = '<h1>Preview</h1><style>h1{color:green}</style><script>document.body.textContent="BAD"</script>';
  InternalFileSource.prototype.read = async () => ({ content: payload, validUtf8: true, revision: { size: payload.length } });
  const ok = fixture();
  await ok.model.load({ name: 'library/a.html' });
  assert.equal(ok.calls.length, 0); // Read can finish before Web is attached.
  ok.model.attach();
  ok.model.attach(); // onPageEnd after loadData must not trigger a reload loop.
  assert.equal(ok.calls.length, 1);
  const [html, mime, encoding, base] = ok.calls[0];
  assert.ok(html.indexOf('Content-Security-Policy') < html.indexOf(payload));
  for (const rule of ["default-src 'none'", "script-src 'none'", "frame-src 'none'", "form-action 'none'", 'img-src data:']) {
    assert.ok(html.includes(rule));
  }
  assert.ok(html.includes(payload)); // Original layout preserved, execution blocked by CSP and native Web settings.
  assert.equal(mime, 'text/html'); assert.equal(encoding, 'utf-8'); assert.equal(base, 'https://mumark.invalid/');
  assert.match(ok.state.status, /只读/);

  let retain;
  ExternalUriFileSource.prototype.read = () => new Promise(resolve => { retain = resolve; });
  const disposed = fixture(); disposed.model.attach();
  const pending = disposed.model.load({ uri: 'file://docs/a.html' });
  disposed.model.dispose(); retain({ content: payload, validUtf8: true }); await pending;
  assert.equal(disposed.calls.length, 0);
  for (const result of [{ content: 'bad', validUtf8: false }, { content: 'x', validUtf8: true, revision: { size: 8 * 1024 * 1024 + 1 } }]) {
    InternalFileSource.prototype.read = async () => result;
    const invalid = fixture(); invalid.model.attach(); await invalid.model.load({ name: 'library/a.html' });
    assert.equal(invalid.calls.length, 0); assert.match(invalid.state.status, /无法预览/);
  }
  InternalFileSource.prototype.read = async () => { throw new Error('access denied'); };
  const denied = fixture(); await denied.model.load({ name: 'library/a.html' });
  assert.match(denied.state.status, /access denied/);
  const page = fs.readFileSync(`${root}/pages/HtmlPreviewPage.ets`, 'utf8');
  assert.ok(page.includes('.javaScriptAccess(false).fileAccess(false).blockNetwork(true)'));
  assert.ok(page.includes("return url !== 'about:blank' && url !== 'https://mumark.invalid/';"));
  assert.ok(!page.includes('javaScriptProxy'));
  console.log('8 HTML preview groups passed (routing, attachment order, CSP, read failure, encoding, size, disposal, native policy)');
})().catch(error => { console.error(error); process.exitCode = 1; });
