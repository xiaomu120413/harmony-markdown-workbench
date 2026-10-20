const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { fileURLToPath, pathToFileURL } = require('node:url');
const createLoader = require('./lib/ets-loader.cjs');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'mumark-html-'));
const local = value => typeof value === 'string' && value.startsWith('file://') ? fileURLToPath(value) : value;
const io = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
  openSync: (p, mode) => ({ fd: fs.openSync(local(p), mode) }), closeSync: fs.closeSync,
  statSync: p => typeof p === 'number' ? fs.fstatSync(p) : fs.statSync(local(p)),
  lstatSync: p => fs.lstatSync(local(p)), accessSync: p => fs.existsSync(local(p)),
  readSync: (fd, data) => fs.readSync(fd, new Uint8Array(data)),
  writeSync: (fd, data) => fs.writeSync(fd, new Uint8Array(data)), fsyncSync: fs.fsyncSync,
  renameSync: fs.renameSync, unlinkSync: fs.unlinkSync,
  mkdirSync: (p, recursive) => { if (fs.existsSync(p)) throw new Error('EEXIST'); return fs.mkdirSync(p, { recursive: !!recursive }); },
};
const load = createLoader({
  '@kit.AbilityKit': {}, '@kit.CoreFileKit': { fileIo: io },
  '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } },
  '@kit.ArkTS': { util: { TextEncoder: { create: () => ({ encodeInto: s => new TextEncoder().encode(s) }) },
    TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } },
}, { canIUse: () => false });
const { HtmlResourceStore } = load(path.join(__dirname, '../../entry/src/main/ets/infrastructure/file/HtmlResourceStore'));
const B = HtmlResourceStore.BASE;
const source = path.join(temporary, 'source'), privateDir = path.join(temporary, 'private');
fs.mkdirSync(source); fs.mkdirSync(privateDir);
fs.mkdirSync(path.join(source, 'styles')); fs.mkdirSync(path.join(source, 'images'));
fs.writeFileSync(path.join(source, 'styles/main.css'), '@import "nested.css";body{background:url(../images/a.png)}');
fs.writeFileSync(path.join(source, 'styles/nested.css'), 'h1{color:green}');
fs.writeFileSync(path.join(source, 'images/a.png'), Buffer.from([137,80,78,71]));
const uri = p => pathToFileURL(p).href;
const store = root => new HtmlResourceStore(root || '');
(async () => {
  assert.equal(HtmlResourceStore.path(B + 'images/a%20b.png?version=1#x'), 'images/a b.png');
  for (const invalid of [B + '../secret.png', B + '%2e%2e/a.css', B + 'images/%2f../a.png', B + 'images/%5cfoo.png',
    B + '%252e%252e/a.png', B + '/a.css', B + 'a%00.png', 'file:///a.png', 'https://other.invalid/a.css']) {
    assert.throws(() => HtmlResourceStore.path(invalid), invalid);
  }
  for (const ext of ['js', 'html', 'json', 'woff', 'txt', 'exe', '__proto__']) assert.throws(() => HtmlResourceStore.mime('a.' + ext));
  assert.equal(HtmlResourceStore.mime('a.CSS'), 'text/css');
  const first = store();
  assert.throws(() => first.read(B + 'styles/main.css'));
  first.useFolder(uri(source));
  const css = first.read(B + 'styles/main.css'); assert.equal(css.mime, 'text/css');
  assert.match(Buffer.from(css.bytes).toString(), /nested.css/);
  assert.equal(first.read(B + 'styles/nested.css').mime, 'text/css');
  assert.deepEqual(Buffer.from(first.read(B + 'images/a.png').bytes), fs.readFileSync(path.join(source, 'images/a.png')));
  fs.renameSync(source, source + '-moved');
  assert.equal(Buffer.from(first.read(B + 'styles/nested.css').bytes).toString(), 'h1{color:green}');
  assert.equal(first.read(B + 'images/a.png').bytes.length, 4);
  const originalLstat = io.lstatSync;
  io.lstatSync = p => p.endsWith('/images') ? { isSymbolicLink: () => true } : originalLstat(p);
  const links = store(uri(source));
  assert.throws(() => links.read(B + 'images/a.png'), /符号链接/);
  io.lstatSync = originalLstat;
  const isolated = store();
  assert.throws(() => isolated.read(B + 'images/a.png'));
  fs.renameSync(source + '-moved', source);

  const selected = store();
  assert.throws(() => selected.read(B + 'styles/main.css'));
  selected.importFiles(['styles/main.css', 'styles/nested.css', 'images/a.png'].map(p => uri(path.join(source, p))));
  assert.equal(selected.read(B + 'styles/nested.css').mime, 'text/css');
  assert.equal(selected.read(B + 'images/a.png').bytes.length, 4);
  assert.deepEqual(fs.readdirSync(privateDir), []); // No resource cache or inferred folder grant is persisted.
  assert.throws(() => selected.importFiles([uri(path.join(source, 'unknown.png'))]));

  fs.writeFileSync(path.join(source, 'large.png'), Buffer.alloc(4 * 1024 * 1024 + 1));
  assert.throws(() => first.read(B + 'large.png'), /limit|限制/);
  const budget = store();
  const large = new Uint8Array(4 * 1024 * 1024);
  for (let i = 0; i < 8; i++) budget.put('image' + i + '.png', large, 'image/png');
  assert.throws(() => budget.put('overflow.png', new Uint8Array(1), 'image/png'));
  budget.put('image0.png', large, 'image/png'); // Repeated reads do not double-count.
  const count = store();
  for (let i = 0; i < 128; i++) count.put('image' + i + '.png', new Uint8Array(1), 'image/png');
  assert.throws(() => count.put('overflow.png', new Uint8Array(1), 'image/png'));
  fs.writeFileSync(path.join(source, 'images/a.png'), Buffer.from([1,2,3]));
  const fresh = store(uri(source));
  assert.equal(fresh.read(B + 'images/a.png').bytes.length, 3);
  assert.equal(first.read(B + 'images/a.png').bytes.length, 4); // Each insertion gets a new snapshot.
  console.log('10 HTML resource groups passed (paths, types, folder, CSS, image, temporary snapshot, isolation, file grants, budgets, fresh insertion)');
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => {
  assert.equal(path.dirname(path.resolve(temporary)), path.resolve(os.tmpdir()));
  assert.ok(path.basename(temporary).startsWith('mumark-html-'));
  fs.rmSync(temporary, { recursive: true, force: true });
});
