/**
 * M0-03 尖峰：Web 编辑资源打包脚本（esbuild）。
 * 输出：entry/src/main/resources/rawfile/web/editor.bundle.js
 * 运行：node build-web.js（见 README「Web 编辑器构建」）
 */
const esbuild = require('esbuild');
const path = require('path');

const outDir = path.resolve(__dirname, '../entry/src/main/resources/rawfile/web');

esbuild.buildSync({
  entryPoints: [path.resolve(__dirname, 'src/editor.js')],
  bundle: true,
  format: 'iife',
  minify: false,
  target: ['chrome80'],
  outfile: path.join(outDir, 'editor.bundle.js'),
  logLevel: 'info',
});

console.log('[build-web] done ->', path.join(outDir, 'editor.bundle.js'));