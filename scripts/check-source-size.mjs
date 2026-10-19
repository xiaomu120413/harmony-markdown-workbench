import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let count = 0;
const failures = [];
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root })
  .toString('utf8').split('\0').filter(Boolean);
for (const relative of files) {
  if (!/\.(ets|ts|js|mjs|cjs|py|sh|bat|ps1|cpp|h)$/.test(relative) || /\.bundle\.js$/.test(relative)) continue;
  const file = path.join(root, relative);
  if (!fs.existsSync(file)) continue;
  count++;
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split(/\r?\n/).length - (text.endsWith('\n') ? 1 : 0);
  if (lines > 500) failures.push(`${relative}: ${lines} lines`);
}
if (failures.length) { console.error(failures.join('\n')); process.exitCode = 1; }
else console.log(`${count} handwritten source/test/script files comply with the 500-line limit`);
