const assert = require('node:assert/strict');
const path = require('node:path');
const { buildSync } = require('../web-tools/node_modules/esbuild');
const source = path.join(__dirname, '../web-tools/src/html-embed.js');
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
assert.ok(require('../web-tools/node_modules/entities').decodeHTML(bundleHtml(escaped,
  { 'images/a b.png': resources['images/photo.png'] })).includes('中文🙂'));
const attacks = '<meta http-equiv="refresh" content="0;url=https://evil.invalid"><base href="file:///private/"><form action="https://evil.invalid"><button onclick="alert(1)">GO</button></form><a href="javascript:alert(1)">LINK</a><img src="../../secret.png">';
const safe = bundleHtml(attacks);
assert.ok(!safe.includes('evil.invalid')); assert.ok(!safe.includes('javascript:')); assert.ok(!safe.includes('onclick'));
assert.ok(!safe.includes('secret.png')); assert.ok(safe.includes('disabled'));
const largeCss = data('text/css', '/*' + 'x'.repeat(4 * 1024 * 1024 - 4) + '*/');
assert.throws(() => bundleHtml('<link rel="stylesheet" href="large.css">'.repeat(5), { 'large.css': largeCss }), /总量|展开/);
assert.throws(() => bundleHtml('<link rel="stylesheet" href="bad.css">', { 'bad.css': data('text/css', [0xff,0xfe]) }));

const markdownCode = buildSync({ entryPoints: [path.join(__dirname, '../web-tools/src/markdown.js')], bundle: true,
  platform: 'node', format: 'cjs', write: false }).outputFiles[0].text;
const markdown = { exports: {} }; new Function('module', 'exports', 'require', markdownCode)(markdown, markdown.exports, require);
const attachment = 'attachments/block.html';
const body = markdown.exports.renderMarkdown(`BEFORE\n\n![HTML](<${attachment}>)\n\nAFTER`, { [attachment]: data('text/html', bundled) });
assert.ok(body.indexOf('BEFORE') < body.indexOf('<iframe')); assert.ok(body.indexOf('<iframe') < body.indexOf('AFTER'));
assert.match(body, /sandbox=""/); assert.match(body, /src="data:text\/html;base64,/);
assert.ok(!body.includes('allow-scripts')); assert.ok(!body.includes('allow-same-origin'));
assert.deepEqual(JSON.parse(markdown.exports.inspectMarkdown(`![HTML](<${attachment}>)`)).images, [attachment]);
assert.ok(!markdown.exports.renderMarkdown('<script>BAD</script>').includes('<script>'));
console.log('10 HTML embed groups passed (graph, styles, imports, images, cycles, media, escapes, safety, inline position, attachment discovery)');
