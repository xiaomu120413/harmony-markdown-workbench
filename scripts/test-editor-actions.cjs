/* Execute the actual non-UI page methods with narrow platform stubs.
 * This covers command dispatch/state, not ArkUI rendering or device permissions. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { transformSync, buildSync } = require('../web-tools/node_modules/esbuild');
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
const policyModule = { exports: {} };
vm.runInNewContext(buildSync({ entryPoints: [path.join(__dirname, '../entry/src/main/ets/domain/editor/ViewModePolicy.ets')],
  bundle: true, loader: { '.ets': 'ts' }, resolveExtensions: ['.ets', '.ts', '.js'],
  format: 'cjs', platform: 'node', write: false }).outputFiles[0].text, { module: policyModule, exports: policyModule.exports });
const { ViewModePolicy } = policyModule.exports;
const DefaultView = { EDIT: 'edit', PREVIEW: 'preview', SPLIT: 'split' };
const toasts = [];
const fixture = `class Page {
  bp = 'pc'; outlineVisible = false; fileSheetVisible = false; fileSheetSection = 'root';
  contentWidthVp = 1200; sidebarVisible = false; viewMode = 'edit';
  opens = 0; syncs = 0;
  openPhoneOutline() { this.opens++; this.fileSheetVisible = true; this.fileSheetSection = 'outline'; }
  syncDocNow() { this.syncs++; }
  ${method('toggleOutline')}
  ${method('enforceWorkspaceBudget')}
  ${method('showHelp')}
}
module.exports = Page;`;
const context = { module: { exports: {} }, ViewModePolicy, DefaultView,
  promptAction: { showToast: d => toasts.push(d) }, AlertDialog: { show: d => dialogs.push(d) } };
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

const cramped = new Page();
cramped.bp = 'tablet'; cramped.contentWidthVp = 676; cramped.sidebarVisible = true;
cramped.toggleOutline();
assert.equal(cramped.outlineVisible, false);
assert.equal(toasts.length, 1);
cramped.outlineVisible = true; cramped.viewMode = 'split';
cramped.enforceWorkspaceBudget();
assert.equal(cramped.outlineVisible, false);
assert.equal(cramped.viewMode, 'edit');
cramped.sidebarVisible = false; cramped.viewMode = 'split'; cramped.contentWidthVp = 1000;
cramped.toggleOutline();
assert.equal(cramped.outlineVisible, true);
assert.equal(cramped.viewMode, 'split');
cramped.contentWidthVp = 800; cramped.enforceWorkspaceBudget();
assert.equal(cramped.outlineVisible, true);
assert.equal(cramped.viewMode, 'edit');

wide.showHelp();
assert.equal(dialogs.length, 1);
assert.ok(dialogs[0].message.includes('\n'));
assert.equal(dialogs[0].message.includes('\\n'), false);
assert.ok(dialogs[0].message.includes('Ctrl+Shift+F'));
console.log('7 editor action scenarios passed (wide/narrow toggle, panel switch, help, cramped outline, resize budget, split outline)');
