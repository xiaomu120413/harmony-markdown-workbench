/* Execute the actual non-UI page methods with narrow platform stubs.
 * This covers command dispatch/state, not ArkUI rendering or device permissions. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { transformSync } = require('../web-tools/node_modules/esbuild');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/EditorPage.ets'), 'utf8');

function method(name) {
  const start = source.indexOf(`  private ${name}(): void {`);
  assert.notEqual(start, -1, `Missing page method ${name}`);
  let pos = source.indexOf('{', start) + 1;
  let depth = 1;
  let quote = '';
  for (; depth && pos < source.length; pos++) {
    const c = source[pos];
    if (quote) {
      if (c === '\\') { pos++; continue; }
      if (c === quote) quote = '';
    } else if (['"', "'", '`'].includes(c)) quote = c;
    else if (c === '{') depth++;
    else if (c === '}') depth--;
  }
  assert.equal(depth, 0, `Unclosed method ${name}`);
  return source.slice(start, pos);
}

const dialogs = [];
const fixture = `class Page {
  bp = 'pc'; outlineVisible = false; fileSheetVisible = false; fileSheetSection = 'root';
  opens = 0; syncs = 0;
  openPhoneOutline() { this.opens++; this.fileSheetVisible = true; this.fileSheetSection = 'outline'; }
  syncDocNow() { this.syncs++; }
  ${method('toggleOutline')}
  ${method('showHelp')}
}
module.exports = Page;`;
const context = { module: { exports: {} }, AlertDialog: { show: d => dialogs.push(d) } };
vm.runInNewContext(transformSync(fixture, { loader: 'ts', format: 'cjs' }).code, context);
const Page = context.module.exports;
const wide = new Page();
wide.toggleOutline();
assert.equal(wide.outlineVisible, true);
assert.equal(wide.syncs, 1);
wide.toggleOutline();
assert.equal(wide.outlineVisible, false);
assert.equal(wide.opens, 0);

const narrow = new Page();
narrow.bp = 'phone';
narrow.outlineVisible = true; // Normalize stale inline state as well.
narrow.toggleOutline();
assert.equal(narrow.outlineVisible, false);
assert.equal(narrow.fileSheetVisible, true);
assert.equal(narrow.fileSheetSection, 'outline');
assert.equal(narrow.syncs, 0);
narrow.toggleOutline();
assert.equal(narrow.fileSheetVisible, false);
assert.equal(narrow.opens, 1);
narrow.fileSheetVisible = true;
narrow.fileSheetSection = 'export';
narrow.toggleOutline();
assert.equal(narrow.fileSheetSection, 'outline');
assert.equal(narrow.opens, 2);

wide.showHelp();
assert.equal(dialogs.length, 1);
assert.ok(dialogs[0].message.includes('\n'));
assert.equal(dialogs[0].message.includes('\\n'), false);
assert.ok(dialogs[0].message.includes('Ctrl+Shift+F'));
console.log('4 editor action scenarios passed (wide toggle, narrow toggle, panel switch, help newlines)');
