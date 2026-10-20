import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? markdownFiles(file) : entry.name.endsWith('.md') ? [file] : [];
  });
}
const files = [path.join(root, 'README.md'), path.join(root, 'docs/MuMark-SDD.md'),
  ...markdownFiles(path.join(root, 'docs'))];
const errors = [];
for (const file of files) {
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(fs.readFileSync(file)); }
  catch { errors.push(`${path.relative(root, file)}: invalid UTF-8`); continue; }
  if (text.includes('\ufffd')) errors.push(`${path.relative(root, file)}: replacement character`);
  for (const match of text.matchAll(/!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)/g)) {
    const url = match[1].replace(/^<|>$/g, '');
    if (/^(https?:|mailto:|#)/i.test(url)) continue;
    const target = decodeURIComponent(url.split('#')[0]);
    if (target && !fs.existsSync(path.resolve(path.dirname(file), target))) {
      errors.push(`${path.relative(root, file)}: missing link ${url}`);
    }
  }
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
else console.log(`${files.length} Markdown files: UTF-8 and local links passed`);
