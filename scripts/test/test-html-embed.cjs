const assert = require('node:assert/strict');
const path = require('node:path');
const { buildSync } = require('../../web-tools/node_modules/esbuild');
const source = path.join(__dirname, '../../web-tools/src/html-embed.js');
const code = buildSync({ entryPoints: [source], bundle: true, platform: 'browser', format: 'cjs', write: false }).outputFiles[0].text;
const moduleObject = { exports: {} };
new Function('module', 'exports', 'require', code)(moduleObject, moduleObject.exports, require);
const { inspectHtml, bundleHtml } = moduleObject.exports;
const data = (mime, value) => `data:${mime};base64,${Buffer.from(value).toString('base64')}`;
const html = '<!doctype html><link rel="stylesheet" href="styles/main.css"><h1>HELLO</h1><img src="images/photo.png" onerror="alert(1)"><div style="background:url(images/photo.png)">CSS</div><script>BAD_EXECUTION</script><iframe src="https://example.com"></iframe>';
const resources = {
  'styles/main.css': data('text/css', '@import url("nested.css");body{background:url(../images/background.png)}'),
  'styles/nested.css': data('text/css', 'h1{color:purple}'),
  'images/photo.png': data('image/png', [137,80,78,71]),
  'images/background.png': data('image/png', [137,80,78,72]),
};
assert.deepEqual(JSON.parse(inspectHtml(html)), ['styles/main.css', 'images/photo.png']);
const needed = JSON.parse(inspectHtml(html, { 'styles/main.css': resources['styles/main.css'] }));
assert.ok(needed.includes('styles/nested.css')); assert.ok(needed.includes('images/background.png'));
assert.throws(() => bundleHtml(html), /缺少/);
const bundled = bundleHtml(html, resources);
assert.ok(bundled.includes('HELLO')); assert.ok(bundled.includes('color:purple'));
assert.ok(bundled.includes(resources['images/photo.png'])); assert.ok(bundled.includes(resources['images/background.png']));
assert.ok(!bundled.includes('BAD_EXECUTION')); assert.ok(!bundled.includes('onerror')); assert.ok(!bundled.includes('<iframe'));
assert.ok(!bundled.includes('@import')); assert.ok(bundled.indexOf('Content-Security-Policy') < bundled.indexOf('HELLO'));
assert.ok(bundled.includes("script-src 'none'"));
const cyclic = { ...resources, 'styles/nested.css': data('text/css', '@import "main.css";h1{color:purple}') };
assert.ok(bundleHtml(html, cyclic).includes('color:purple'));
const media = { ...resources, 'styles/main.css': data('text/css', '@import "nested.css" screen;') };
assert.ok(bundleHtml(html, media).includes('@media screen'));
const escaped = '<style>p{background:url("images/a\\20 b.png")}</style><p>中文🙂</p>';
assert.deepEqual(JSON.parse(inspectHtml(escaped)), ['images/a b.png']);
assert.ok(require('../../web-tools/node_modules/entities').decodeHTML(bundleHtml(escaped,
  { 'images/a b.png': resources['images/photo.png'] })).includes('中文🙂'));
const attacks = '<meta http-equiv="refresh" content="0;url=https://evil.invalid"><base href="file:///private/"><form action="https://evil.invalid"><button onclick="alert(1)">GO</button></form><a href="javascript:alert(1)">LINK</a><img src="../../secret.png">';
const safe = bundleHtml(attacks);
assert.ok(!safe.includes('evil.invalid')); assert.ok(!safe.includes('javascript:')); assert.ok(!safe.includes('onclick'));
assert.ok(!safe.includes('secret.png')); assert.ok(safe.includes('disabled'));
const largeCss = data('text/css', '/*' + 'x'.repeat(4 * 1024 * 1024 - 4) + '*/');
assert.throws(() => bundleHtml('<link rel="stylesheet" href="large.css">'.repeat(5), { 'large.css': largeCss }), /总量|展开/);
assert.throws(() => bundleHtml('<link rel="stylesheet" href="bad.css">', { 'bad.css': data('text/css', [0xff,0xfe]) }));

const markdownCode = buildSync({ entryPoints: [path.join(__dirname, '../../web-tools/src/markdown.js')], bundle: true,
  platform: 'node', format: 'cjs', write: false }).outputFiles[0].text;
const markdown = { exports: {} }; new Function('module', 'exports', 'require', markdownCode)(markdown, markdown.exports, require);
const attachment = 'attachments/block.html';
const body = markdown.exports.renderMarkdown(`BEFORE\n\n![HTML](<${attachment}>)\n\nAFTER`, { [attachment]: data('text/html', bundled) });
assert.ok(body.indexOf('BEFORE') < body.indexOf('<iframe')); assert.ok(body.indexOf('<iframe') < body.indexOf('AFTER'));
assert.match(body, /sandbox=""/); assert.match(body, /src="data:text\/html;base64,/);
assert.ok(!body.includes('allow-scripts')); assert.ok(!body.includes('allow-same-origin'));
assert.deepEqual(JSON.parse(markdown.exports.inspectMarkdown(`![HTML](<${attachment}>)`)).images, [attachment]);
assert.ok(!markdown.exports.renderMarkdown('<script>BAD</script>').includes('<script>'));
const txt = 'attachments/note.txt';
const plain = '中文🙂\n<script>BAD</script>\n![图片](https://evil.invalid/a.png)';
const txtBody = markdown.exports.renderMarkdown(`BEFORE\n\n![TXT](<${txt}>)\n\nAFTER`, { [txt]: data('text/plain', plain) });
assert.ok(txtBody.indexOf('BEFORE') < txtBody.indexOf('txt-embed'));
assert.ok(txtBody.indexOf('txt-embed') < txtBody.indexOf('AFTER'));
assert.ok(txtBody.includes('中文🙂')); assert.ok(txtBody.includes('&lt;script&gt;BAD&lt;/script&gt;'));
assert.ok(!txtBody.includes('<script>')); assert.ok(!txtBody.includes('<img')); assert.ok(!txtBody.includes('<iframe'));
assert.deepEqual(JSON.parse(markdown.exports.inspectMarkdown(`![TXT](<${txt}>)`)).images, [txt]);
assert.ok(markdown.exports.renderMarkdown(`![TXT](<${txt}>)`, { [txt]: data('text/plain', '') }).includes('空文本'));
assert.ok(markdown.exports.renderMarkdown(`![TXT](<${txt}>)`, { [txt]: data('text/plain', [255]) }).includes('读取失败'));

// ---- 预览 DOM：相同 iframe/图片复用原节点，避免每次刷新重新加载导致闪白 ----
class FakeNode {
  constructor(tag) { this.tagName = tag; this.attrs = Object.create(null); this.childNodes = []; this.parentNode = null; }
  get firstChild() { return this.childNodes.length > 0 ? this.childNodes[0] : null; }
  appendChild(node) {
    if (node.parentNode) { node.parentNode.removeChild(node); }
    node.parentNode = this; this.childNodes.push(node); return node;
  }
  removeChild(node) {
    const index = this.childNodes.indexOf(node);
    if (index >= 0) { this.childNodes.splice(index, 1); node.parentNode = null; }
    return node;
  }
  replaceWith(node) {
    const parent = this.parentNode; if (!parent) { return; }
    const index = parent.childNodes.indexOf(this); if (index < 0) { return; }
    if (node.parentNode) { node.parentNode.removeChild(node); }
    parent.childNodes[index] = node; node.parentNode = parent; this.parentNode = null;
  }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  getAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attrs, name) ? this.attrs[name] : null; }
  set innerHTML(html) {
    this.childNodes = [];
    const element = /<(iframe|img)\b([^>]*)>/gi;
    let match;
    while ((match = element.exec(html))) {
      const node = new FakeNode(match[1].toLowerCase());
      const attr = /([\w-]+)="([^"]*)"/g;
      let found;
      while ((found = attr.exec(match[2]))) { node.setAttribute(found[1], found[2]); }
      this.appendChild(node);
    }
  }
  get innerHTML() { return ''; }
  querySelectorAll(selector) {
    const found = [];
    const parsed = /^(\w+)\[([\w-]+)\]$/.exec(selector);
    if (!parsed) { return found; }
    const visit = node => {
      if (node.tagName === parsed[1] && node.getAttribute(parsed[2]) !== null) {
        const htmlEmbed = node.tagName !== 'iframe' ||
          (node.getAttribute('src') || '').startsWith('data:text/html;base64,');
        if (htmlEmbed) { found.push(node); }
      }
      for (const child of node.childNodes) { visit(child); }
    };
    for (const child of this.childNodes) { visit(child); }
    return found;
  }
}
const out = new FakeNode('out');
global.window = {};
global.document = { createElement: tag => new FakeNode(tag), getElementById: () => out, scrollingElement: { scrollTop: 0 } };
const previewCode = buildSync({ entryPoints: [path.join(__dirname, '../../web-tools/src/preview.js')], bundle: true,
  platform: 'browser', format: 'cjs', write: false }).outputFiles[0].text;
const preview = { exports: {} };
new Function('module', 'exports', 'require', previewCode)(preview, preview.exports, require);
const api = global.window.__previewApi;
assert.ok(api);
const embed = { [attachment]: data('text/html', bundled) };
api.render('before\n\n![HTML](<attachments/block.html>)\n\nafter', embed);
const first = out.querySelectorAll('iframe[sandbox]')[0];
assert.ok(first);
api.render('before 2\n\n![HTML](<attachments/block.html>)\n\nafter 2', embed);
assert.equal(out.querySelectorAll('iframe[sandbox]')[0], first);
api.render('before 3\n\n![HTML](<attachments/block.html>)\n\nafter 3', { [attachment]: data('text/html', '<p>changed</p>') });
assert.notEqual(out.querySelectorAll('iframe[sandbox]')[0], first);
const picture = { 'attachments/pic.png': data('image/png', [137, 80, 78, 71]) };
api.render('one\n\n![pic](<attachments/pic.png>)\n\ntwo', picture);
const image = out.querySelectorAll('img[src]')[0];
assert.ok(image);
api.render('one changed\n\n![pic](<attachments/pic.png>)\n\ntwo changed', picture);
assert.equal(out.querySelectorAll('img[src]')[0], image);
api.render('one changed\n\n![other](<attachments/pic.png>)\n\ntwo changed', picture);
assert.notEqual(out.querySelectorAll('img[src]')[0], image);
// 宿主只发增量：同一 epoch 复用 Web 缓存，epoch 变化后清空。
api.render('epoch same\n\n![HTML](<attachments/block.html>)', {}, 0);
assert.equal(out.querySelectorAll('iframe[sandbox]').length, 1);
api.render('epoch new\n\n![HTML](<attachments/block.html>)', {}, 1);
assert.equal(out.querySelectorAll('iframe[sandbox]').length, 0);
api.render('epoch new again\n\n![HTML](<attachments/block.html>)', embed, 1);
assert.equal(out.querySelectorAll('iframe[sandbox]').length, 1);
console.log('13 HTML embed groups passed (graph, styles, imports, images, cycles, media, escapes, safety, inline position, attachment discovery, iframe reuse, image reuse, resource delta)');
