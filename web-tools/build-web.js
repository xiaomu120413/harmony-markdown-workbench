/**
 * M0-03 尖峰：Web 编辑资源打包脚本（esbuild）。
 * 输出：entry/src/main/resources/rawfile/web/editor.bundle.js + editor.html（外部引用）。
 * 运行：node build-web.js（见 README「Web 编辑器构建」）
 */
const esbuild = require('esbuild');
const path = require('path');
const fs = require('fs');

const outDir = path.resolve(__dirname, '../entry/src/main/resources/rawfile/web');

esbuild.buildSync({
  entryPoints: [path.resolve(__dirname, 'src/editor.js')],
  bundle: true,
  format: 'iife',
  minify: true,
  target: ['chrome80'],
  outfile: path.join(outDir, 'editor.bundle.js'),
  logLevel: 'info',
});

const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>HMWB Editor Runtime</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
</style>
</head>
<body>
<script src="./editor.bundle.js"></script>
</body>
</html>`;

fs.writeFileSync(path.join(outDir, 'editor.html'), html, 'utf-8');
console.log('[build-web] done ->', path.join(outDir, 'editor.html'), '+ editor.bundle.js');