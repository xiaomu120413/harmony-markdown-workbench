import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root })
  .toString('utf8').split('\0').filter(Boolean);
const extensions = new Set(['.ets','.ts','.js','.mjs','.cjs','.json','.json5','.md','.html','.css','.svg','.xml','.yaml','.yml','.txt']);
let count = 0;
const errors = [];
for (const file of files) {
  if (!extensions.has(path.extname(file)) || !fs.existsSync(path.join(root, file))) continue;
  count++;
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(fs.readFileSync(path.join(root, file)));
    if (text.includes('\ufffd')) errors.push(`${file}: contains U+FFFD (review possible replacement loss)`);
  } catch { errors.push(`${file}: invalid UTF-8`); }
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
else console.log(`${count} source/config/document text files passed strict UTF-8 checks`);
